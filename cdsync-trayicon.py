#!/usr/bin/env python3
import os
import signal
import subprocess
import fcntl
import gi
import hashlib
import re

# GTK and AppIndicator setup
gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
from gi.repository import Gtk, AppIndicator3, GLib

class LogWindow(Gtk.Window):
    def __init__(self, log_path):
        super().__init__(title="CDSync Logs")
        self.set_default_size(600, 400)
        self.set_border_width(10)
        # Position near the mouse to feel "attached" to the tray icon
        self.set_position(Gtk.WindowPosition.MOUSE)
        self.log_path = log_path

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.add(vbox)

        # Scrolled Window
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_vexpand(True)
        scrolled.set_hexpand(True)
        vbox.pack_start(scrolled, True, True, 0)

        # Text View
        self.textview = Gtk.TextView()
        self.textview.set_editable(False)
        self.textview.set_monospace(True)
        self.textview.set_wrap_mode(Gtk.WrapMode.NONE) # No wrap for logs usually better
        scrolled.add(self.textview)

        # Button Box
        bbox = Gtk.ButtonBox(orientation=Gtk.Orientation.HORIZONTAL)
        bbox.set_layout(Gtk.ButtonBoxStyle.END)
        vbox.pack_start(bbox, False, False, 0)

        btn_refresh = Gtk.Button(label="Refresh")
        btn_refresh.connect("clicked", self.load_logs)
        bbox.add(btn_refresh)

        btn_close = Gtk.Button(label="Close")
        btn_close.connect("clicked", self.on_close)
        bbox.add(btn_close)

        self.load_logs()
        self.show_all()

    def load_logs(self, widget=None):
        buffer = self.textview.get_buffer()
        if not os.path.exists(self.log_path):
            buffer.set_text("Log file not found.")
            return

        try:
            file_size = os.path.getsize(self.log_path)
            limit = 1024 * 1024 # 1MB

            with open(self.log_path, "r", errors='replace') as f:
                if file_size > limit:
                    f.seek(file_size - limit)
                    content = f.read()
                    # Discard the first partial line to avoid garbage
                    if '\n' in content:
                        content = content.split('\n', 1)[1]
                    
                    header = f"[WARNING: Log file is huge ({file_size / (1024*1024):.2f} MB). Showing last 1MB only...]\n"
                    buffer.set_text(header + content)
                else:
                    content = f.read()
                    buffer.set_text(content)
                
            # Scroll to end (must be queued to run after UI update)
            GLib.idle_add(self.scroll_to_end)
        except Exception as e:
            buffer.set_text(f"Error reading log: {e}")

    def scroll_to_end(self):
        buffer = self.textview.get_buffer()
        mark = buffer.create_mark("end", buffer.get_end_iter(), False)
        self.textview.scroll_to_mark(mark, 0.0, True, 0.0, 1.0)
        return False

    def on_close(self, widget):
        self.destroy()

class CDSyncIndicator:
    def __init__(self):
        # 1. Resolve paths
        self.base_dir = os.path.dirname(os.path.abspath(__file__))
        folder_name = os.path.basename(self.base_dir)
        dir_hash = hashlib.md5(self.base_dir.encode()).hexdigest()[:6]
        
        # Service Names
        self.service_name = f"cdsync-{folder_name}-{dir_hash}-watcher.service"
        self.timer_name = f"cdsync-{folder_name}-{dir_hash}-poll.timer"
        
        # App ID
        self.APPINDICATOR_ID = f"cdsync_indicator_{folder_name}"

        # 2. Resolve Lock File & Log File
        self.lock_file_path = self.get_lock_file_path()
        self.log_file_path = self.get_log_file_path()

        # 3. Configure Icons
        self.notifications_enabled = self.get_config_value("ENABLE_NOTIFICATIONS", "true") == "true"
        self.icon_idle = "emblem-default"
        self.icon_syncing = "mail-send-receive"
        self.icon_inactive = "dialog-warning"
        
        self.indicator = AppIndicator3.Indicator.new(
            self.APPINDICATOR_ID,
            self.icon_idle,
            AppIndicator3.IndicatorCategory.APPLICATION_STATUS
        )
        self.indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)

        # 4. Create the Menu
        self.menu = Gtk.Menu()
        
        # Status Label
        self.item_label = Gtk.MenuItem(label="CDSync: Checking...")
        self.item_label.set_sensitive(True) 
        self.item_label.connect("activate", self.toggle_service)
        self.menu.append(self.item_label)

        # Activity Label (Shows if currently syncing)
        self.activity_label = Gtk.MenuItem(label="")
        self.activity_label.set_sensitive(False)
        self.menu.append(self.activity_label)

        self.menu.append(Gtk.SeparatorMenuItem())

        # Activity Submenu
        self.item_activity = Gtk.MenuItem(label="📜 Activity")
        self.activity_menu = Gtk.Menu()
        self.item_activity.set_submenu(self.activity_menu)
        self.menu.append(self.item_activity)
        
        self.last_log_lines = []
        self.pending_action = None # None, 'disable', 'quit'
        
        # Link to full log window (added dynamically in update/rebuild or just once here? 
        # Actually proper place is inside the submenu or main menu? 
        # User asked for "option inside the activity submenu".
        # So we handle it in update_activity_menu)

        self.menu.append(Gtk.SeparatorMenuItem())
        
        # Manual Sync Button
        self.item_sync = Gtk.MenuItem(label="Sync Now")
        self.item_sync.connect("activate", self.manual_sync)
        self.menu.append(self.item_sync)

        self.menu.append(self.item_sync)

        self.menu.append(Gtk.SeparatorMenuItem())

        # Config Submenu
        self.item_config = Gtk.MenuItem(label="⚙️ Config")
        self.config_menu = Gtk.Menu()
        self.item_config.set_submenu(self.config_menu)
        self.menu.append(self.item_config)

        # Set Interval
        item_interval = Gtk.MenuItem(label="⏱️ Set Interval...")
        item_interval.connect("activate", self.change_interval_dialog)
        self.config_menu.append(item_interval)

        self.config_menu.append(Gtk.SeparatorMenuItem())

        # Move Force Resync here
        self.item_resync = Gtk.MenuItem(label="🔧 Force Resync (Repair)")
        self.item_resync.connect("activate", self.force_resync)
        self.config_menu.append(self.item_resync)

        # Quit Button
        self.menu.append(Gtk.SeparatorMenuItem())
        item_quit = Gtk.MenuItem(label="Quit Tray Icon")
        item_quit.connect("activate", self.quit)
        self.menu.append(item_quit)

        self.menu.show_all()
        
        # Hide activity label initially
        self.activity_label.hide()
        
        self.indicator.set_menu(self.menu)

        # 5. Start Check Loop (every 2 seconds)
        self.update_status()
        GLib.timeout_add_seconds(2, self.update_status)

    def get_config_value(self, var_name, default=None):
        """Reads config.env using bash to access variables"""
        try:
            cmd = f'source "{self.base_dir}/config.env"; echo ${var_name}'
            result = subprocess.check_output(cmd, shell=True, executable="/bin/bash").decode().strip()
            if not result:
                return default
            return result
        except Exception:
            return default

    def get_lock_file_path(self):
        return self.get_config_value("LOCK_FILE", "/tmp/cdsync_default.lock")

    def get_log_file_path(self):
        custom = self.get_config_value("CUSTOM_LOG_FILE", "")
        if custom:
            return custom
        return os.path.join(self.base_dir, "cdsync.log")

    def parse_log_line(self, line):
        """Parses a raw log line and returns a formatted string or None."""
        # Capture Timestamp: YYYY/MM/DD HH:MM:SS or YYYY-MM-DD HH:MM:SS
        # Rclone uses /, shell script uses -
        
        # Ex: "2025/12/09 15:00:00" OR "15:00:00"
        ts_match = re.search(r"(?:(\d{4}[/-]\d{2}[/-]\d{2})\s+)?(\d{2}:\d{2}:\d{2})", line)
        
        timestamp = ""
        if ts_match:
            try:
                date_part = ts_match.group(1)
                time_part = ts_match.group(2)
                
                if date_part:
                    # We have a date, format to [YYYY-MM-DD HH:MM]
                    full_date = date_part.replace('/', '-')
                    timestamp = f"[{full_date} {time_part[:5]}] "
                else:
                    # We only have time. Show [HH:MM]
                    timestamp = f"[{time_part[:5]}] "
            except:
                pass # Timestamp stays empty if parsing fails

        # Regex 1: Standard Action (Copied, Updated, Deleted, Moved)
        # Ex: "INFO  : folder/file.txt: Copied (new)"
        match_std = re.search(r"INFO\s+:\s+(.*?):\s+(Copied|Updated|Deleted|Moved)", line)
        if match_std:
            filename = os.path.basename(match_std.group(1).strip())
            action = match_std.group(2)
            
            icon = "✅" # Default for Copied
            if action == "Updated": icon = "🔄"
            elif action == "Deleted": icon = "🗑️"
            elif action == "Moved": icon = "➡️"
            
            return f"{timestamp}{icon} {filename}"

        # Regex 2: Bisync Newer
        # Ex: "INFO  : - Path2    File is newer       - (WORK)/file.txt"
        match_newer = re.search(r"INFO\s+:\s+-\s+Path[12]\s+File is newer\s+-\s+(.*)", line)
        if match_newer:
            filename = os.path.basename(match_newer.group(1).strip())
            return f"{timestamp}🆕 {filename}"
            
        return None

    def get_recent_activity(self):
        if not os.path.exists(self.log_file_path):
            return []
        try:
            # Read last 50KB to find enough relevant lines
            # Using python read instead of tail for better control
            file_size = os.path.getsize(self.log_file_path)
            limit = 50 * 1024 # 50KB
            
            content = ""
            with open(self.log_file_path, "r", errors='replace') as f:
                if file_size > limit:
                    f.seek(file_size - limit)
                content = f.read()
            
            lines = content.splitlines()
            found_items = []
            
            # Iterate backwards
            for line in reversed(lines):
                parsed = self.parse_log_line(line)
                if parsed:
                    found_items.append(parsed)
                    if len(found_items) >= 10:
                        break
            
            return found_items
        except Exception:
            return []

    def update_activity_menu(self):
        logs = self.get_recent_activity()
        
        # Optimization: Don't rebuild menu if logs haven't changed
        # This prevents the menu from auto-closing while the user is reading it
        if logs == self.last_log_lines:
            return

        self.last_log_lines = logs

        # Clear existing items
        for child in self.activity_menu.get_children():
            self.activity_menu.remove(child)
        
        if not logs:
            item = Gtk.MenuItem(label="(No recent logs)")
            item.set_sensitive(False)
            self.activity_menu.append(item)
        else:
            for line in logs:
                # Clean up date prefix for cleaner UI if possible, or just show raw
                # Example: "2023-12-01 10:00:00 - Message" -> keep it
                
                # Revert to simple label, no Pango markup hacks
                item = Gtk.MenuItem(label=line)
                item.set_sensitive(False) # Just for display
                self.activity_menu.append(item)

        self.activity_menu.append(Gtk.SeparatorMenuItem())
        
        item_full = Gtk.MenuItem(label="📂 Open Full Log...")
        item_full.connect("activate", self.open_log_window)
        self.activity_menu.append(item_full)
        
        self.activity_menu.show_all()

    def open_log_window(self, source):
        win = LogWindow(self.log_file_path)
        win.show()

    def is_sync_running(self):
        """Checks if the lock file is currently held by another process"""
        if not os.path.exists(self.lock_file_path):
            return False
            
        fp = None
        try:
            fp = open(self.lock_file_path, 'r')
            # Try to acquire a non-blocking exclusive lock
            # If it fails (IOError), it means someone else (the shell script) holds the lock
            fcntl.flock(fp, fcntl.LOCK_EX | fcntl.LOCK_NB)
            # If we got here, we locked it successfully, so no one else was using it.
            # Unlock and return False
            fcntl.flock(fp, fcntl.LOCK_UN)
            return False
        except IOError:
            return True # Could not lock, so it IS running
        finally:
            if fp: fp.close()

    def send_notification(self, title, message):
        if self.notifications_enabled:
            subprocess.Popen(["notify-send", "CDSync", f"{title}\n{message}"])

    def check_service_active(self):
        try:
            result = subprocess.run(
                ["systemctl", "--user", "is-active", self.service_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            return result.returncode == 0
        except Exception:
            return False

    def update_status(self):
        is_active = self.check_service_active()
        is_running = self.is_sync_running()

        # Update Service Status UI
        if is_active:
            if is_running:
                 self.indicator.set_icon(self.icon_syncing)
            else:
                 self.indicator.set_icon(self.icon_idle)
                 
            self.item_label.set_label("CDSync: 🟢 ACTIVE")
        else:
            self.indicator.set_icon(self.icon_inactive)
            self.item_label.set_label("CDSync: 🔴 STOPPED")

        # Update Activity UI (Sync in Progress)
        if is_running:
            if self.pending_action == 'disable':
                self.activity_label.set_label("⏳ Stop Pending... (Click 'CDSync' to cancel)")
                # We enable the label so user can click it to cancel? 
                # Actually toggle_service is connected to item_label ("CDSync: ...")
            if self.pending_action == 'disable':
                self.activity_label.set_label("⏳ Stop Pending... (Click 'CDSync' to cancel)")
                # We enable the label so user can click it to cancel? 
                # Actually toggle_service is connected to item_label ("CDSync: ...")
            else:
                self.activity_label.set_label("⚡ Sync in progress...")
                
            self.activity_label.show()
            
            # Enable the label so user can click it to queue a Stop action
            self.item_label.set_sensitive(True)
                
            self.item_sync.set_sensitive(False)
            self.item_resync.set_sensitive(False)
        else:
            # Sync just finished? Check pending actions
            if self.pending_action == 'disable':
                self.pending_action = None
                self.send_notification("Sync Finished", "Disabling service as requested.")
                # We need to force is_active to True so the toggle logic effectively stops it
                # calling toggle_service directly is safer but we need to mock the state
                # Actually, simply calling logic to stop:
                subprocess.run(["systemctl", "--user", "stop", self.service_name])
                subprocess.run(["systemctl", "--user", "stop", self.timer_name])
                subprocess.run(["systemctl", "--user", "disable", self.service_name])
                subprocess.run(["systemctl", "--user", "disable", self.timer_name])
                # Refresh status immediately
                self.update_status()
                return True
                # Refresh status immediately
                self.update_status()
                return True

            self.activity_label.hide()
            # Enable actions
            self.item_label.set_sensitive(True)
            self.item_sync.set_sensitive(True)
            self.item_resync.set_sensitive(True)

        self.update_activity_menu()
        return True

    def toggle_service(self, source):
        # 1. Is Sync Running?
        if self.is_sync_running():
             # If action is already pending, just cancel it (simple toggle behavior)
             if self.pending_action:
                 self.pending_action = None
                 self.send_notification("Action Cancelled", "Pending stop cancelled.\nService will continue running.")
                 self.update_status()
                 return
             
             # Sync is running and NO pending action. Ask user what to do.
             dialog = Gtk.MessageDialog(
                 parent=None,
                 flags=0,
                 message_type=Gtk.MessageType.QUESTION,
                 buttons=Gtk.ButtonsType.NONE,
                 text="Sync in Progress"
             )
             dialog.format_secondary_text("A synchronization is currently running.\nHow do you want to stop?")
             
             dialog.add_buttons(
                 "Cancel", Gtk.ResponseType.CANCEL,
                 "Wait for Finish (Graceful)", 1,
                 "Force Stop (KILL)", 2
             )
             
             # Style the "Force Stop" button as destructive if possible (Gtk 3 basic)
             
             response = dialog.run()
             dialog.destroy()
             
             if response == Gtk.ResponseType.CANCEL or response == Gtk.ResponseType.DELETE_EVENT:
                 return # Do nothing
                 
             elif response == 1: # Graceful
                 self.pending_action = 'disable'
                 self.send_notification("Scheduled", "Service will be disabled when sync finishes.")
                 self.update_status()
                 
             elif response == 2: # Force Kill
                 self.force_stop_sync()
             
             return

        is_active = self.check_service_active()
        
        if is_active:
            # STOP
            subprocess.run(["systemctl", "--user", "stop", self.service_name])
            subprocess.run(["systemctl", "--user", "stop", self.timer_name])
            subprocess.run(["systemctl", "--user", "disable", self.service_name])
            subprocess.run(["systemctl", "--user", "disable", self.timer_name])
        else:
            # START
            subprocess.run(["systemctl", "--user", "enable", self.service_name])
            subprocess.run(["systemctl", "--user", "enable", self.timer_name])
            subprocess.run(["systemctl", "--user", "start", self.service_name])
            subprocess.run(["systemctl", "--user", "start", self.timer_name])
        
        self.update_status()

    def manual_sync(self, source):
        if self.is_sync_running():
             self.send_notification("Ignored", "Sync is already running.")
             return

        # Run core script
        core_script = os.path.join(self.base_dir, "cdsync-core.sh")
        subprocess.Popen(["/bin/bash", core_script])
        
        self.send_notification("Manual Sync", "Synchronization started...")
        # Immediate update to show "Sync in progress" in the menu
        self.update_status()

    def force_resync(self, source):
        if self.is_sync_running():
             self.send_notification("Ignored", "Sync is already running.")
             return

        # Run core script with forced flag
        core_script = os.path.join(self.base_dir, "cdsync-core.sh")
        subprocess.Popen(["/bin/bash", core_script, "--force-resync"])
        
        self.send_notification("Repair Started", "Forced resync initiated...\nThis may take a while.")
        self.update_status()

    def change_interval_dialog(self, source):
        # 1. Ask user for new interval
        dialog = Gtk.Dialog(title="Set Sync Interval", parent=None, flags=0)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, "Set Minutes", Gtk.ResponseType.OK)
        dialog.set_default_size(300, 100)
        dialog.set_position(Gtk.WindowPosition.MOUSE)
        dialog.set_border_width(10)

        box = dialog.get_content_area()
        box.set_spacing(10)
        
        label = Gtk.Label(label="Enter new interval (in minutes):")
        box.add(label)
        
        entry = Gtk.Entry()
        # Try to get current value
        current = self.get_config_value("POLL_INTERVAL", "5")
        entry.set_text(current)
        box.add(entry)
        
        dialog.show_all()
        response = dialog.run()

        new_val = entry.get_text().strip()
        dialog.destroy()

        if response == Gtk.ResponseType.OK and new_val.isdigit() and int(new_val) > 0:
            self.apply_new_interval(new_val)

    def apply_new_interval(self, minutes):
        # 1. Update config.env
        config_path = os.path.join(self.base_dir, "config.env")
        try:
            with open(config_path, 'r') as f:
                content = f.read()
            
            # Regex replace or append
            if "POLL_INTERVAL=" in content:
                content = re.sub(r'POLL_INTERVAL=.*', f'POLL_INTERVAL={minutes}', content)
            else:
                content += f"\nPOLL_INTERVAL={minutes}\n"
            
            with open(config_path, 'w') as f:
                f.write(content)
                
        except Exception as e:
            self.send_notification("Error", f"Could not update config.env: {e}")
            return

        # 2. Update Systemd Timer File
        # Path: ~/.config/systemd/user/{timer_name}
        timer_path = os.path.expanduser(f"~/.config/systemd/user/{self.timer_name}")
        
        if os.path.exists(timer_path):
            try:
                with open(timer_path, 'r') as f:
                    t_content = f.read()
                
                # Replace OnUnitActiveSec=...min
                t_content = re.sub(r'OnUnitActiveSec=.*', f'OnUnitActiveSec={minutes}min', t_content)
                
                with open(timer_path, 'w') as f:
                    f.write(t_content)
                    
                # 3. Reload Systemd
                subprocess.run(["systemctl", "--user", "daemon-reload"])
                subprocess.run(["systemctl", "--user", "restart", self.timer_name])
                
                self.send_notification("Success", f"Sync interval set to {minutes} minutes.\nTimer restarted.")
                
            except Exception as e:
                self.send_notification("Error", f"Could not update timer: {e}")
        else:
             self.send_notification("Error", "Timer file not found. Run install.sh again?")

    def force_stop_sync(self):
        # 1. Kill rclone processes related to this sync
        subprocess.run(["pkill", "-f", "rclone bisync"])
        subprocess.run(["pkill", "-f", "cdsync-core.sh"])
        
        # 2. Remove Lock File
        if os.path.exists(self.lock_file_path):
            try:
                os.remove(self.lock_file_path)
            except:
                pass
                
        # 3. Stop Services
        subprocess.run(["systemctl", "--user", "stop", self.service_name])
        subprocess.run(["systemctl", "--user", "stop", self.timer_name])
        subprocess.run(["systemctl", "--user", "disable", self.service_name])
        subprocess.run(["systemctl", "--user", "disable", self.timer_name])

        self.send_notification("Force Stopped", "Sync process killed and services disabled.")
        self.update_status()

    def quit(self, source):
        # Immediate exit requested by user
        Gtk.main_quit()

if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    app = CDSyncIndicator()
    Gtk.main()

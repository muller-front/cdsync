#!/usr/bin/env python3
import os
import signal
import subprocess
import fcntl
import gi
import hashlib

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
        self.icon_active = "mail-send-receive"
        self.icon_inactive = "dialog-warning"
        
        self.indicator = AppIndicator3.Indicator.new(
            self.APPINDICATOR_ID,
            self.icon_inactive,
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
        
        # Link to full log window (added dynamically in update/rebuild or just once here? 
        # Actually proper place is inside the submenu or main menu? 
        # User asked for "option inside the activity submenu".
        # So we handle it in update_activity_menu)

        self.menu.append(Gtk.SeparatorMenuItem())
        
        # Manual Sync Button
        self.item_sync = Gtk.MenuItem(label="Sync Now")
        self.item_sync.connect("activate", self.manual_sync)
        self.menu.append(self.item_sync)

        # Quit Button
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

    def get_recent_activity(self):
        if not os.path.exists(self.log_file_path):
            return []
        try:
            # Read last 50 lines to ensure we find enough non-empty content
            lines = subprocess.check_output(['tail', '-n', '50', self.log_file_path]).decode().splitlines()
            # Filter empty lines and trim content
            non_empty = [line for line in lines if line.strip()]
            return [line[:80] + "..." if len(line) > 80 else line for line in non_empty][-10:]
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
            self.indicator.set_icon(self.icon_active)
            self.item_label.set_label("CDSync: 🟢 ACTIVE")
        else:
            self.indicator.set_icon(self.icon_inactive)
            self.item_label.set_label("CDSync: 🔴 STOPPED")

        # Update Activity UI (Sync in Progress)
        if is_running:
            self.activity_label.set_label("⚡ Sync in progress...")
            self.activity_label.show()
            # Disable actions to prevent corruption
            self.item_label.set_sensitive(False)
            self.item_sync.set_sensitive(False)
        else:
            self.activity_label.hide()
            # Enable actions
            self.item_label.set_sensitive(True)
            self.item_sync.set_sensitive(True)

        self.update_activity_menu()
        return True

    def toggle_service(self, source):
        # Double check lock before action
        if self.is_sync_running():
             self.send_notification("Cannot Disable", "A synchronization is currently in progress.\nPlease wait until it finishes.")
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

    def quit(self, source):
        Gtk.main_quit()

if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    app = CDSyncIndicator()
    Gtk.main()

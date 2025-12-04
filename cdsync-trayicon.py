#!/usr/bin/env python3
import os
import signal
import subprocess
import fcntl
import gi

# GTK and AppIndicator setup
gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
from gi.repository import Gtk, AppIndicator3, GLib

class CDSyncIndicator:
    def __init__(self):
        # 1. Resolve paths
        self.base_dir = os.path.dirname(os.path.abspath(__file__))
        folder_name = os.path.basename(self.base_dir)
        
        # Service Names
        self.service_name = f"cdsync-{folder_name}-watcher.service"
        self.timer_name = f"cdsync-{folder_name}-poll.timer"
        
        # App ID
        self.APPINDICATOR_ID = f"cdsync_indicator_{folder_name}"

        # 2. Resolve Lock File Path (reading from config.env via bash to handle $HOME expansion)
        self.lock_file_path = self.get_lock_file_path()

        # 3. Configure Icons
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
        self.menu.append(self.item_label)

        # Activity Label (Shows if currently syncing)
        self.activity_label = Gtk.MenuItem(label="")
        self.activity_label.set_sensitive(False)
        self.menu.append(self.activity_label)

        self.menu.append(Gtk.SeparatorMenuItem())

        # Toggle Button
        self.item_toggle = Gtk.MenuItem(label="Enable Sync")
        self.item_toggle.connect("activate", self.toggle_service)
        self.menu.append(self.item_toggle)

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

    def get_lock_file_path(self):
        """Reads config.env using bash to verify the LOCK_FILE variable"""
        try:
            cmd = f'source "{self.base_dir}/config.env"; echo $LOCK_FILE'
            result = subprocess.check_output(cmd, shell=True, executable="/bin/bash").decode().strip()
            if not result:
                # Default fallback if empty
                return "/tmp/cdsync_default.lock"
            return result
        except Exception:
            return "/tmp/cdsync_default.lock"

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
            self.item_toggle.set_label("Disable Sync")
        else:
            self.indicator.set_icon(self.icon_inactive)
            self.item_label.set_label("CDSync: 🔴 STOPPED")
            self.item_toggle.set_label("Enable Sync")

        # Update Activity UI (Sync in Progress)
        if is_running:
            self.activity_label.set_label("⚡ Sync in progress...")
            self.activity_label.show()
            # Disable actions to prevent corruption
            self.item_toggle.set_sensitive(False)
            self.item_sync.set_sensitive(False)
        else:
            self.activity_label.hide()
            # Enable actions
            self.item_toggle.set_sensitive(True)
            self.item_sync.set_sensitive(True)

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

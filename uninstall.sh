#!/bin/bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_DIR="$HOME/.config/systemd/user"
AUTOSTART_DIR="$HOME/.config/autostart"
SERVICE_NAME="cdsync-$(basename "$BASE_DIR")-$(echo -n "$BASE_DIR" | md5sum | cut -c1-6)"

echo "------------------------------------------------"
echo "🗑️  Uninstalling CDSync..."
echo "------------------------------------------------"

# 1. REMOVE TRAY ICON
echo "🛑 Stopping Tray Icon process..."
pkill -f "cdsync-trayicon.py"

if [ -f "$AUTOSTART_DIR/cdsync-tray.desktop" ]; then
    echo "Removing Autostart entry..."
    rm "$AUTOSTART_DIR/cdsync-tray.desktop"
fi

# 2. REMOVE SYSTEMD SERVICES
if [ -f "$SYSTEMD_DIR/$SERVICE_NAME-watcher.service" ]; then
    echo "🛑 Stopping Systemd services..."
    systemctl --user stop "$SERVICE_NAME-watcher.service"
    systemctl --user stop "$SERVICE_NAME-poll.timer"

    echo "Disabling services..."
    systemctl --user disable "$SERVICE_NAME-watcher.service"
    systemctl --user disable "$SERVICE_NAME-poll.timer"

    echo "Removing Systemd files..."
    rm "$SYSTEMD_DIR/$SERVICE_NAME-watcher.service"
    rm "$SYSTEMD_DIR/$SERVICE_NAME-poll.service"
    rm "$SYSTEMD_DIR/$SERVICE_NAME-poll.timer"
    
    systemctl --user daemon-reload
else
    echo "ℹ️  Systemd services not found. Skipping."
fi

echo "✅ UNINSTALLATION SUCCESSFUL!"
echo "Note: Configuration files, logs, and Python dependencies were NOT removed."

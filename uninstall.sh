#!/bin/bash

# Resolve directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_DIR="$HOME/.config/systemd/user"
SERVICE_NAME="cdsync-$(basename "$BASE_DIR")"

echo "------------------------------------------------"
echo "🗑️  Uninstalling CDSync services..."
echo "⚙️  Target Service Name: $SERVICE_NAME"
echo "------------------------------------------------"

# Check if services exist
if [ ! -f "$SYSTEMD_DIR/$SERVICE_NAME-watcher.service" ]; then
    echo "⚠️  Services not found in systemd. Is it installed?"
    exit 1
fi

# 1. Stop Services
echo "Stopping services..."
systemctl --user stop "$SERVICE_NAME-watcher.service"
systemctl --user stop "$SERVICE_NAME-poll.timer"

# 2. Disable Services
echo "Disabling services..."
systemctl --user disable "$SERVICE_NAME-watcher.service"
systemctl --user disable "$SERVICE_NAME-poll.timer"

# 3. Remove Files
echo "Removing systemd files..."
rm "$SYSTEMD_DIR/$SERVICE_NAME-watcher.service"
rm "$SYSTEMD_DIR/$SERVICE_NAME-poll.service"
rm "$SYSTEMD_DIR/$SERVICE_NAME-poll.timer"

# 4. Reload Daemon
systemctl --user daemon-reload

echo "✅ UNINSTALLATION SUCCESSFUL!"
echo "Note: Configuration files and logs in '$BASE_DIR' were NOT deleted."

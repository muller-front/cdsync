#!/bin/bash

# --- PRE-FLIGHT CHECKS ---

# 1. Check if Rclone is installed
if ! command -v rclone &> /dev/null; then
    echo "❌ ERROR: rclone is not installed."
    echo "Please install it first (e.g., sudo apt install rclone or via script)."
    exit 1
fi

# 2. Check if inotify-tools is installed
if ! command -v inotifywait &> /dev/null; then
    echo "❌ ERROR: inotify-tools is not installed."
    echo "Please install it: sudo apt install inotify-tools"
    exit 1
fi

# 3. Resolve directory and load config
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$BASE_DIR/config.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ ERROR: config.env not found."
    echo "Please copy config.env.example to config.env and edit it first."
    exit 1
fi

source "$CONFIG_FILE"

# 4. Check if Remote is Configured and Accessible
echo "🔍 Checking connection to remote '$RCLONE_REMOTE'..."
# We use 'lsd' (list directories) with depth 1 as a lightweight connectivity check
if rclone lsd "$RCLONE_REMOTE" --max-depth 1 --config "$HOME/.config/rclone/rclone.conf" &> /dev/null; then
    echo "✅ Remote '$RCLONE_REMOTE' is accessible."
else
    echo "❌ ERROR: Could not connect to remote '$RCLONE_REMOTE'."
    echo "Please check your 'config.env' or run 'rclone config' to fix authentication."
    exit 1
fi

# 5. Check if Local Directory exists
if [ ! -d "$LOCAL_SYNC_DIR" ]; then
    echo "⚠️  WARNING: Local directory '$LOCAL_SYNC_DIR' does not exist."
    read -p "Do you want to create it now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mkdir -p "$LOCAL_SYNC_DIR"
        echo "✅ Directory created."
    else
        echo "❌ Installation aborted."
        exit 1
    fi
fi

# --- INSTALLATION ---

SYSTEMD_DIR="$HOME/.config/systemd/user"
SERVICE_NAME="cdsync-$(basename "$BASE_DIR")"

echo "------------------------------------------------"
echo "🛠️  Installing CDSync services..."
echo "📂 Source: $BASE_DIR"
echo "⚙️  Service Name: $SERVICE_NAME"
echo "------------------------------------------------"

mkdir -p "$SYSTEMD_DIR"

# 1. Create Watcher Service
cat > "$SYSTEMD_DIR/$SERVICE_NAME-watcher.service" <<EOF
[Unit]
Description=CDSync Watcher ($BASE_DIR)
After=network.target

[Service]
ExecStart=/bin/bash "$BASE_DIR/cdsync-watcher.sh"
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

# 2. Create Polling Service
cat > "$SYSTEMD_DIR/$SERVICE_NAME-poll.service" <<EOF
[Unit]
Description=CDSync Polling ($BASE_DIR)

[Service]
ExecStart=/bin/bash "$BASE_DIR/cdsync-core.sh"
EOF

# 3. Create Polling Timer
cat > "$SYSTEMD_DIR/$SERVICE_NAME-poll.timer" <<EOF
[Unit]
Description=Timer for CDSync Polling ($BASE_DIR)

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=$SERVICE_NAME-poll.service

[Install]
WantedBy=timers.target
EOF

# 4. Enable Services
systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE_NAME-watcher.service"
systemctl --user enable --now "$SERVICE_NAME-poll.timer"

echo "✅ INSTALLATION SUCCESSFUL!"
echo "------------------------------------------------"
echo "To check status:"
echo "  systemctl --user status $SERVICE_NAME-watcher.service"
echo "To view logs:"
echo "  tail -f $BASE_DIR/cdsync.log"

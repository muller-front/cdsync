#!/bin/bash

# --- SETUP VARIABLES ---
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$BASE_DIR/config.env"
SYSTEMD_DIR="$HOME/.config/systemd/user"
AUTOSTART_DIR="$HOME/.config/autostart"
APP_DIR="$HOME/.local/share/applications"
SERVICE_NAME="cdsync-$(basename "$BASE_DIR")-$(echo -n "$BASE_DIR" | md5sum | cut -c1-6)"

# --- HELPER FUNCTIONS ---

check_python_deps() {
    echo "🔍 Checking Python dependencies for Tray Icon..."
    if ! python3 -c "import gi; gi.require_version('AppIndicator3', '0.1')" 2>/dev/null; then
        echo "❌ ERROR: Missing Python libraries for System Tray."
        echo "Please install: sudo apt install python3-gi gir1.2-appindicator3-0.1"
        return 1
    fi
    return 0
}

install_core() {
    # 1. Pre-flight Checks
    if ! command -v rclone &> /dev/null; then echo "❌ rclone not found."; exit 1; fi
    if ! command -v inotifywait &> /dev/null; then echo "❌ inotify-tools not found."; exit 1; fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ config.env not found. Please create it first."
        exit 1
    fi

    source "$CONFIG_FILE"
    
    # Check Remote Connection
    if ! rclone lsd "$RCLONE_REMOTE" --max-depth 1 --config "$HOME/.config/rclone/rclone.conf" &> /dev/null; then
        echo "❌ Could not connect to remote '$RCLONE_REMOTE'."
        exit 1
    fi

    # Create Local Dir if needed
    if [ ! -d "$LOCAL_SYNC_DIR" ]; then
        mkdir -p "$LOCAL_SYNC_DIR"
        echo "✅ Created local directory: $LOCAL_SYNC_DIR"
    fi

    echo "⚙️  Installing/Updating Core Services (Systemd)..."
    
    # Stop existing services to ensure clean update
    systemctl --user stop "$SERVICE_NAME-watcher.service" 2>/dev/null
    systemctl --user stop "$SERVICE_NAME-poll.timer" 2>/dev/null
    
    mkdir -p "$SYSTEMD_DIR"

    # Create Watcher Service
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

    # Create Polling Service
    cat > "$SYSTEMD_DIR/$SERVICE_NAME-poll.service" <<EOF
[Unit]
Description=CDSync Polling ($BASE_DIR)

[Service]
ExecStart=/bin/bash "$BASE_DIR/cdsync-core.sh"
EOF

    # Create Timer
    cat > "$SYSTEMD_DIR/$SERVICE_NAME-poll.timer" <<EOF
[Unit]
Description=Timer for CDSync Polling ($BASE_DIR)

[Timer]
OnBootSec=2min
OnUnitActiveSec=${POLL_INTERVAL:-5}min
Unit=$SERVICE_NAME-poll.service

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user daemon-reload
    
    echo "✅ Core Services Installed (Stopped)."
}

start_services() {
    echo "🚀 Starting Services..."
    systemctl --user enable --now "$SERVICE_NAME-watcher.service"
    systemctl --user enable --now "$SERVICE_NAME-poll.timer"
    echo "✅ Services Active!"
}

configure_tray() {
    # Check dependencies first
    if ! check_python_deps; then return; fi

    echo "🎨 Configuring System Tray Icon..."
    
    # Kill running instance if any
    pkill -f "cdsync-trayicon.py"
    
    # Make executable
    chmod +x "$BASE_DIR/cdsync-trayicon.py"

    mkdir -p "$AUTOSTART_DIR"
    mkdir -p "$APP_DIR"
    
    # Create Desktop Entry Content
    DESKTOP_CONTENT="[Desktop Entry]
Type=Application
Exec=$BASE_DIR/cdsync-trayicon.py
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=CDSync Tray
Comment=System tray icon for CDSync
Icon=emblem-synchronizing
Categories=Utility;Network;FileTransfer;
Keywords=sync;drive;cloud;google;dropbox;
Terminal=false"

    # Install to Autostart
    echo "$DESKTOP_CONTENT" > "$AUTOSTART_DIR/cdsync-tray.desktop"
    
    # Install to Applications Menu
    echo "$DESKTOP_CONTENT" > "$APP_DIR/cdsync-tray.desktop"
    chmod +x "$APP_DIR/cdsync-tray.desktop"
    
    # Refresh Icon Cache if possible
    update-desktop-database "$APP_DIR" 2>/dev/null

    echo "✅ Desktop Entry installed/updated."
    
    # Launch immediately
    echo "🚀 Launching Tray Icon..."
    nohup "$BASE_DIR/cdsync-trayicon.py" >/dev/null 2>&1 &
}

# --- MAIN FLOW ---

echo "------------------------------------------------"
echo "🛠️  CDSync Installer"
echo "------------------------------------------------"

# 1. INSTALL CORE SERVICES
# Always run to ensure config updates (e.g. Poll Interval) are applied
install_core

echo "------------------------------------------------"

# 2. ASK TO START SERVICES
echo "❓ Do you want to enable and start the synchronization services now?"
echo "   (If No, you can start them later via the Tray Icon)"
read -p "[Y/n]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ || -z $REPLY ]]; then
    start_services
else
    echo "⚠️  Services installed but NOT started."
fi

echo "------------------------------------------------"

# 2. ASK TO INSTALL/LAUNCH TRAY ICON
echo "🎨 Do you want to install/launch the System Tray Icon?"
echo "   (This will update desktop entries and start the icon)"
read -p "[Y/n]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ || -z $REPLY ]]; then
    configure_tray
else
    echo "Skipping Tray Icon configuration."
fi

echo "------------------------------------------------"
echo "🎉 Setup Complete!"

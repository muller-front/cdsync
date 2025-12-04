#!/bin/bash

# --- SETUP VARIABLES ---
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$BASE_DIR/config.env"
SYSTEMD_DIR="$HOME/.config/systemd/user"
AUTOSTART_DIR="$HOME/.config/autostart"
SERVICE_NAME="cdsync-$(basename "$BASE_DIR")"

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

    echo "⚙️  Installing Core Services (Systemd)..."
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
OnUnitActiveSec=5min
Unit=$SERVICE_NAME-poll.service

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now "$SERVICE_NAME-watcher.service"
    systemctl --user enable --now "$SERVICE_NAME-poll.timer"
    
    echo "✅ Core Services Installed and Started!"
}

install_tray() {
    # Check dependencies first
    if ! check_python_deps; then return; fi

    echo "🎨 Installing System Tray Icon..."
    
    # Make executable
    chmod +x "$BASE_DIR/cdsync-trayicon.py"

    mkdir -p "$AUTOSTART_DIR"
    
    # Create Desktop Entry
    cat > "$AUTOSTART_DIR/cdsync-tray.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=$BASE_DIR/cdsync-trayicon.py
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=CDSync Tray
Comment=System tray icon for CDSync
Icon=emblem-synchronizing
EOF

    echo "✅ Autostart entry created."
    
    # Launch immediately
    echo "🚀 Launching Tray Icon..."
    nohup "$BASE_DIR/cdsync-trayicon.py" >/dev/null 2>&1 &
}

# --- MAIN FLOW ---

echo "------------------------------------------------"
echo "🛠️  CDSync Installer"
echo "------------------------------------------------"

# 1. CHECK CORE SERVICES
if [ -f "$SYSTEMD_DIR/$SERVICE_NAME-watcher.service" ]; then
    echo "ℹ️  Core Services (Systemd) are ALREADY installed."
else
    install_core
fi

echo "------------------------------------------------"

# 2. CHECK/INSTALL TRAY ICON
if [ -f "$AUTOSTART_DIR/cdsync-tray.desktop" ]; then
    echo "ℹ️  Tray Icon is ALREADY configured to autostart."
else
    # Ask user
    echo "Would you like to install the System Tray Icon?"
    echo "This provides a visual indicator and Start/Stop controls."
    read -p "[y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_tray
    else
        echo "Unknown choice or No. Skipping Tray Icon."
    fi
fi

echo "------------------------------------------------"
echo "🎉 Setup Complete!"

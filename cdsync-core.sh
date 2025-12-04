#!/bin/bash

# 1. Resolve base directory (Portability)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 2. Load Configuration
if [ -f "$BASE_DIR/config.env" ]; then
    source "$BASE_DIR/config.env"
else
    echo "ERROR: config.env not found in $BASE_DIR"
    exit 1
fi

# 3. Define Log File
LOG_FILE="${CUSTOM_LOG_FILE:-$BASE_DIR/cdsync.log}"

# --- NEW: Notification Helper ---
send_notification() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"

    if [ "$ENABLE_NOTIFICATIONS" = "true" ]; then
        if command -v notify-send &> /dev/null; then
             notify-send -u "$urgency" "CDSync: $title" "$message"
        fi
    fi
}

# --- FILTER LOGIC ---
FILTER_FLAGS=""
if [ -f "$BASE_DIR/filter-rules.txt" ]; then
    FILTER_FLAGS="--filter-from $BASE_DIR/filter-rules.txt"
fi

# Log Function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# 4. Lock Mechanism (Mutex)
# Default Lock File
if [ -z "$LOCK_FILE" ]; then
    LOCK_FILE="/tmp/cdsync_default.lock"
    log "WARNING: LOCK_FILE not set in config. Using default: $LOCK_FILE"
fi

exec 200>"$LOCK_FILE"
flock -n 200 || { log "SKIP: Instance already running (Lock detected)."; exit 0; }

log "--- STARTING SYNC ($RCLONE_REMOTE <-> $LOCAL_SYNC_DIR) ---"

# 5. Execute Rclone Bisync
# --verbose: Details to log
# --drive-acknowledge-abuse: Required for some Google Drive files
# Default Rclone Config Path
RCLONE_CONFIG="${RCLONE_CONFIG_PATH:-$HOME/.config/rclone/rclone.conf}"

if rclone bisync "$RCLONE_REMOTE" "$LOCAL_SYNC_DIR" \
    --config "$RCLONE_CONFIG" \
    --drive-acknowledge-abuse \
    $FILTER_FLAGS \
    --verbose >> "$LOG_FILE" 2>&1; then
    
    log "SUCCESS: Synchronization completed."
else
    log "ERROR: rclone bisync failed. Check logs above."
    # --- NEW: Error Notification ---
    send_notification "Sync Failed" "Check $LOG_FILE for details." "critical"
fi

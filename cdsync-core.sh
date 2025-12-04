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

# --- Notification Helper ---
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
if [ -z "$LOCK_FILE" ]; then
    LOCK_FILE="/tmp/cdsync_default.lock"
    log "WARNING: LOCK_FILE not set in config. Using default: $LOCK_FILE"
fi

exec 200>"$LOCK_FILE"
flock -n 200 || { log "SKIP: Instance already running (Lock detected)."; exit 0; }

log "--- STARTING SYNC ($RCLONE_REMOTE <-> $LOCAL_SYNC_DIR) ---"

# 5. Execute Rclone Bisync with AUTO-HEALING

# Define Rclone Config Path (Default or Custom)
RCLONE_CONFIG="${RCLONE_CONFIG_PATH:-$HOME/.config/rclone/rclone.conf}"

# Create a temporary file to capture the output so we can analyze errors
OUTPUT_LOG=$(mktemp)

# Helper function to run rclone (Avoids code repetition)
run_rclone() {
    local extra_flags="$1"
    rclone bisync "$RCLONE_REMOTE" "$LOCAL_SYNC_DIR" \
        --config "$RCLONE_CONFIG" \
        --drive-acknowledge-abuse \
        --fast-list \
        --checkers 16 \
        --transfers 8 \
        $FILTER_FLAGS \
        $extra_flags \
        --verbose >> "$OUTPUT_LOG" 2>&1
    return $?
}

# --- EXECUTION FLOW ---

# Attempt 1: Normal Sync
if run_rclone ""; then
    # Success: Append output to main log
    cat "$OUTPUT_LOG" >> "$LOG_FILE"
    log "SUCCESS: Synchronization completed."
else
    # Failure: Analyze the error
    cat "$OUTPUT_LOG" >> "$LOG_FILE"
    
    # Check specifically for the "Must run --resync" corruption error
    if grep -q "Must run --resync" "$OUTPUT_LOG"; then
        log "CRITICAL ERROR DETECTED: State corruption (likely due to interruption)."
        log "INITIATING AUTO-HEALING (--resync)..."
        
        send_notification "Database Corruption" "Repairing sync database automatically..." "critical"
        
        # Clear the temp log for the retry
        truncate -s 0 "$OUTPUT_LOG"
        
        # Attempt 2: Resync (Auto-Healing)
        if run_rclone "--resync"; then
             cat "$OUTPUT_LOG" >> "$LOG_FILE"
             log "RECOVERY SUCCESSFUL: Database repaired and synced."
             send_notification "Recovery Success" "CDSync database repaired." "normal"
        else
             cat "$OUTPUT_LOG" >> "$LOG_FILE"
             log "RECOVERY FAILED: Manual intervention required."
             send_notification "Recovery Failed" "Check logs manually." "critical"
        fi
    else
        # It was some other error (network, permissions, etc)
        log "ERROR: rclone bisync failed with a non-recoverable error."
        send_notification "Sync Failed" "Check log for details." "critical"
    fi
fi

# Cleanup temp file
rm "$OUTPUT_LOG"

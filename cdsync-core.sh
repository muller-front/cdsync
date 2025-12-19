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
    
    # Default to Level 2 (ALL) if not set
    local level="${NOTIFY_LEVEL:-2}"

    # Level 0: OFF
    if [ "$level" -eq 0 ]; then
        return
    fi

    # Level 1: ERRORS ONLY
    if [ "$level" -eq 1 ] && [ "$urgency" != "critical" ]; then
        return
    fi
    
    # Check for transient hint (Anti-Spam for History)
    local -a cmd_args=()
    cmd_args+=("-u" "$urgency")
    
    if [ "$urgency" != "critical" ]; then
        cmd_args+=("-h" "int:transient:1")
    fi

    if command -v notify-send &> /dev/null; then
         notify-send "${cmd_args[@]}" "CDSync: $title" "$message"
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

# Smart Ignore List
IGNORE_LIST="/tmp/cdsync_smart_ignore.list"

# Check for manual resync request
FORCE_RESYNC=false
DIR_EVENT=false
SMART_SYNC_PATH=""

# Parse Arguments
for arg in "$@"; do
    case $arg in
        --force-resync)
            FORCE_RESYNC=true
            shift
            ;;
        --smart-sync)
            SMART_SYNC_PATH="$2"
            shift 2
            ;;
        --dir-event)
            DIR_EVENT=true
            SMART_SYNC_PATH="$2" # We use this just for logging if needed
            shift 2
            ;;

        --dedupe)
            DEDUPE_MODE="$2"
            shift 2
            ;;
        *)
            # shift
            ;;
    esac
done

exec 200>"$LOCK_FILE"

# LOCKING STRATEGY
if [ -n "$SMART_SYNC_PATH" ]; then
    # *** DISABLED ***
    # Shallow Sync (Smart): QUEUE/WAIT
    # We use a blocking lock. This script will PAUSE here until the lock is released.
    #log "WAIT: Unlocking queued... (Pending prior sync)"
    #flock 200
    
    # *** ENABLED ***
    # Shallow Sync (Smart): SKIP IF BUSY
    # Prevent "Thundering Herd" from backup software like Duplicati
    flock -n 200 || { log "SKIP: Smart Sync ignored (System busy). Will be picked up by Timer."; exit 0; }
elif [ "$DIR_EVENT" = "true" ]; then
    # Directory Event: WAIT
    # Full Bisync triggered by directory change. Needs to wait.
    log "WAIT: Queued behind active sync (Dir Event)..."
    flock 200
elif [ "$FORCE_RESYNC" = "true" ]; then
    # Force Resync: WAIT
    log "WAIT: Queued behind active sync..."
    flock 200
else
    # Timer (Periodic): SKIP
    flock -n 200 || { log "SKIP: Instance already running (Lock detected)."; exit 0; }
fi

log "--- STARTING SYNC ($RCLONE_REMOTE <-> $LOCAL_SYNC_DIR) ---"

# 5. Execute Rclone Bisync with AUTO-HEALING

# Define Rclone Config Path (Default or Custom)
RCLONE_CONFIG="${RCLONE_CONFIG_PATH:-$HOME/.config/rclone/rclone.conf}"

# Create a temporary file to capture the output so we can analyze errors
OUTPUT_LOG=$(mktemp)

# Helper function to run rclone (Avoids code repetition)
run_rclone() {
    local extra_flags="$1"
    
    # "Blindfold" removed in favor of Smart Ignore List
    # We allow events to accumulate, and then filter them based on logs.
    

    # Conflict Resolution Strategy
    # Controlled by FORCE_SYNC_NEWER (Default: true)
    if [ "${FORCE_SYNC_NEWER:-true}" = "true" ]; then
        CONFLICT_FLAGS="--conflict-resolve newer --conflict-loser delete"
    else
        CONFLICT_FLAGS="" # Rclone default (creates .conflict files)
    fi

    rclone bisync "$RCLONE_REMOTE" "$LOCAL_SYNC_DIR" \
        --config "$RCLONE_CONFIG" \
        --log-format date,time \
        --log-file "$OUTPUT_LOG" \
        --drive-acknowledge-abuse \
        --fast-list \
        --checkers 16 \
        --transfers 8 \
        $CONFLICT_FLAGS \
        --create-empty-src-dirs \
        $FILTER_FLAGS \
        $extra_flags \
        --verbose
    
    EXIT_CODE=$?
    
    # Generate Smart Ignore List from Output Log
    # We want to catch files that Rclone MODIFIED LOCALLY, which triggers inotify.
    # 1. Bisync "Queue copy to Path2" (Remote->Local Download)
    #    Format: "... - Path1 Queue copy to Path2 - path/to/file"
    sed -n 's/.*Queue copy to Path2.*-\s*\(.*\)/\1/p' "$OUTPUT_LOG" | while read -r line; do echo "$LOCAL_SYNC_DIR/$line" >> "$IGNORE_LIST"; done
    
    # 2. Standard Sync "Copied (new/replaced)" (Shallow Sync or Standard Rclone)
    #    Format: "INFO : path/to/file: Copied (new)"
    sed -n 's/.*INFO\s*:\s*\(.*\):\s*Copied.*/\1/p' "$OUTPUT_LOG" | while read -r line; do echo "$LOCAL_SYNC_DIR/$line" >> "$IGNORE_LIST"; done

    # 3. Deleted files (prevent "delete" event loop if we just deleted it)
    #    Format: "... - Path2 Deleted - path" (Bisync) OR "INFO : path: Deleted" (Standard)
    sed -n 's/.*Path2\s*Deleted.*-\s*\(.*\)/\1/p' "$OUTPUT_LOG" | while read -r line; do echo "$LOCAL_SYNC_DIR/$line" >> "$IGNORE_LIST"; done
    sed -n 's/.*INFO\s*:\s*\(.*\):\s*Deleted.*/\1/p' "$OUTPUT_LOG" | while read -r line; do echo "$LOCAL_SYNC_DIR/$line" >> "$IGNORE_LIST"; done
    
    return $EXIT_CODE
}

# --- EXECUTION FLOW ---

# --- EXECUTION FLOW ---

# --- 3. DIRECTORY EVENT LOGIC (FULL BISYNC) ---
if [ "$DIR_EVENT" = "true" ]; then
    log "INFO: 📂 Directory/Structure Change Detected. Triggering Full Bisync..."
    send_notification "Structure Change" "Running full sync..." "normal"
    
    # We fall through to the MAIN BISYNC LOGIC below
    # But we ensure FORCE_RESYNC is false so it runs normal sync
    FORCE_RESYNC=false
fi

# --- 4. SHALLOW SYNC LOGIC (FILE ONLY) ---
if [ -n "$SMART_SYNC_PATH" ] && [ "$DIR_EVENT" != "true" ]; then
    # 3.1 Calculate Relative Directory
    if [[ "$SMART_SYNC_PATH" != "$LOCAL_SYNC_DIR"* ]]; then
        echo "Error: Path is outside sync dir."
        rm -f "$LOCK_FILE"
        exit 1
    fi
    
    # We always sync the DIRECTORY, not the file.
    TARGET_DIR=$(dirname "$SMART_SYNC_PATH")
    
    REL_PATH="${TARGET_DIR#$LOCAL_SYNC_DIR}"
    REL_PATH="${REL_PATH#/}"
    
    # Check if Target Directory exists (e.g. recursive delete case)
    if [ ! -d "$TARGET_DIR" ]; then
        log "SKIP: Parent directory $TARGET_DIR not found (likely deleted)."
        rm -f "$LOCK_FILE"
        exit 0
    fi
     
    if [ -z "$REL_PATH" ]; then
        REL_PATH="." # Root
        REMOTE_TARGET="$RCLONE_REMOTE"
        LOCAL_TARGET="$LOCAL_SYNC_DIR"
        LOG_MSG="/"
    else
        REMOTE_TARGET="$RCLONE_REMOTE/$REL_PATH"
        LOCAL_TARGET="$LOCAL_SYNC_DIR/$REL_PATH"
        LOG_MSG="$REL_PATH/"
    fi
    
    # Extract just the filename for Targeted Sync
    TARGET_FILE_NAME=$(basename "$SMART_SYNC_PATH")
    
    log "INFO: 🚀 Targeted Sync triggered for: $LOG_MSG$TARGET_FILE_NAME"
    send_notification "Smart Sync" "Syncing: $TARGET_FILE_NAME" "normal"

    # 3.2 Execute Targeted Sync
    # We sync the PARENT directory but FILTER ONLY the changed FILE.
    # Directory changes are handled by the DIR_EVENT triggers (Bisync).
    # --filter "+ /NAME"    -> Matches the file itself.
    # --filter "- *"        -> Exclude everything else (Safety)
    
    rclone sync "$LOCAL_TARGET" "$REMOTE_TARGET" \
        --filter "+ /$TARGET_FILE_NAME" \
        --filter "- *" \
        --config "$RCLONE_CONFIG" \
        --drive-acknowledge-abuse \
        --verbose >> "$LOG_FILE" 2>&1

    EXIT_CODE=$?
    
    # Cleanup and Exit
    rm -f "$LOCK_FILE"
    
    if [ $EXIT_CODE -eq 0 ]; then
        log "INFO: ✅ Shallow Sync Success."
        exit 0
    else
        log "ERROR: ❌ Shallow Sync Failed."
        exit $EXIT_CODE
    fi
fi

# --- 4. FULL BISYNC LOGIC (DEFAULT) ---
# Check for manual resync request
if [ "$FORCE_RESYNC" = "true" ]; then
    log "MANUAL RESYNC INITIATED (User Request)."
    send_notification "Manual Resync" "Starting repair database..." "normal"
    
    # Force resync
    if run_rclone "--resync"; then
         cat "$OUTPUT_LOG" >> "$LOG_FILE"
         log "MANUAL RESYNC SUCCESSFUL."
         send_notification "Resync Success" "Database repaired." "normal"
    else
         cat "$OUTPUT_LOG" >> "$LOG_FILE"
         log "MANUAL RESYNC FAILED."
         send_notification "Resync Failed" "Check logs." "critical"
    fi
    rm "$OUTPUT_LOG"
    exit 0

fi

# DEDUPLICATION LOGIC
if [ -n "$DEDUPE_MODE" ]; then
    log "MAINTENANCE: Deduplication started (Mode: $DEDUPE_MODE)."
    send_notification "Maintenance Started" "Cleaning cloud duplicates ($DEDUPE_MODE)..." "normal"
    
    # Valid modes: rename, newest, oldest, first, largest, smallest
    # We map 'newest' -> 'newest' (Keep newest), 'rename' -> 'rename'.
    
    rclone dedupe "$DEDUPE_MODE" "$RCLONE_REMOTE" \
        --config "$RCLONE_CONFIG" \
        --drive-acknowledge-abuse \
        --verbose >> "$OUTPUT_LOG" 2>&1
        
    EXIT_CODE=$?
    
    cat "$OUTPUT_LOG" >> "$LOG_FILE"
    rm "$OUTPUT_LOG"
    
    if [ $EXIT_CODE -eq 0 ]; then
        log "MAINTENANCE SUCCESSFUL."
        send_notification "Maintenance Success" "Deduplication complete." "normal"
        exit 0
    else
        log "MAINTENANCE FAILED."
        send_notification "Maintenance Error" "Check logs." "critical"
        exit $EXIT_CODE
    fi
fi

# Attempt 1: Normal Sync
if run_rclone ""; then
    # Success: Append output to main log
    cat "$OUTPUT_LOG" >> "$LOG_FILE"
    log "SUCCESS: ✅ Synchronization completed."
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

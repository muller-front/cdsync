#!/bin/bash

# 1. Resolve base directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 2. Load Configuration
if [ -f "$BASE_DIR/config.env" ]; then
    source "$BASE_DIR/config.env"
else
    echo "ERROR: config.env not found."
    exit 1
fi

LOCK_FILE="${LOCK_FILE:-/tmp/cdsync_default.lock}"
# No Blindfold Marker checking needed here? 
# actually the redundancy is solved by the buffer logic itself.
# If bisync is running, events accumulate.
# But we might still want to skip events generated primarily by bisync?
# Yes, blindfold is still useful to filter out the download events.
# Smart Ignore List (Replaces Blindfold)
IGNORE_LIST="/tmp/cdsync_smart_ignore.list"

# Buffer Files
BUFFER_FILE="/tmp/cdsync_events.buffer"
PROCESSING_FILE="/tmp/cdsync_events.processing"
touch "$BUFFER_FILE"

echo "Starting CDSync Watcher (Buffer Strategy)..."
echo "Monitored Directory: $LOCAL_SYNC_DIR"
echo "Buffer File: $BUFFER_FILE"

# 3. Inotify Background Process
# Fix: Pipe to while-read to allow 'mv' of buffer file (re-opening file on each write)
inotifywait -m -r -e close_write,moved_to,create,delete,moved_from \
    --format '%e|%w%f' \
    --exclude '(\.git/|\.lock|cdsync\.log|\.swp|\.tmp|\.part|\.~tmp~|\.goutputstream|\.\.path)' \
    "$LOCAL_SYNC_DIR" 2>/dev/null | while read -r LINE; do
        echo "$LINE" >> "$BUFFER_FILE"
    done &

INOTIFY_PID=$!

# Trap to kill inotify on exit
cleanup() {
    kill "$INOTIFY_PID"
    rm -f "$BUFFER_FILE" "$PROCESSING_FILE"
    exit 0
}
trap cleanup SIGINT SIGTERM

# 4. Processing Loop (The Garbage Collector)
while true; do
    sleep 5 # 5 seconds window (accumulate events)

    # Check if buffer has content
    if [ -s "$BUFFER_FILE" ]; then
        # Atomic Move to processing
        mv "$BUFFER_FILE" "$PROCESSING_FILE"
        touch "$BUFFER_FILE" # Create new empty buffer immediately

        # 4.1 Blindfold Check (Stale check included)
        # Prepare Ignore List (Atomic Consumption)
        ACTIVE_IGNORE="/tmp/cdsync_ignore_active.list"
        if [ -f "$IGNORE_LIST" ]; then
             mv "$IGNORE_LIST" "$ACTIVE_IGNORE"
             touch "$IGNORE_LIST" # Create empty immediately
        fi

        echo "--- Processing Batch ---"
        
        # 4.2 Hierarchy Decision
        # Check for ANY Directory Event
        if grep -q "ISDIR" "$PROCESSING_FILE"; then
            echo "📂 Directory Change Detected in Batch. Triggering FULL BISYNC."
            # Trigger --dir-event (which runs bisync)
            # We don't care which dir, bisync scans all.
            # Use background & to not block watcher loop? 
            # Bisync blocks core, but core manages lock. 
            "$BASE_DIR/cdsync-core.sh" --dir-event "Batch Trigger" &
            
        else
            echo "📄 File-Only Batch. Triggering Targeted Syncs..."
            
            # Deduplicate files
            # Format: EVENT|PATH. We just want PATH.
            # Also we might have multiple events for same file.
            # Just take unique paths.
            
            awk -F'|' '{print $2}' "$PROCESSING_FILE" | sort | uniq | while read -r CHANGED_FILE; do
                if [ -n "$CHANGED_FILE" ]; then
                    # Smart Ignore Check
                    if [ -f "$ACTIVE_IGNORE" ] && grep -Fqx "$CHANGED_FILE" "$ACTIVE_IGNORE"; then
                        echo " -> Ignored (Smart List): $CHANGED_FILE"
                        continue
                    fi
                    
                    echo " -> Syncing File: $CHANGED_FILE"
                    "$BASE_DIR/cdsync-core.sh" --smart-sync "$CHANGED_FILE" &
                fi
            done
        fi
        
        # Cleanup Active Ignore List
        rm -f "$ACTIVE_IGNORE"

        
        # Cleanup
        rm "$PROCESSING_FILE"
    fi
done

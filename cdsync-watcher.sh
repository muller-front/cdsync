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

EXECUTABLE="$BASE_DIR/cdsync-core.sh"

echo "Starting CDSync Watcher..."
echo "Monitored Directory: $LOCAL_SYNC_DIR"
echo "Executor Script: $EXECUTABLE"

# 3. Monitoring Loop
while true; do
    # inotifywait: recursive, excluding system/git/temp files to prevent loops
    inotifywait -r -e close_write,moved_to,create,delete \
    --exclude '(\.git/|\.lock|cdsync\.log|\.swp|\.tmp|\.~tmp~)' \
    "$LOCAL_SYNC_DIR" 2>/dev/null

    # Debounce (Wait 5s to group rapid changes)
    sleep 5

    echo "Change detected. Triggering sync..."
    bash "$EXECUTABLE"
done

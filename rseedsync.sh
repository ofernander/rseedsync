#!/bin/bash
########################
#                        _                      
#                       | |                     
# _ __ ___  ___  ___  __| |___ _   _ _ __   ___ 
#| '__/ __|/ _ \/ _ \/ _` / __| | | | '_ \ / __|
#| |  \__ \  __/  __/ (_| \__ \ |_| | | | | (__ 
#|_|  |___/\___|\___|\__,_|___/\__, |_| |_|\___|
#                               __/ |           
#                              |___/            
#
#Simple script that uses rsync to pull files from a remote seedbox via ssh
#
########################
set -euo pipefail

source "rseedsync.conf"

# --- Command-line Arguments ---
DRY_RUN=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN="--dry-run"
            echo "Running in dry-run mode..."
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# --- Functions ---

# Log messages with timestamp
log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${message}" | tee -a "$LOG_FILE"
}

# Create a lock file to prevent multiple instances
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        log "Another instance of the script is currently running. Exiting."
        exit 1
    else
        touch "$LOCK_FILE"
    fi
}

# Remove the lock file
release_lock() {
    rm -f "$LOCK_FILE"
}

# Generate an exclude file from the completed directory
generate_exclude_file() {
    if [ ! -d "$LOCAL_COMPLETED_DIR" ]; then
        log "Local completed directory '$LOCAL_COMPLETED_DIR' does not exist. Exiting."
        exit 1
    fi
    # Clear the exclude file to avoid duplicate entries
    > "$EXCLUDE_FILE"
    # Append completed files and directories to the exclude file
    find "$LOCAL_COMPLETED_DIR" -type f -exec basename {} \; >> "$EXCLUDE_FILE"
    find "$LOCAL_COMPLETED_DIR" -type d -exec basename {} \; >> "$EXCLUDE_FILE"
}

# Use rsync to sync files from remote to local directory, applying file type exclusions
run_rsync() {
    local RSYNC_OPTIONS="-av --progress --exclude-from=$EXCLUDE_FILE $DRY_RUN --chmod=$FILE_PERMISSIONS --chown=$FILE_USER:$FILE_GROUP"
    
    # Append file type exclude patterns from the configuration
    for pattern in "${EXCLUDED_FILE_TYPES[@]}"; do
        RSYNC_OPTIONS+=" --exclude=${pattern}"
    done

    log "Syncing files from remote ($SEEDBOX_USER@$SEEDBOX_HOST:$REMOTE_DIR) to local sync directory ($LOCAL_SYNC_DIR)..."
    rsync -e "ssh -p $SSH_PORT" $RSYNC_OPTIONS "$SEEDBOX_USER@$SEEDBOX_HOST:$REMOTE_DIR" "$LOCAL_SYNC_DIR" | tee -a "$LOG_FILE"
}

# Recursively move media files from the sync directory to the completed directory.
move_files() {
    log "Recursively moving media files from sync directory to completed directory..."
    # Look for common media file extensions (adjust as needed)
    find "$LOCAL_SYNC_DIR" -type f \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.avi' -o -iname '*.mov' -o -iname '*.mp3' -o -iname '*.flac' -o -iname '*.wav' -o -iname '*.ogg' -o -iname '*.wmv' -o -iname '*.webm' \) -print0 | while IFS= read -r -d '' file; do
         log "Moving media file: $file"
         mv "$file" "$LOCAL_COMPLETED_DIR"
    done
}

# Clean up old log files, retaining only the most recent ones
cleanup_logs() {
    log "Retaining only the most recent $LOGS_TO_RETAIN log(s), cleaning up older logs..."
    local logs_to_delete
    logs_to_delete=$(ls -1t "$LOG_DIR"/rseedsync_log_*.txt 2>/dev/null | tail -n +$((LOGS_TO_RETAIN + 1)) || true)
    if [ -n "$logs_to_delete" ]; then
        echo "$logs_to_delete" | xargs rm -f
    fi
}

# --- Cleaner Functions (Integrated) ---
# Recursively delete files smaller than CLEAN_FILES_THRESHOLD_SIZE (in kilobytes)
delete_small_items() {
    find "$LOCAL_SYNC_DIR" -mindepth 1 -type f -size -"${CLEAN_FILES_THRESHOLD_SIZE}k" -print0 | while IFS= read -r -d '' file; do
         log "Deleting file due to size: $file"
         rm -f "$file"
    done
}

# Recursively delete files older than CLEAN_FILES_THRESHOLD_DAYS
delete_old_items() {
    find "$LOCAL_SYNC_DIR" -mindepth 1 -type f -mtime +"$CLEAN_FILES_THRESHOLD_DAYS" -print0 | while IFS= read -r -d '' file; do
         log "Deleting file due to age: $file"
         rm -f "$file"
    done
}

# Remove empty directories that may result from file deletion
delete_empty_directories() {
    find "$LOCAL_SYNC_DIR" -type d -empty -print0 | while IFS= read -r -d '' dir; do
         log "Deleting empty directory: $dir"
         rmdir "$dir"
    done
}

delete_exclude_file() {
    rm -f "$EXCLUDE_FILE"
    done 
}

# Run the cleaner on the local sync directory recursively
run_cleaner() {
    log "Running cleaner on local sync directory: $LOCAL_SYNC_DIR"
    delete_small_items
    delete_old_items
    delete_empty_directories
    delete_exclude_file
}

# Ensure the lock file is removed on exit, even on errors or interrupts
trap 'release_lock' SIGINT SIGTERM EXIT

# Create necessary directories if they don't exist
mkdir -p "$RSEEDSYNC_DIR" "$LOG_DIR" "$LOCAL_SYNC_DIR" "$LOCAL_COMPLETED_DIR"

# Validate required configuration variables
if [ -z "$SEEDBOX_USER" ] || [ -z "$SEEDBOX_HOST" ] || [ -z "$REMOTE_DIR" ]; then
    log "Error: SEEDBOX_USER, SEEDBOX_HOST, and REMOTE_DIR must be set in the configuration."
    exit 1
fi

acquire_lock
generate_exclude_file
run_rsync
move_files
cleanup_logs
run_cleaner

log "Sync Complete!"
exit 0

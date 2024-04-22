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
#config
SEEDBOX_USER=""
SEEDBOX_HOST=""
REMOTE_DIR="" #where to find completed files on seedbox
LOCAL_SYNC_DIR="" #where files being synced are stored while syncing
LOCAL_COMPLETED_DIR="" #where synced files are moved to when the script completes
SSH_PORT="22"
FILE_PERMISSIONS="755"
FILE_USER=""
FILE_GROUP=""
RSEEDSYNC_DIR="/opt/rseedsync"
EXCLUDE_FILE="$RSEEDSYNC_DIR/rseedsync_exclude.txt"
LOG_FILE="$RSEEDSYNC_DIR/log/rseedsync_log_$(date '+%Y%m%d_%H%M%S').txt"
LOCK_FILE="/tmp/rseedsync.lock"
LOG_RETENTION_DAYS="0.1"

#check for --dry-run option
DRY_RUN=""
if [ "$1" == "--dry-run" ]; then
    DRY_RUN="--dry-run"
    echo "Running in dry-run mode..."
fi

mkdir -p "$RSEEDSYNC_DIR"
mkdir -p "$RSEEDSYNC_DIR/log"

#check if the script is already running
if [ -f "$LOCK_FILE" ]; then
    echo "Another instance of the script is currently running. Exiting."
    exit 1
else
    #create a lock file
    touch "$LOCK_FILE"
fi

#generate a list of files in the completed directory
find "$LOCAL_COMPLETED_DIR" -type f -exec basename {} \; >> "$EXCLUDE_FILE"
find "$LOCAL_COMPLETED_DIR" -type d -exec basename {} \; >> "$EXCLUDE_FILE"

#rsync options
RSYNC_OPTIONS="-av --progress --exclude-from=$EXCLUDE_FILE $DRY_RUN --chmod=$FILE_PERMISSIONS --chown=$FILE_USER:$FILE_GROUP"

#sync files from the remote seedbox to the local sync directory
echo "Syncing files from remote to local sync directory..."
rsync -e "ssh -p $SSH_PORT" $RSYNC_OPTIONS "$SEEDBOX_USER@$SEEDBOX_HOST:$REMOTE_DIR" "$LOCAL_SYNC_DIR" | tee -a "$LOG_FILE"

#move files from local sync directory to local completed directory
echo "Moving files to completed directory..."
for file in "$LOCAL_SYNC_DIR"/*; do
    if [ "$(basename "$file")" != "complete" ]; then
        mv "$file" "$LOCAL_COMPLETED_DIR"
    fi
done

#clean up
find "log/" -name "rseedsync_log_*.txt" -type f -mtime +"$LOG_RETENTION_DAYS" -exec rm -f {} \;
rm -f "$LOCK_FILE"

#run cleaner script
echo "Running rseedsync_cleaner.sh script..."
DIR="$(dirname "${BASH_SOURCE[0]}")"  # Get the directory of the current script
bash "$DIR/rseedsync_cleaner.sh"

echo "Sync Complete!"

exit 0

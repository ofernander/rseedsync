#!/bin/bash
#############
#Companion script that cleans old left over files not imported by your service of choice
#############
# Define the threshold size in kilobytes (100MB)
THRESHOLD_SIZE=$((100 * 1024))

# Define the age threshold in days
AGE_THRESHOLD=3

# Function to check size and delete if it's less than the threshold
delete_small_items() {
    for item in "$1"/*; do
        if [ -e "$item" ]; then
            # Calculate the item size (file or directory)
            item_size=$(du -sk "$item" | cut -f1)
            if [ $item_size -lt $THRESHOLD_SIZE ]; then
                echo "Deleting item due to size: $item"
                rm -rf "$item"
            fi
        fi
    done
}

# Function to delete items older than the specified age
delete_old_items() {
    for item in "$1"/*; do
        if [ -e "$item" ]; then
            # Find items older than the AGE_THRESHOLD
            if find "$item" -maxdepth 0 -mtime +$AGE_THRESHOLD | grep -q .; then
                echo "Deleting item due to age: $item"
                rm -rf "$item"
            fi
        fi
    done
}

# Parent directory (replace with the path you want to search)
PARENT_DIR=""

# Calling the functions
delete_small_items "$PARENT_DIR"
delete_old_items "$PARENT_DIR"

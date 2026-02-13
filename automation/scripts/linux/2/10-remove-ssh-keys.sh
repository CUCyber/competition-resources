#!/bin/sh
# 10-remove-ssh-keys.sh
# Author: Dylan Harvey
# Description: Automated script to backup and remove SSH keys. Checks sshd_config and defaults.
# Dependencies: awk, sed, tar, find, date*

LOG_FILE="/var/log/ssh_key_purge.log"
BACKUP_DIR="/root/ssh_backups"
mkdir -p "$BACKUP_DIR"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Must be run as root." >&2
    exit 1
fi

CONFIG_PATHS=$(awk '/^AuthorizedKeysFile/ {for (i=2; i<=NF; i++) print $i}' /etc/ssh/sshd_config 2>/dev/null)

DEFAULT_PATHS=".ssh/authorized_keys .ssh/authorized_keys2"

SEARCH_TARGETS=""
for path in $CONFIG_PATHS $DEFAULT_PATHS; do
    if echo "$path" | grep -q "^/"; then
        SEARCH_TARGETS="$SEARCH_TARGETS $path"
    else
        SEARCH_TARGETS="$SEARCH_TARGETS $(awk -F: '$6 ~ /^\// {print $6}' /etc/passwd | sed "s|$|/$path|")"
    fi
done

FINAL_LIST=""
for f in $SEARCH_TARGETS; do
    if [ -f "$f" ]; then
        FINAL_LIST="$FINAL_LIST $f"
    fi
done

if [ -n "$FINAL_LIST" ]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/keys_backup_$TIMESTAMP.tgz"
    
    tar czf "$BACKUP_FILE" $FINAL_LIST 2>/dev/null
    
    for key_file in $FINAL_LIST; do
        rm -f "$key_file"
        echo "$(date): Removed $key_file" >> "$LOG_FILE"
    done
    
    echo "SUCCESS: Keys backed up to $BACKUP_FILE and removed."
else
    echo "INFO: No authorized_keys found."
    echo "$(date): No keys found to remove." >> "$LOG_FILE"
fi

echo "SSH keys backed up and deleted."

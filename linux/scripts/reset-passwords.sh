#!/bin/sh
# \reset-passwords.sh
# Author: Dylan Harvey
# Description: Interactive password reset script, will change passwords for non-excluded user accounts.
# Dependencies: id, cp, sed, awk, chpasswd, passwd, date*

# === CONFIG ===
EXCLUDED_USERS="^blackteam ^seccdc"  # CHANGE AS NEEDED, SUPPORTS REGEX
PASSWORD=""  # CHANGE

LOG_FILE="/var/log/password_reset.log"

if [ -z "$PASSWORD" ]; then
    echo "ERROR: Password is not set! Aborting..." >&2
    exit 2
fi

if [ -z "$EXCLUDED_USERS" ]; then
    echo "WARNING: Excluded users list is not set!"
    sleep 2
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Must be run as root." >&2
    exit 1
fi

cp /etc/shadow /etc/shadow.bak

EXCLUDE_REGEX=$(echo "$EXCLUDED_USERS" | sed 's/ /|/g')

TARGET_USERS=$(awk -F: -v r="$EXCLUDE_REGEX" '
    ($3 == 0 || ($3 > 999 && $3 < 60000)) {
        if ($1 !~ r) {
            print $1
        }
    }' /etc/passwd)

for user in $TARGET_USERS; do
    if echo "$user:$PASSWORD" | chpasswd -c SHA512 2>/dev/null; then
        STATUS="SUCCESS (SHA512)"
    elif echo "$user:$PASSWORD" | chpasswd 2>/dev/null; then
        STATUS="SUCCESS (Standard)"
    elif echo "$PASSWORD" | passwd --stdin "$user" 2>/dev/null; then
        STATUS="SUCCESS? (Stdin)"
    else
        STATUS="FAILURE"
    fi

    echo "[$user] $STATUS"
    echo "$(date): $STATUS - $user" >> "$LOG_FILE"
done

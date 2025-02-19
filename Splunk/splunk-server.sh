#!/bin/sh
# Thanks SEMO and TTU :)

PORT="9997"
SPLUNK_USERNAME="admin"
SPLUNK_PASSWORD="SecretPassword123!"
OG_SPLUNK_PASSWORD="changeme"

SPLUNK_HOME="/opt/splunk"
BACKUP_DIR="/root/.cache/splunk"

mkdir -p "$BACKUP_DIR"

echo "Backing up original Splunk configurations..."
mkdir -p "$BACKUP_DIR/splunkORIGINAL"
cp -R "$SPLUNK_HOME" "$BACKUP_DIR/splunkORIGINAL"

echo "Setting secure local file permissions..."
chmod -R 700 "$SPLUNK_HOME/etc/system/local"
chmod -R 700 "$SPLUNK_HOME/etc/system/default"
chown -R root:root "$SPLUNK_HOME/etc"

if ! $SPLUNK_HOME/bin/splunk edit user $SPLUNK_USERNAME -password "$SPLUNK_PASSWORD" -auth "$SPLUNK_USERNAME:$OG_SPLUNK_PASSWORD"; then
    echo "Error: Failed to change admin password"
    exit 1
fi

USERS=$($SPLUNK_HOME/bin/splunk list user -auth "${SPLUNK_USERNAME}:${SPLUNK_PASSWORD}" | grep -v "$SPLUNK_USERNAME" | awk '{print $2}')

for USER in $USERS; do
    $SPLUNK_HOME/bin/splunk remove user $USER -auth "${SPLUNK_USERNAME}:${SPLUNK_PASSWORD}"
done

echo "Restarting Splunk to apply changes..."
$SPLUNK_HOME/bin/splunk restart

echo "Backing up latest Splunk configurations..."
mkdir -p "$BACKUP_DIR/splunk"
cp -R "$SPLUNK_HOME" "$BACKUP_DIR/splunk"

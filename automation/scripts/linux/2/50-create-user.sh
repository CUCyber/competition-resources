#!/bin/sh
# 50-create-user.sh
# Author: Dylan Harvey / Adam Colaianni
# Description: Automated user creation script, will create a sudo user.
# Dependencies: useradd, usermod, chpasswd, grep, cut, chmod, chown

USERNAME=""  # CHANGE AS NEEDED
PASSWORD=""  # CHANGE
SSH_KEY=""  # CHANGE

if [ -z "$USERNAME" ]; then
    echo "ERROR: Username is not set! Aborting..." >&2
    exit 2
fi

if [ -z "$PASSWORD" ]; then
    echo "ERROR: Password is not set! Aborting..." >&2
    exit 2
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Must be run as root." >&2
    exit 1
fi

if grep -q "^$USERNAME:" /etc/passwd; then
    echo "[!] User '$USERNAME' already exists. Skipping." >&2
    exit 1
else
    useradd -m -s /bin/bash "$USERNAME" || useradd -m "$USERNAME"
    echo "[+] User '$USERNAME' created."
fi

if echo "$USERNAME:$PASSWORD" | chpasswd -c SHA512 2>/dev/null; then
        METHOD="SHA512"
    elif echo "$USERNAME:$PASSWORD" | chpasswd 2>/dev/null; then
        METHOD="Standard"
    elif echo "$PASSWORD" | passwd --stdin "$USERNAME" 2>/dev/null; then
        METHOD="Stdin"
    else
        METHOD="FAILURE"
fi
echo "[+] Password for '$USERNAME' updated ($METHOD)."

for GROUP in sudo wheel; do
    if grep -q "^$GROUP:" /etc/group; then
        if ! grep "^$GROUP:" /etc/group | grep -q "$USERNAME"; then
            usermod -aG "$GROUP" "$USERNAME" 2>/dev/null || addgroup "$USERNAME" "$GROUP"
            echo "[+] Added '$USERNAME' to group: $GROUP"
        fi
    fi
done

USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)

if [ -z "$USER_HOME" ]; then
    USER_HOME="/home/$USERNAME"
fi

SSH_DIR="$USER_HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

echo "$SSH_KEY" > "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"
chown -R "$USERNAME:$USERNAME" "$SSH_DIR"

echo "Backup user created."

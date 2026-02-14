#!/bin/sh
# 50-create-user.sh
# Author: Dylan Harvey
# Description: Automated user creation script, will create a sudo user.
# Dependencies: awk, useradd, usermod, chpasswd, chmod, chown

USERNAME=""  # CHANGE AS NEEDED
PASSWORD=""  # CHANGE
SSH_KEY=""  # CHANGE, OPTIONAL

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

if awk -F: -v u="$USERNAME" '$1 == u {found=1} END {exit !found}' /etc/passwd; then
    echo "[!] WARNING: User '$USERNAME' already exists. Skipping creation."
else
    useradd -m -s /bin/bash "$USERNAME" || useradd -m "$USERNAME"
    echo "[+] Created user $USERNAME"
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

for GROUP in sudo wheel admin; do
    if awk -F: -v g="$GROUP" '$1 == g {found=1} END {exit !found}' /etc/group; then
        usermod -aG "$GROUP" "$USERNAME" 2>/dev/null || addgroup "$USERNAME" "$GROUP" 2>/dev/null
        echo "[+] Added '$USERNAME' to $GROUP"
    fi
done

USER_HOME=$(awk -F: -v u="$USERNAME" '$1 == u {print $6}' /etc/passwd)
if [ -n "$SSH_KEY" ] && [ -d "$USER_HOME" ]; then
    mkdir -p "$USER_HOME/.ssh"
    echo "$SSH_KEY" > "$USER_HOME/.ssh/authorized_keys"
    chmod 700 "$USER_HOME/.ssh"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"
    chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
    echo "[+] Added SSH key at $USER_HOME/.ssh/authorized_keys"
fi

#!/bin/bash
# nuke-firewall.sh
# Author: Dylan Harvey
# Description: Interactive firewall hardening script that restores backup if you block yourself
# Dependencies: nftables (nft), bash, tr, xargs, systemctl/service
# WARNING: WILL BREAK SCORED SERVICES!!!
# Note: Not as polished as windows variant, BE CAREFUL. Know what you are doing.

# === CONFIG ===
ALLOW_IPS="10.2.0.0/24"  # CHANGE, Supports CIDR and individual IPs (space or comma separated)
INBOUND_ACTION="drop"    # default drop
OUTBOUND_ACTION="drop"   # default accept (Block super strict, will stop C2+RevShell and probably break more stuff)
BACKUP_PATH="./nftables_backup.rules"
CONF_FILE="/etc/nftables.conf"
TMP_RULES="/tmp/new_nftables.rules"
RULE_COMMENT="BLUE_MGMT"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# === HELPERS ===
manage_service() {
    local action=$1
    if command -v systemctl >/dev/null 2>&1; then
        systemctl "$action" nftables 2>&1
    elif command -v service >/dev/null 2>&1; then
        service nftables "$action" 2>&1
    fi
}

disable_firewall() {
    echo "[!] Clearing firewall to prevent lockout..."
    nft flush ruleset
    nft add table inet filter 2>/dev/null
    nft add chain inet filter input { type filter hook input priority 0 \; policy accept \; }
    nft add chain inet filter output { type filter hook output priority 0 \; policy accept \; }
    echo "flush ruleset" > "$CONF_FILE"
}


# === EXECUTION ===
if [[ -f "$BACKUP_PATH" ]]; then
    echo "[i] Found existing backup at $BACKUP_PATH, moving to ${BACKUP_PATH}.old"
    mv -f "$BACKUP_PATH" "${BACKUP_PATH}.old"
fi

echo "flush ruleset" > "$BACKUP_PATH"
nft list ruleset >> "$BACKUP_PATH"

echo "Generating new nftables configuration..."
FORMATTED_IPS=$(echo "$ALLOW_IPS" | tr ' ' ',' | tr -s ',' | sed 's/^,//;s/,$//')

cat <<EOF > $TMP_RULES
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy $INBOUND_ACTION;

        iif "lo" accept
        ct state established,related accept
        ct state invalid drop

        ip saddr { $FORMATTED_IPS } accept comment "$RULE_COMMENT"
        
        log prefix "NFT_INPUT_POLICY: " flags all
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy $OUTBOUND_ACTION;

        oif "lo" accept
        ct state established,related accept

        ip daddr { $FORMATTED_IPS } accept comment "$RULE_COMMENT"

        log prefix "NFT_OUTPUT_POLICY: " flags all
    }
}
EOF

echo "[*] Verifying syntax..."
if ! nft -c -f "$TMP_RULES"; then
    echo "[!] ERROR: Syntax check failed. Configuration aborted."
    rm -f "$TMP_RULES"
    exit 1
fi

echo "[*] Applying rules via nftables service..."
cp "$TMP_RULES" "$CONF_FILE"
manage_service "restart"
manage_service "enable"

echo -e "\n--- SAFETY REVERT CHECK ---"
echo "NOTE: Attempt a new connection to test, established traffic is still allowed."
echo "Press 'y' to KEEP these settings. Reverting in 15 seconds..."

if read -t 15 -n 1 -p "Confirm (y/n): " confirm && [[ $confirm == [yY] ]]; then
    echo -e "\n\n[+] Settings CONFIRMED."
    echo "[i] Current ruleset:"
    nft list ruleset
    echo "[i] Service status:"
    manage_service "status"
else
    echo -e "\n\n[!] NO CONFIRMATION OR REJECTED. REVERTING..."
    cp "$BACKUP_PATH" "$CONF_FILE"
    manage_service "restart"

    echo "[+] Firewall rules restored to previous state."
    echo -e "\n--- DOUBLE SAFETY REVERT CHECK ---"
    echo "Press 'y' to KEEP these settings. Clearing firewall in 15 seconds..."
    if read -t 15 -n 1 -p "Confirm (y/n): " confirm2 && [[ $confirm2 == [yY] ]]; then
        echo -e "\n[+] Access confirmed OK after revert. Exiting."
    else
        echo -e "\n\n[!!]DOUBLE FAILSAFE TRIGGERED"
        disable_firewall
    fi
fi

rm -f "$TMP_RULES"

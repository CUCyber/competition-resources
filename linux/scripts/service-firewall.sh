#!/bin/bash
# service-firewall.sh
# Author: Dylan Harvey
# Description: Interactive firewall script that adds rules required for AD and common services
# Dependencies: nftables (nft), bash, tr, xargs, systemctl/service
# Note: Unlike windows variant, this will override all rules, use on its own. Hard to do in conjunction with nuke-firewall.sh (for now)
# WARNING: WIP and not well tested! Not as easy to implement on linux firewall in this case.

# === CONFIG ===
ALLOW_IPS="10.2.0.0/24"      # CHANGE, Supports CIDR and individual IPs (space or comma separated)
RULE_COMMENT="BLUE_MGMT"
SCOREBOARD_IPS="10.3.2.1"    # CHANGE, Supports CIDR and individual IPs (space or comma separated)
DC_IPS="10.3.4.1 10.3.4.2"   # CHANGE, Supports CIDR and individual IPs (space or comma separated)
DM_IPS="10.3.4.0/24"         # CHANGE, Supports CIDR and individual IPs (space or comma separated)
DOMAIN_IPS="$DC_IPS $DM_IPS"
ALL_IPS="$SCOREBOARD_IPS $DOMAIN_IPS"

INBOUND_ACTION="drop"    # default drop
OUTBOUND_ACTION="drop"   # default accept (Block super strict, will stop C2+RevShell and probably break more stuff)

BACKUP_PATH="/etc/nftables.conf.bak"
CONF_FILE="/etc/nftables.conf"
TMP_RULES="/tmp/nftables_new.conf"

IS_DC=false
IS_DM=false

declare -A SVC_PORTS=(
    ["Web (HTTP/S)"]="80, 443"
    ["Web HTTP Alt"]="8000, 8008, 8080"
    ["Web HTTPS Alt"]="8443, 8444"
    ["Mail (SMTP)"]="25, 465, 587"
    ["Mail (IMAP)"]="143, 993"
    ["Mail (POP3)"]="110, 995"
    ["SSH"]="22"
    ["MySQL/MariaDB"]="3306"
    ["PostgreSQL"]="5432"
    ["FTP"]="20, 21"
    ["SNMP"]="161, 162"
)

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# === HELPERS ===
format_ips() {
    echo "$1" | tr ' ' '\n' | sort -u | tr '\n' ',' | sed 's/,,*/,/g; s/^,//; s/,$//'
}

backup_rules() {
    if [[ -f "$CONF_FILE" ]]; then
        cp "$CONF_FILE" "$BACKUP_PATH"
        echo "[+] Backup created at $BACKUP_PATH"
    fi
}

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

# === ROLE DETECTION ===
echo "[*] Detecting System Role..."
if command -v realm >/dev/null 2>&1; then
    if realm list | grep -q "type: kerberos"; then
        echo "[+] Detected: Domain Member (via realm)"
        IS_DM=true
    else
        echo "[i] No active realm join found."
    fi
fi

if [ -f "/etc/samba/smb.conf" ] && grep -q "server role = active directory domain controller" /etc/samba/smb.conf; then
    echo "[+] Detected: Domain Controller (via smb.conf)"
    IS_DC=true
    IS_DM=false
fi

if [ "$IS_DC" = false ] && [ "$IS_DM" = false ]; then
    read -p "Role detection failed. Is this a (1) DC, (2) Domain Member, or (3) Standalone? [1-3]: " role_choice
    [[ "$role_choice" == "1" ]] && IS_DC=true
    [[ "$role_choice" == "2" ]] && IS_DM=true
fi

# === RULE GENERATION ===
echo "[*] Generating ruleset..."

# --- INBOUND ---
cat <<EOF > "$TMP_RULES"
flush ruleset

table inet filter {
    set scoreboard_ips { type ipv4_addr; flags interval; auto-merge; elements = { $(format_ips "$SCOREBOARD_IPS") } }
    set dc_ips { type ipv4_addr; flags interval; auto-merge; elements = { $(format_ips "$DC_IPS") } }
    set domain_ips { type ipv4_addr; flags interval; auto-merge; elements = { $(format_ips "$DOMAIN_IPS") } }
    set all_trusted { type ipv4_addr; flags interval; auto-merge; elements = { $(format_ips "$ALL_IPS") } }

    chain input {
        type filter hook input priority 0; policy $INBOUND_ACTION;

        iif "lo" accept
        ct state established,related accept
        ct state invalid drop

        ip saddr { $(format_ips "$ALLOW_IPS") } accept comment "$RULE_COMMENT"

        icmp type { echo-request, destination-unreachable, time-exceeded } accept comment "PING-In"

        ip saddr @domain_ips tcp dport { 22, 5985, 5986, 3389 } accept comment "MGMT-In"
EOF

if [ "$IS_DC" = true ]; then
    cat <<EOF >> "$TMP_RULES"
        # Domain Controller Inbound
        ip saddr @domain_ips tcp dport { 53, 88, 135, 389, 445, 464, 636, 3268, 3269, 49152-65535 } accept comment "AD-Svc-TCP"
        ip saddr @domain_ips udp dport { 53, 88, 123, 135, 389, 445, 464 } accept comment "AD-Svc-UDP"
        ip saddr @dc_ips tcp dport 5722 accept comment "DC-DFS-R"
EOF
elif [ "$IS_DM" = true ]; then
    cat <<EOF >> "$TMP_RULES"
        # Domain Member Inbound
        ip saddr @dc_ips tcp dport 49152-65535 accept comment "DM-In-RPC"
EOF
fi

# --- OPTIONAL SERVICES ---
echo -e "\n--- Optional Service Configuration ---"
if read -n 1 -p "Would you like to configure Services now? (y/N): " configure && [[ $configure == [yY] ]]; then
    echo ""
    for svc in "${!SVC_PORTS[@]}"; do
        ports=${SVC_PORTS[$svc]}
        first_port=$(echo "$ports" | cut -d',' -f1 | tr -d ' ')
        status="[CLOSED]"
        ss -tlpn | grep -q ":$first_port " && status="[LISTENING]"

        read -p "Allow $svc (Ports: $ports) $status? (y/N): " choice
        if [[ $choice == [yY] ]]; then
            proto="tcp"
            [[ "$svc" == "SNMP" ]] && proto="udp"
            echo "        ip saddr @all_trusted $proto dport { $ports } accept comment \"SVC-$svc\"" >> "$TMP_RULES"
        fi
    done
fi

# --- OUTBOUND ---
cat <<EOF >> "$TMP_RULES"
        log prefix "NFT_INPUT_POLICY: " flags all
    }

    chain output {
        type filter hook output priority 0; policy $OUTBOUND_ACTION;

        oif "lo" accept
        ct state established,related accept

        ip daddr { $(format_ips "$ALLOW_IPS") } accept comment "$RULE_COMMENT"

        icmp type { echo-request, destination-unreachable, time-exceeded } accept comment "PING-Out"
EOF

if [ "$IS_DC" = true ]; then
    cat <<EOF >> "$TMP_RULES"
        # Domain Controller Outbound
        ip daddr @dc_ips tcp dport { 53, 88, 135, 389, 445, 464, 636, 3268, 3269, 49152-65535 } accept
        ip daddr @dc_ips udp dport { 53, 88, 123, 135, 389, 445, 464 } accept
        ip daddr @dc_ips tcp dport 5722 accept comment "DC-DFS-R"
EOF
elif [ "$IS_DM" = true ]; then
    cat <<EOF >> "$TMP_RULES"
        # Domain Member Outbound
        ip daddr @dc_ips tcp dport { 53, 88, 135, 389, 445, 464, 636, 3268, 3269, 49152-65535 } accept
        ip daddr @dc_ips udp dport { 53, 88, 123, 135, 389, 445, 464 } accept
EOF
fi

cat <<EOF >> "$TMP_RULES"
        log prefix "NFT_OUTPUT_POLICY: " flags all
    }
}
EOF

# === EXECUTION ===
backup_rules

echo "[*] Verifying syntax..."
if ! nft -c -f "$TMP_RULES"; then
    echo "[!] SYNTAX ERROR: The generated ruleset is invalid."
    exit 1
fi

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

#!/usr/bin/env bash
#
# rejoin-domain.sh — Leave and rejoin a Linux host to an Active Directory domain
# (realmd + sssd), then re-apply local SSSD/access customizations.
#
# Use when sssd.conf / krb5.conf / keytab got overwritten or broken.
#
# Usage:
#   sudo ./rejoin-domain.sh -d example.com -u joinadmin [options]
#
# Options:
#   -d DOMAIN      AD domain (required), e.g. corp.example.com
#   -u USER        AD account with rights to join computers (required)
#   -o OU          Computer OU, e.g. "OU=Linux,OU=Servers,DC=corp,DC=example,DC=com"
#   -g GROUPS      Comma-separated AD groups allowed to log in, e.g. "linux-admins,devs"
#   -s             Short usernames (use_fully_qualified_names = False)
#   -n             Dry run: show what would happen, change nothing
#   -h             Help
#
# Password: read from $JOIN_PASSWORD if set, otherwise prompted (never put it on the CLI).
#
set -euo pipefail

DOMAIN=""
JOIN_USER=""
OU=""
ALLOW_GROUPS=""
SHORT_NAMES=false
DRY_RUN=false

BACKUP_DIR="/root/domain-rejoin-backup-$(date +%Y%m%d-%H%M%S)"
CONFIG_FILES=(
  /etc/sssd/sssd.conf
  /etc/krb5.conf
  /etc/krb5.keytab
  /etc/realmd.conf
  /etc/nsswitch.conf
  /etc/pam.d
)

log()  { echo -e "\e[1;34m[*]\e[0m $*"; }
ok()   { echo -e "\e[1;32m[+]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!]\e[0m $*" >&2; }
die()  { echo -e "\e[1;31m[x]\e[0m $*" >&2; exit 1; }

run() {
  if $DRY_RUN; then echo "    (dry-run) $*"; else "$@"; fi
}

usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while getopts ":d:u:o:g:snh" opt; do
  case $opt in
    d) DOMAIN="$OPTARG" ;;
    u) JOIN_USER="$OPTARG" ;;
    o) OU="$OPTARG" ;;
    g) ALLOW_GROUPS="$OPTARG" ;;
    s) SHORT_NAMES=true ;;
    n) DRY_RUN=true ;;
    h) usage ;;
    :) die "Option -$OPTARG needs a value" ;;
    \?) die "Unknown option -$OPTARG (use -h)" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "Run as root (sudo)."
[[ -n $DOMAIN ]]    || die "Domain is required (-d)."
[[ -n $JOIN_USER ]] || die "Join user is required (-u)."
DOMAIN_UPPER="${DOMAIN^^}"

# --- 1. Prerequisites -------------------------------------------------------
log "Checking required tools..."
for bin in realm sssctl kinit klist systemctl; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' not found. Install realmd, sssd, sssd-tools, adcli, krb5 client tools."
done

log "Checking that $DOMAIN can be discovered..."
realm discover "$DOMAIN" >/dev/null 2>&1 || die "Cannot discover $DOMAIN. Check DNS (resolv.conf) and network to the DCs."

# Clock skew > 5 min breaks Kerberos
if command -v timedatectl >/dev/null; then
  timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q yes \
    || warn "Clock is not NTP-synchronized. Kerberos fails if skew > 5 minutes."
fi

# --- 2. Password -------------------------------------------------------------
if [[ -z "${JOIN_PASSWORD:-}" ]]; then
  read -rsp "Password for ${JOIN_USER}@${DOMAIN_UPPER}: " JOIN_PASSWORD; echo
fi
[[ -n $JOIN_PASSWORD ]] || die "Empty password."

# --- 3. Backup ---------------------------------------------------------------
log "Backing up current config to $BACKUP_DIR"
run mkdir -p "$BACKUP_DIR"
for f in "${CONFIG_FILES[@]}"; do
  [[ -e $f ]] && run cp -a "$f" "$BACKUP_DIR/" || true
done
run chmod 700 "$BACKUP_DIR"

# --- 4. Leave ----------------------------------------------------------------
if realm list --name-only 2>/dev/null | grep -qix "$DOMAIN"; then
  log "Leaving $DOMAIN..."
  if ! $DRY_RUN; then
    # Try a clean leave (removes computer account); fall back to local-only leave.
    if ! printf '%s\n' "$JOIN_PASSWORD" | realm leave -U "$JOIN_USER" "$DOMAIN" 2>/dev/null; then
      warn "Clean leave failed (common if config is broken). Doing local leave only."
      realm leave "$DOMAIN" 2>/dev/null || warn "Local leave also failed; cleaning up manually."
    fi
  fi
else
  warn "Host does not appear joined to $DOMAIN (realm list). Cleaning up and joining fresh."
fi

# --- 5. Clean leftovers ------------------------------------------------------
log "Stopping sssd and clearing caches/stale keytab..."
run systemctl stop sssd || true
run rm -f /etc/krb5.keytab
run rm -rf /var/lib/sss/db/* /var/lib/sss/mc/*
run kdestroy -A 2>/dev/null || true

# --- 6. Join -----------------------------------------------------------------
JOIN_ARGS=(join -U "$JOIN_USER" --verbose)
[[ -n $OU ]] && JOIN_ARGS+=(--computer-ou="$OU")
JOIN_ARGS+=("$DOMAIN")

log "Joining $DOMAIN as $JOIN_USER..."
if ! $DRY_RUN; then
  printf '%s\n' "$JOIN_PASSWORD" | realm "${JOIN_ARGS[@]}" \
    || die "Join failed. Backup of old config is in $BACKUP_DIR"
fi
unset JOIN_PASSWORD

# --- 7. Re-apply local SSSD customizations ------------------------------------
SSSD_CONF=/etc/sssd/sssd.conf
SECTION="domain/${DOMAIN}"

set_sssd_opt() {   # set_sssd_opt key value  -> sets it inside [domain/DOMAIN]
  local key=$1 val=$2
  if $DRY_RUN; then echo "    (dry-run) [$SECTION] $key = $val"; return; fi
  if grep -qE "^\s*${key}\s*=" "$SSSD_CONF"; then
    sed -i -E "/^\[${SECTION//\//\\/}\]/,/^\[/ s|^\s*${key}\s*=.*|${key} = ${val}|" "$SSSD_CONF"
  else
    sed -i -E "/^\[${SECTION//\//\\/}\]/a ${key} = ${val}" "$SSSD_CONF"
  fi
}

log "Applying SSSD settings..."
if $SHORT_NAMES; then
  set_sssd_opt use_fully_qualified_names False
  set_sssd_opt fallback_homedir /home/%u
fi
# Add your own standard tweaks here, e.g.:
# set_sssd_opt ad_gpo_access_control permissive
# set_sssd_opt dyndns_update True
run chmod 600 "$SSSD_CONF"

if [[ -n $ALLOW_GROUPS ]]; then
  log "Restricting logins to groups: $ALLOW_GROUPS"
  run realm deny --all
  IFS=',' read -ra GRP <<< "$ALLOW_GROUPS"
  for g in "${GRP[@]}"; do run realm permit -g "$(echo "$g" | xargs)"; done
fi

# Ensure home dirs get created on first login
if command -v authselect >/dev/null; then
  run authselect select sssd with-mkhomedir --force
  run systemctl enable --now oddjobd 2>/dev/null || true
elif command -v pam-auth-update >/dev/null; then
  run pam-auth-update --enable mkhomedir
fi

# --- 8. Restart & verify -----------------------------------------------------
log "Restarting sssd..."
run sssctl cache-remove -o -p -s 2>/dev/null || true
run systemctl enable --now sssd
run systemctl restart sssd

if $DRY_RUN; then ok "Dry run complete. Nothing was changed."; exit 0; fi

sleep 3
log "Verifying..."
realm list "$DOMAIN" | grep -q "configured: kerberos-member" \
  && ok "realm: joined to $DOMAIN" || warn "realm list doesn't show kerberos-member"

klist -k /etc/krb5.keytab >/dev/null 2>&1 \
  && ok "keytab present ($(klist -k /etc/krb5.keytab | tail -n +4 | wc -l) entries)" \
  || warn "No keytab found"

if $SHORT_NAMES; then TEST_ID="$JOIN_USER"; else TEST_ID="${JOIN_USER}@${DOMAIN}"; fi
if id "$TEST_ID" >/dev/null 2>&1; then
  ok "User lookup works: $(id "$TEST_ID")"
else
  warn "Could not resolve $TEST_ID yet. Check: journalctl -u sssd -n 50"
fi

ok "Done. Previous config backed up in $BACKUP_DIR"

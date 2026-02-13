#!/bin/sh
# rsync backup script
# usage: sh rsync.sh
# requirements: 
#   - rsync needs to be installed on both the client and server
#   - user needs to execute rsync as root with no password (handled by reset_perms.sh)

CONFIG_FILE="rsync.conf"
BACKUP_ROOT="backups"
LOG_FILE="$BACKUP_ROOT/rsync_backups.log"

SSH_USER="monkey" # CHANGE USER IF NEEDED
SSH_KEY="~/Downloads/team_key"  # CHANGE PATH

RUN_TS="$(date '+%F_%H%M%S')"
RUN_DIR="$BACKUP_ROOT/$RUN_TS"

log() {
  printf '[%s] %s\n' "LOG" "$*" | tee -a "$LOG_FILE"
}

if [ -z "$SSH_USER" ]; then
  log "ERROR: SSH User is empty!"
  exit 1
fi

if [ -z "$SSH_KEY" ]; then
  log "ERROR: SSH key path is empty!"
  exit 1
fi

if [ ! -r "$CONFIG_FILE" ]; then
  log "ERROR: Cannot read config file: $CONFIG_FILE"
  exit 1
fi

if [ ! -r "$SSH_KEY" ]; then
  log "ERROR: Cannot read SSH key: $SSH_KEY"
  exit 1
fi


mkdir -p "$RUN_DIR"
touch "$LOG_FILE"

SSH_OPTS="-i $SSH_KEY -o BatchMode=yes"

log "Starting backup run: $RUN_TS"
log "Config: $CONFIG_FILE"
log "Dest:   $RUN_DIR"

failures=0

while IFS= read -r line || [ -n "$line" ]; do
  # trim leading/trailing whitespace (POSIX via sed)
  line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

  # skip blank/comment lines
  [ -z "$line" ] && continue
  case "$line" in
    \#*) continue ;;
  esac

    ip=${line%%:*}
    path=${line#*:}

  # validate format
  if [ "$ip" = "$line" ] || [ -z "$ip" ] || [ -z "$path" ]; then
    log "WARN: Skipping invalid line (expected IP:/path): $line"
    failures=$((failures + 1))
    continue
  fi

  case "$path" in
    /*) : ;;
    *)
      log "WARN: Skipping invalid path (must be absolute): $line"
      failures=$((failures + 1))
      continue
      ;;
  esac

  host_dir="$RUN_DIR/$ip"
  mkdir -p "$host_dir"

  # safe folder name: strip leading /, replace remaining / with _
  safe_path=$(printf '%s' "$path" | sed 's#^/##; s#/#_#g')
  dest="$host_dir/$safe_path"

  log "Backing up $SSH_USER@$ip:$path -> $dest"

  if ! ssh $SSH_OPTS -n "$SSH_USER@$ip" "sudo -n test -e '$path'" </dev/null >/dev/null 2>&1; then
    log "ERROR: Remote path not accessible: $SSH_USER@$ip:$path"
    failures=$((failures + 1))
    continue
  fi

  # rsync pull
  # -H: preserve hard links
  # -A: preserve ACLs
  # -X: preserve extended attributes (xattrs)
  if ! rsync -a \
    --rsync-path="sudo -n /usr/bin/rsync" \
    -e "ssh $SSH_OPTS" \
    "$SSH_USER@$ip:$path" \
    "$dest/" >>"$LOG_FILE" 2>&1; then
  log "ERROR: rsync failed for $ip:$path"
  failures=$((failures + 1))
  continue
  fi

  log "OK: $ip:$path"
done < "$CONFIG_FILE"

log "Backup run complete: $RUN_TS (failures=$failures)"

[ "$failures" -gt 0 ] && exit 2
exit 0

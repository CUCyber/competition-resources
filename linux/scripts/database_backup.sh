#!/bin/sh
# THANK YOU CHATGPT :sob :pray :pray
# Author: ChatGPT
#
# Usage:
#   ./database_backup <ssh_user> <target-ip-or-host> <postgres|mysql> <ssh_key_path>
#
# Args:
#   $1 = SSH user
#   $2 = target IP/hostname
#   $3 = db type (postgres|mysql)
#   $4 = SSH key path
#
# Optional env:
#   SSH_PORT (default 22)
#   DB_USER (postgres default: postgres; mysql default: root)
#   DB_PASS (if not using sudo path)
#   OUT_DIR (default ./db_backups)
#   COMPRESS (gzip|none, default gzip)
#   SSH_OPTS (extra ssh opts)
#   REQUIRE_SUDO (mysql only; default 1; set to 0 to use DB_USER/DB_PASS instead)
#
#   RESTORING FROM BACKUP: 
#   gzip -dc backup.gz | ssh -i /path/to/key users@IP "sudo -u postgres psql"

set -eu

SSH_USER=${1:-}
TARGET=${2:-}
DBTYPE=${3:-}
SSH_KEY=${4:-}

if [ -z "$SSH_USER" ] || [ -z "$TARGET" ] || [ -z "$DBTYPE" ] || [ -z "$SSH_KEY" ]; then
  echo "Usage: $0 <ssh_user> <target-ip-or-host> <postgres|mysql> <ssh_key_path>" >&2
  exit 2
fi

case "$DBTYPE" in
  postgres|mysql) ;;
  *)
    echo "ERROR: db type must be 'postgres' or 'mysql' (got: $DBTYPE)" >&2
    exit 2
    ;;
esac

# basic local validation
if [ ! -r "$SSH_KEY" ]; then
  echo "ERROR: SSH key not readable: $SSH_KEY" >&2
  exit 2
fi

SSH_PORT=${SSH_PORT:-22}
OUT_DIR=${OUT_DIR:-./db_backups}
COMPRESS=${COMPRESS:-gzip}
SSH_OPTS=${SSH_OPTS:-}
REQUIRE_SUDO=${REQUIRE_SUDO:-1}

umask 077
mkdir -p "$OUT_DIR"

ts=$(date '+%Y%m%d_%H%M%S')
safe_target=$(echo "$TARGET" | tr '.:/' '___')

SSH_BASE="ssh -p $SSH_PORT -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new $SSH_OPTS"
SCP_BASE="scp -P $SSH_PORT -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new $SSH_OPTS"

remote_run() {
  # $1 = remote command string
  # shellcheck disable=SC2086
  $SSH_BASE "$SSH_USER@$TARGET" "$1"
}

remote_mktempdir() {
  remote_run 'd=$(mktemp -d "/tmp/dbbackup.XXXXXX") && echo "$d"'
}

remote_cleanup() {
  remote_run "rm -rf '$1'"
}

make_remote_backup() {
  dbtype=$1
  rdir=$2

  case "$dbtype" in
    postgres)
      # Use OS-level peer auth by running pg_dumpall as the postgres OS user.
      remote_run "
      set -eu
      cd '$rdir'
      command -v pg_dumpall >/dev/null 2>&1
      sudo -n -u postgres pg_dumpall > dump.sql
      "

      if [ "$COMPRESS" = "gzip" ]; then
        remote_run "
        set -eu
        cd '$rdir'
        gzip -f dump.sql
        test -f dump.sql.gz
        echo dump.sql.gz
        "
      else
        remote_run "
        set -eu
        cd '$rdir'
        test -f dump.sql
        echo dump.sql
        "
      fi
      ;;

    mysql)
      DBU=${DB_USER:-root}

      # Default path: sudo-based dump (handles ubuntu/mariadb unix_socket root auth)
      if [ "$REQUIRE_SUDO" = "1" ]; then
        remote_run "
        set -eu
        cd '$rdir'
        command -v mysqldump >/dev/null 2>&1
        sudo -n mysqldump --all-databases --single-transaction --routines --events --triggers > dump.sql
        "
      else
        if [ "${DB_PASS:-}" ]; then
          remote_run "
          set -eu
          cd '$rdir'
          command -v mysqldump >/dev/null 2>&1
          mysqldump --all-databases -u '$DBU' -p'${DB_PASS}' \
            --single-transaction --routines --events --triggers > dump.sql
          "
        else
          remote_run "
          set -eu
          cd '$rdir'
          command -v mysqldump >/dev/null 2>&1
          mysqldump --all-databases -u '$DBU' \
            --single-transaction --routines --events --triggers > dump.sql
          "
        fi
      fi

      if [ "$COMPRESS" = "gzip" ]; then
        remote_run "
        set -eu
        cd '$rdir'
        gzip -f dump.sql
        test -f dump.sql.gz
        echo dump.sql.gz
        "
      else
        remote_run "
        set -eu
        cd '$rdir'
        test -f dump.sql
        echo dump.sql
        "
      fi
      ;;
  esac
}

pull_backup() {
  rdir=$1
  rfile=$2
  lpath=$3
  # shellcheck disable=SC2086
  $SCP_BASE "$SSH_USER@$TARGET:$rdir/$rfile" "$lpath"
}

echo "[*] SSH User: $SSH_USER"
echo "[*] Target: $TARGET"
echo "[*] DB type: $DBTYPE"

echo "[*] Creating remote temp dir..."
rdir=$(remote_mktempdir)

cleanup() {
  remote_cleanup "$rdir" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

echo "[*] Running remote backup..."
rfile=$(make_remote_backup "$DBTYPE" "$rdir" | tail -n 1) || {
  echo "ERROR: remote backup failed; not attempting scp" >&2
  exit 1
}

if [ -z "$rfile" ]; then
  echo "ERROR: remote backup did not return a filename; not attempting scp" >&2
  exit 1
fi

ext=$(echo "$rfile" | awk -F. '{print $NF}')
local_file="$OUT_DIR/${safe_target}_${DBTYPE}_${ts}.${ext}"

echo "[*] Pulling backup back to local: $local_file"
pull_backup "$rdir" "$rfile" "$local_file"

echo "[*] Done: $local_file"

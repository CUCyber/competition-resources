#!/bin/sh
# 99-lock-users.sh
# Author: Adam Colaianni
# Description: Automated script to lock all local users and set shell to nologin, except for specified users
# Dependencies: awk, cp, cat, rm

EXCLUDE="root monkey blackteam seccdc"

# Pick a nologin shell that exists
NOLOGIN="/usr/sbin/nologin"
[ -x "$NOLOGIN" ] || NOLOGIN="/sbin/nologin"
[ -x "$NOLOGIN" ] || NOLOGIN="/bin/false"

in_exclude() {
    case " $EXCLUDE " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

tmp1="/tmp/lock-users.passwd.$$"
tmp2="/tmp/lock-users.shadow.$$"
trap 'rm -f "$tmp1" "$tmp2" 2>/dev/null || true' EXIT HUP INT TERM

# --- Update shells in /etc/passwd (except excluded) ---
# fields: name:pw:uid:gid:gecos:home:shell
awk -F: -v OFS=: -v nologin="$NOLOGIN" -v excl=" $EXCLUDE " '
{
  u=$1
  if (index(excl, " " u " ") == 0) $7=nologin
  print
}' /etc/passwd > "$tmp1"

# Keep a backup; preserve behavior even if cp lacks -p
cp /etc/passwd /etc/passwd~ 2>/dev/null || true
cat "$tmp1" > /etc/passwd
rm -f "$tmp1"

# --- Lock passwords in /etc/shadow (Linux local users) ---
# If /etc/shadow exists, prefix password hash with "!" for non-excluded users (idempotent).
if [ -f /etc/shadow ]; then
    awk -F: -v OFS=: -v excl=" $EXCLUDE " '
    {
      u=$1
      if (index(excl, " " u " ") == 0) {
        if ($2 !~ /^!/) $2="!" $2
      }
      print
    }' /etc/shadow > "$tmp2"

    cp /etc/shadow /etc/shadow~ 2>/dev/null || true
    cat "$tmp2" > /etc/shadow
    rm -f "$tmp2"
fi

echo "Locked users."

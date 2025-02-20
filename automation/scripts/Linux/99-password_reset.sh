#!/bin/sh

# Space separated list of users to ignore
IGNORE_USER_LIST="ansible gold-team seccdc_adm" # CHANGE

# The new password to set all users passwords to
PASSWORD="" # CHANGE

# [ -z "${IGNORE_USER_LIST-}" ] && echo "IGNORE LIST UNSET" && exit 2
[ -z "${PASSWORD-}" ] && echo "NO PASSWORD SET" && exit 2

sys=`which chpasswd 2>/dev/null`

if [ $? -ne 0 ]; then
  sys=`which pw 2>/dev/null`

  if [ $? -ne 0 ]; then
    sys=`which passwd 2>/dev/null`
    if [ $? -ne 0 ]; then
      echo "No known binaries to reset passwords with"
      exit 2
    fi

    # Make sure passwd has the --stdin option
    if ! echo `passwd -h` | grep -q "--stdin"; then
      echo "No known binaries to reset passwords with"
      exit 2
    fi

    cmd="passwd"

  else
    cmd="pw"
  fi

else
  cmd="chpasswd"
fi

# Gets all users (system and regular)
users=`awk -F: '{print $1}' /etc/passwd`

# Alternative version that only gets regular users + root.
#users=`awk -F '$3 >= 1000' '{print $1}' /etc/passwd`
#users="$users root"

# Backup /etc/shadow
cp /etc/shadow /etc/backup_shadow

# Reset all passwords
for user in $users; do

  # Skip the user if they are in the ignore list
  case " $IGNORE_USER_LIST " in
    *" $user "*)
      echo "SKIPPING USER $user"
      continue
      ;;
  esac

  if [ "$cmd" = "chpasswd" ]; then
    echo "$user:$PASSWORD" | $sys

  elif [ "$cmd" = "passwd" ]; then
    echo "$PASSWORD" | $sys -s $user

  elif [ "$cmd" = "pw" ]; then
    # -h 0 = Read from stdin
    echo "$PASSWORD" | $sys usermod -n $user -h 0
  fi

  echo "Reset $user's password"
done

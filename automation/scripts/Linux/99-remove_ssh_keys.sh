#!/bin/sh

# Space separated list of users to ignore. ec2-user will be by script added later
# ENSURE THE DESIRED LINUX USER IS ADDED HERE
IGNORE_USER_LIST=""

[ -z "${IGNORE_USER_LIST-}" ] && echo "IGNORE LIST UNSET" && exit 2

IGNORE_USER_LIST="$IGNORE_USER_LIST ec2-user"

authorized_keys="`find / -name "authorized_keys" 2>/dev/null`"

# Remove all keys for users not in the ignore list
for file in $authorized_keys; do

  # Skip the file if the user is in the ignore list
  for user in $IGNORE_USER_LIST; do
    case "$file" in
      *"$user"*)
        echo "SKIPPING FILE $file"
        continue 2
        ;;
    esac
  done

  rm $file

  echo "Removed $file"
done

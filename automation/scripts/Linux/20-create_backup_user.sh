#!/bin/sh

# The new user
NEW_USER=""

# The new password to set all users passwords to
PASSWORD=""

[ -z "${NEW_USER-}" ] && echo "NO NEW USER SET" && exit 2
[ -z "${PASSWORD-}" ] && echo "NO PASSWORD SET" && exit 2

sys=`which useradd 2>/dev/null`

if [ $? -ne 0 ]; then
  sys=`which pw 2>/dev/null`
  if [ $? -ne 0 ]; then
    echo "No known binaries to create new users"
    exit 2
  fi
  cmd="pw"
else
  cmd="useradd"
fi

# Create the new user
if [ "$cmd" = "useradd" ]; then
  $sys -m -s `which sh` -p `openssl passwd -6 "$PASSWORD"` $NEW_USER

elif [ "$cmd" = "pw" ]; then
   echo "$PASSWORD" | $sys useradd -n $NEW_USER -m -s `which sh` -h 0
fi

if [ $? -ne 0 ]; then
  echo "Failed to create new user"
  exit 2
fi

# Add user to sudoers file
echo "$NEW_USER ALL=(ALL : ALL) NOPASSWD: ALL" >> /etc/sudoers

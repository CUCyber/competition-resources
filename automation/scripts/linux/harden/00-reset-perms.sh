#!/bin/sh
# 99-reset-perms.sh
# Author: Adam Colaianni
# Description: Automated script to reset sudoers perms.
# Dependencies: cp, groupdel, groupadd, cat, chown, chmod, usermod

cp -Ra /etc/sudoers.d /etc/sudoers.d~
groupdel wheel && groupadd wheel
groupdel sudo && groupadd sudo
cp -a /etc/sudoers /etc/sudoers~
cat >/etc/sudoers <<- EOF
root ALL=(ALL) ALL
%wheel ALL=(ALL) ALL
%sudo ALL=(ALL) ALL
monkey ALL=(root) NOPASSWD: /usr/bin/rsync
EOF

chown root:root /etc/sudoers
chmod 600 /etc/sudoers

usermod -aG sudo root
usermod -aG sudo monkey
usermod -aG sudo blackteam

usermod -aG wheel root
usermod -aG wheel monkey
usermod -aG wheel blackteam

echo "merge stuff from '/etc/sudoers~' and '/etc/sudoers.d~/'"
echo "Sudoers perms reset."

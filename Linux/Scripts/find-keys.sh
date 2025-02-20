#!/bin/sh

grep PermitRootLogin /etc/ssh/sshd_config

grep AuthorizedKeysFile /etc/ssh/sshd_config | awk '{ $1=""; print $0 }' | tr ' ' '\n'
sudo find / -iname authorized_keys

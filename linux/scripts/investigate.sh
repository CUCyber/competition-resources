#!/bin/sh

# usage: investigate.sh [ssh|suid_guid|groups|upx|drives|pam|domain|pii|linpeas]

ssh() {
	echo '=== SSH ==='
	echo '== SSHD_CONFIG =='
	grep -v '^$\|^#' /etc/ssh/sshd_config | column -t

	echo '== KEYS ==' >&2
	sudo find / -type f -iname authorized_keys
}

groups() {
	echo '=== GROUPS ==='
	awk -F: '$NF != "" { print $0 }' /etc/group
}

suid_sgid() {
	echo '=== SUID/SGID ==='
	sudo find / -perm -u=s -o -perm -g=s -type f 2>/dev/null |
		grep --line-buffered -v '/usr/bin/\(pkexec\|umount\|su\|gpasswd\|newgrp\|fusermount\|at\|chsh\|passwd\|chfn\|mount\)'

	echo 'CAN ALSO EXCLUDE (AT TIMES): /usr/sbin/(unix_chkpwd|pam_extrausers_chkpwd) /usr/lib/dbus(-1.0)?/dbus-daemon-launch-helper /usr/lib/(open)?ssh/ssh-keysign' >&2
}

upx() {
	echo '=== UPX ==='
	sudo find / -type f -exec grep -q 'UPX executable' {} \; -print
}

drives() {
	echo '=== MOUNTED DRIVES ==='
	lsblk -f
	systemctl list-automounts --all --plain
}

pam() {
	echo '=== PAM ==='
	grep -R 'nullok\|debug\|first_pass\|forward_pass\|default=\(success\|ignore\)' /etc/pam.d/
	grep -R 'pam_\(exec\|python\|perl\|ssh\|tacplus\|radius\|ldap\|permit\|deny\)' /etc/pam.d/
	ls -lt /etc/pam.d /usr/lib/security
	perl -nle 'next if /^\s*(#|\w+\s+include)/; @f=(); while(/\s*(\[[^\]]*\]|\S+)/g){push @f,$1} print join "\t", @f;' /etc/pam.d/* |
		sort -u -k3 -t"$(printf '\t')" |
		column -t -s "$(printf '\t')"
}

domain() {
	echo '=== DOMAIN ==='
	net ads info

	echo '== DNS =='
	cat /etc/resolv.conf
	echo '== SAMBA =='
	cat /etc/samba/smb.conf
	echo '== KERBEROS =='
	cat /etc/krb5.conf
	echo '== SSSD =='
	cat /etc/sssd/sssd.conf
}

pii() {
	echo '=== PII ==='
	DIRS='/var/log /home /etc /tmp /opt /srv /mnt /media'

	credit_card='(?:\d{4}[-\s]?){3}\d{4,6}'
	address='\d{1,5}\s[\w\s]+(?:St|Street|Ave|Avenue|Rd|Road|Blvd|Boulevard|Dr|Drive|Ln|Lane|Ct|Court|Way|Place|Pl|Pkwy|Parkway|Loop|Terrace|Square|Commons|Highway|Hwy)'
	ssn='(?!666|000|9\d{2})[0-9]{3}-(?!00)[0-9]{2}-(?!0000)[0-9]{4}'
	phone='(?:\+?[0-9]{1,3}[-.\s]?)?(?!\b(?:4\d{3}|5[1-5]\d{2}|3[47]\d{2}|6011)\d{4,14}\b)(?!\d{3}-\d{2}-\d{4})(?:\(?[2-9][0-9]{2}\)?[-.\s]?)[0-9]{3}[-.\s]?[0-9]{4}'
	email='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,10}'
	date='(0[1-9]|1[0-2])[-\/.](0[1-9]|[12][0-9]|3[01])[-\/.]([12][0-9]{3})'

	# shellcheck disable=SC2086
	sudo grep -oRE "\b$credit_card|$address|$ssn|$phone|$email|$date\b" $DIRS 2>/dev/null
}

linpeas() {
	echo '=== LINPEAS ==='
	curl -L https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh | sh -s -- -q -s
}

[ -z "$*" ] && {
	ssh
	groups
	suid_guid
	upx
	drives
	pam
	domain
	pii
	exit
}

for x in "$@"; do
	command -v "$x" >/dev/null && "$x"
done

# Report.sh
# Author: Tim Koehler
# Gathers information regarding the machine and its services.
# Useful for threat hunting and hardening.
# Run with sudo

#!/bin/sh

# Gather System Info
hostname=$(hostname)
os=$(cat /etc/os-release | grep -i "PRETTY_NAME" | sed "s/PRETTY_NAME=//g")
is_freebsd=0
if echo "$os" | grep -q "FreeBSD"; then
	is_freebsd=1
fi

# Logged in users
who_output="who_users"
who > $who_output
logged_in=$(cat $who_output | tr -s ' ' | tr ' ' ':' | awk -F: '{print $1}')
rm $who_output

printf "Machine Info 
Hostname: $hostname
OS: $os
 
Logged in Users:
$logged_in

Listening network connections:\n"
if [ $is_freebsd -eq 1 ]; then
	sockstat -l
else
	ss -tunlp | grep -i "listen"
fi	

printf "\nDump of running services:\n"
if [ $is_freebsd -eq 1 ]; then
	for svc in /etc/rc.d/* /usr/local/etc/rc.d/*; do
    		service_name=$(basename "$svc")
    		if service "$service_name" onestatus >/dev/null 2>&1; then
        		printf "$service_name is running\n"
    		fi
	done
else
	systemctl --type=service --state=running
fi

printf "\nMission critical services:\n"
if [ $is_freebsd -eq 1 ]; then
	printf "skipping on FreeBSD, look at the running services dump"
else
	systemctl | grep -i "sshd\|http\|squid\|nginx\|mysql\|postgres\|https\|mariadb\|bta\|ftp"
fi

printf "\nSSH Config (sshd_config):\n"
cat /etc/ssh/sshd_config

printf "\nFiles in /etc/ssh/sshd_conf.d:\n"
cat /etc/ssh/sshd_config.d/*

# Users with crontabs
printf "\n\nUsers with crontabs:\n"
for u in $(awk -F: '{print $1}' /etc/passwd); do
	if [ -f "/var/spool/cron/crontabs/$u" ]; then
		printf "User $u has a crontab\n"
		cat /var/spool/cron/crontabs/$u
		printf "\n\n"
	fi
done

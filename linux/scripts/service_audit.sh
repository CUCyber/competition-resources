#!/bin/sh

# usage: service_audit.sh [list|command] [units|unit-files|sockets|automounts|paths|timers]

service_list() {
	systemctl "$1" --plain --no-legend --all --full |
		perl -lane 'push @r, [@F]; END {print join "\t", (@$_[0..2], join " ", @$_[3..$#$_]) for sort {$a->[2] cmp $b->[2]||$b->[3] cmp $a->[3]} @r}' |
		column -t -s "$(printf '\t')"
}

service_command() {
	# shellcheck disable=SC2046
	systemctl show $(service_list "$1" | awk '{ print $1 }') \
		-P Names -P ExecStart -P ExecStartPre -P ExecStartPost -P ExecStop -P ExecStopPre -P ExecStopPost -P ExecReload |
		sed -E 's/.*argv\[\]=([^;]+).*/\t\1/'
}

"service_${1:-list}" "list-${2:-units}"

#!/bin/sh

# usage: sskill.sh

ss -tulpanH |
	awk '{ match($7, /pid=([0-9]+)/, arr); printf "%s|%-10s%-48s%-48s %s", $1, $2, $5, $6, $7 ? "pid="arr[1]" " : "\n"; arr[1] && system("ps -p " arr[1] " -o cmd=") }' |
	"$(dirname "$0")"/../bin/fzy |
	awk '$4 ~ /^pid/ { sub(/pid=/, "", $4); system("kill -9 " $4) }'

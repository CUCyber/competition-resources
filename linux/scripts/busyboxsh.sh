#!/bin/sh

# usage: busyboxsh.sh

bb="$(realpath "$(dirname "$0")")/../bin/busybox"
dir="$($bb mktemp -d)"

for x in $($bb --list); do $bb ln -s "$bb" "$dir/$x" & done &&
	wait && PATH="$dir:$PATH" $bb sh && $bb rm -rf "$dir"

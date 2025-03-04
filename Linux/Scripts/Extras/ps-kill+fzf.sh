#!/bin/sh

ps aux |
	../Binaries/fzf --multi --header-lines=1 --reverse |
	awk '{ print $2 }' |
	xargs kill -9

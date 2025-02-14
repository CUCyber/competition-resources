#!/bin/sh

ss -tulpan | ./fzf --preview-window=right,30% --multi --header-lines=1 --reverse --preview='echo {} | sed '"'"'s/.*pid=\([0-9]\+\).*/\1/g'"'"' | xargs ps h -o cmd -p' | sed 's/.*pid=\([0-9]\+\).*/\1/g' | xargs kill -9

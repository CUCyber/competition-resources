#!/bin/sh

# usage: pskill.sh

ps auxh --sort -%mem | "$(dirname "$0")"/../bin/fzy | awk '$2 { system("kill -9 " $2) }'

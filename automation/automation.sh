#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-f] -p param_value arg1 [arg2...]

This automation script is reponsible for the following:
  1) Enumerating a subnet.
  2) Detecting each machine's OS in a subnet.
  3) Handling automation-over-ssh by executing all scripts in
     the appropriate subdirectory of this repository.
  4) Outputting status updates for each machine and script
     that is run.

Any dependencies for these child scripts should be handled
there and not within this automation script. This is to allow
for significantly better modularity.

Available options:

-h, --help          Print this help and exit
-s, --subnet        The subnet to run scripts over
-w, --windows-user  The ssh user to use for Windows
-l, --linux-user    The ssh user to use for Linux
-p, --password      The password for the ssh user(s)

Dependencies:
- sshpass
- netcat
EOF
  exit
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  # script cleanup here
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}

parse_params() {
  # default values of variables set from params
  flag=0
  param=''

  while :; do
    case "${1-}" in
    -h | --help usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    -f | --flag) flag=1 ;; # example flag
    -p | --param) # example named parameter
      param="${2-}"
      shift
      ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  # check required params and arguments
  [[ -z "${param-}" ]] && die "Missing required parameter: param"
  [[ ${#args[@]} -eq 0 ]] && die "Missing script arguments"

  return 0
}

parse_params "$@"
setup_colors

# Global Vars

# script logic here
# Steps for each machine in subnet:
#   1) Detect OS
#   2) Copy ssh public key over (with ssh-copy-id) (possibly tie in with #3)
#   3) Start running appropriate handler
#     1) Transfer/execute all files in scripts directory 
#     2) Capture script execution output (and display failures)

msg "${RED}Read parameters:${NOFORMAT}"
msg "- flag: ${flag}"
msg "- param: ${param}"
msg "- arguments: ${args[*]-}"

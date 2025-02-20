#!/bin/bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

###########################################################
##################       FUNCTIONS       ##################
###########################################################

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

Additionally, this automation script is, by design, always going
to attempt to automate something. By default, with no options
specified, this script will attempt to automate both Windows and
Linux machines by setting the Windows user to "Administrator" and
the Linux user to "root".

Available options:

-h, --help            Print this help and exit.
-s, --subnet          The subnet to run scripts over. (required)
-w, --windows-user    The ssh user to use for Windows. (optional, default="Administrator")
--windows-only        Check for and run scripts against only
                      Windows machines. Does nothing when
                      used with --linux-only. (optional)
-l, --linux-user      The ssh user to use for Linux. (optional, default="root")
--linux-only          Check for and run scripts against only
                      Linux machines. Does nothing when
                      used with --windows-only. (optional)
-p, --password        The password for the ssh user(s). (required)
-i, --identity-file   The path to the private key to use.
                      The corresponding public key is required
                      to be in the same directory. (required)
--no-color            Turn off colorful printing. (optional)

Dependencies (windows|linux|both):
- sshpass (both)
- netcat (both)
- iconv (windows)
- nmap (both)

Authors:
- Duncan Hogg (D42H5)
- Dylan Harvey (D-Guy2157)
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

# Sends a message to stdout. Does not automatically append a newline.
msg_stdout() {
  echo >&1 -ne "${1-}"
}

# Sends a message to stderr and exit with status
die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg_stdout "$msg\n"
  exit "$code"
}

validate_subnet() {
    local subnet="$1"
    # Invalid subnet if it doesn't match the regex
    if ! [[ "$subnet" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}\/([0-9]|[1-2][0-9]|3[0-2])$ ]]; then
      return 1
    fi

    # Further validate the IP address (0-255 per octet)
    IFS='/' read -r ip cidr <<< "$subnet"
    IFS='.' read -r oct1 oct2 oct3 oct4 <<< "$ip"

    # Check if each octet is within the range 0-255
    if (( oct1 >= 0 && oct1 <= 255 )) && (( oct2 >= 0 && oct2 <= 255 )) && \
       (( oct3 >= 0 && oct3 <= 255 )) && (( oct4 >= 0 && oct4 <= 255 )); then

        # Valid subnet if all octects within range
        return 0

    else
        # Otherwise invalid subnet
        return 1
    fi
}

parse_params() {
  while :; do
    case "${1-}" in
    -h | --help)
      usage
      ;;
    -s | --subnet)
      SUBNET="${2-}"
      shift
      ;;
    -w | --windows-user)
      WINDOWS_USER="${2-}"
      shift
      ;;
    --windows-only)
      WINDOWS_ONLY=1
      ;;
    -l | --linux-user)
      LINUX_USER="${2-}"
      shift
      ;;
    --linux-only)
      LINUX_ONLY=1
      ;;
    -p | --password)
      PASSWORD="${2-}"
      shift
      ;;
    -i | --identity-file)
      IDENTITY_FILE="${2-}"
      shift
      ;;
    --no-color)
      NO_COLOR=1
      ;;
    -?*) die "Unknown option: $1\n\nPlease use -h or --help to see valid options" ;;
    *) break ;;
    esac
    shift
  done

  # Check required params and arguments
  [[ -z "${SUBNET-}" ]] && die "Missing required parameter: subnet"

  if [[ "${WINDOWS_ONLY-}" == "${LINUX_ONLY-}" ]]; then
    BOTH_OS=1
  fi

  # Set default windows user as needed
  if [[ -n "${WINDOWS_ONLY-}" || -n "${BOTH_OS-}" ]]; then
    if [[ -z "${WINDOWS_USER-}" ]]; then
      WINDOWS_USER="Administrator"
    fi
  fi

  # Set default linux user as needed
  if [[ -n "${LINUX_ONLY-}" || -n "${BOTH_OS-}" ]]; then
    if [[ -z "${LINUX_USER-}" ]]; then
      LINUX_USER="root"
    fi
  fi

  [[ -z "${PASSWORD-}" ]] && die "Missing required parameter: password"
  [[ -z "${IDENTITY_FILE-}" ]] && die "Missing required parameter: identity-file"

  # Ensure SUBNET is a valid subnet
  set +e
  validate_subnet $SUBNET
  [[ $? == 1 ]] && die "Invalid subnet \"$SUBNET\""
  set -e

  # Ensure IDENTITY_FILE and IDENTITY_FILE.pub exist
  [[ ! -f $IDENTITY_FILE ]] && die "Could not find the identity-file \"$(realpath $IDENTITY_FILE)\""
  [[ ! -f "$IDENTITY_FILE.pub" ]] && die "Could not find the public identity-file \"$(realpath $IDENTITY_FILE).pub\""

  # Strip IDENTITY_FILE of ".pub" if it ends in that
  IDENTITY_FILE="${IDENTITY_FILE%.pub}"

  return 0
}

# Returns an array of all ips in a subnet
# Args:
#   $1 - the subnet to get ips from
get_ips_from_subnet() {
    local subnet="$1"  # Take subnet as input

    # Split the subnet into base IP and mask
    IFS='/' read -r base_ip mask <<< "$subnet"

    # Special cases for /31 and /32 subnets
    if [[ "$mask" == "31" ]]; then
        # /31 subnet has exactly 2 usable IPs
        result="$base_ip $(get_next_ip "$base_ip")"
        echo "$result"
        return
    elif [[ "$mask" == "32" ]]; then
        # /32 subnet has exactly 1 IP address (the base IP itself)
        echo "$base_ip"
        return
    fi

    # Calculate the number of host addresses (2^(32 - mask) - 2 for usable addresses)
    local num_hosts=$(( 2 ** (32 - mask) - 2 ))

    # Split the base IP into an array of octets
    IFS='.' read -r -a octets <<< "$base_ip"

    # Convert the IP address into a single 32-bit integer
    ip_int=$(( (${octets[0]} << 24) | (${octets[1]} << 16) | (${octets[2]} << 8) | ${octets[3]} ))

    # Initialize an empty result string
    local result=""

    # Iterate over the range of host IPs
    for ((i=1; i<=num_hosts; i++)); do
        # Increment the IP address by 1
        current_ip=$(( ip_int + i ))

        # Convert the current IP back into four octets
        octet1=$(( (current_ip >> 24) & 255 ))
        octet2=$(( (current_ip >> 16) & 255 ))
        octet3=$(( (current_ip >> 8) & 255 ))
        octet4=$(( current_ip & 255 ))

        # Append the full IP address to the result string
        result+="$octet1.$octet2.$octet3.$octet4 "
    done

    # Return the result string (without newline at the end)
    echo "$result"
}

# Helper function to calculate the next IP address in the subnet
get_next_ip() {
    ip="$1"
    IFS='.' read -r -a octets <<< "$ip"
    next_ip=$(( (${octets[3]} + 1) % 256 ))

    if (( next_ip == 0 )); then
        octets[2]=$(( octets[2] + 1 ))
    fi
    if (( octets[2] == 256 )); then
        octets[1]=$(( octets[1] + 1 ))
        octets[2]=0
    fi
    if (( octets[1] == 256 )); then
        octets[0]=$(( octets[0] + 1 ))
        octets[1]=0
    fi

    echo "${octets[0]}.${octets[1]}.${octets[2]}.$next_ip"
}

# Linux machine handler
# Args:
#   $1 - The ip address of the machine
linux_handler() {
  local ip=$1
  local remove_ssh_script=$(cat ./00-remove_ssh_keys.sh)
  local b64remove_ssh_script=$(echo "$remove_ssh_script" | base64)
  local remove_ssh_command="echo \"$b64remove_ssh_script\" | base64 -di - | sudo sh"

  msg_stdout "> Automation starting for ${CYAN}$ip${NOFORMAT}:\n"

  # Copy IDENTITY_FILE to machine with ssh-copy-id
  msg_stdout ">> Clearing SSH keys and Copying SSH Key \"$IDENTITY_FILE\" ...\n"

  set +e
  # `> /dev/null 2>&1` used to redirect all output to /dev/null
  echo "$PASSWORD" | sshpass ssh -o StrictHostKeyChecking=no $LINUX_USER@$ip $remove_ssh_command 2> /dev/null
  echo "$PASSWORD" | sshpass ssh-copy-id -i "$IDENTITY_FILE" "$LINUX_USER@$ip" 2> /dev/null
  local exit_code=$?
  set -e

  msg_stdout "<< Cleared SSH keys and Copying SSH Key \"$IDENTITY_FILE\" - "

  if [[ $exit_code == 0 ]]; then
    msg_stdout "${GREEN}OK${NOFORMAT}\n"
  else
    msg_stdout "${RED}FAILED ($exit_code)${NOFORMAT}\n"
    die "Failed to set SSH Key for ${ORANGE}$ip${NOFORMAT}" 2
  fi


  # Run each script over ssh using IDENTITY_FILE
  # as the private key.
  for script in $LINUX_SCRIPTS_DIR/*.sh; do

    local script_name="$(basename $script)"
    local b64=$(base64 $script)
    local command="echo \"$b64\" | base64 -di - | sudo sh"

    # Necessary to wrap both the ssh command AND exit_code retrieval with `set [+|-]e`.
    # This enables the script to continue even if the command over ssh fails AND
    # allows us to still retrieve the exit code.
    msg_stdout ">> Executing $script_name ...\n"

    set +e
    ssh -i $IDENTITY_FILE $LINUX_USER@$ip $command
    exit_code=$?
    set -e

    msg_stdout "<< Executed $script_name - "
    if [[ $exit_code == 0 ]]; then
      msg_stdout "${GREEN}OK${NOFORMAT}\n"
    else
      msg_stdout "${RED}FAILED ($exit_code)${NOFORMAT}\n"
    fi
  done
}

# Windows machine handler
# Args: 
#   $1 - IP of the machine
windows_handler() {
  local ip=$1
  local pubkey_value=$(cat "$IDENTITY_FILE.pub")
  local remove_ssh_script=$(cat ./00-Remove-SSH-Keys.ps1)
  local ssh_script=$(cat <<EOF
\$SSH_DIR = "\$env:USERPROFILE\\.ssh"
\$SSH_ROOT = "C:\\ProgramData\\ssh"
\$AUTH_KEYS = "\$SSH_DIR\\authorized_keys"
\$GROUP_KEYS = "\$SSH_ROOT\\administrators_authorized_keys"
\$sshKey = "$pubkey_value"
if (-Not (Test-Path \$SSH_DIR)) {
    New-Item -ItemType Directory -Path \$SSH_DIR -Force | Out-Null
}
Set-Content -Path \$AUTH_KEYS -Encoding utf8 -Value \$sshKey
Set-Content -Path \$GROUP_KEYS -Encoding utf8 -Value \$sshKey
EOF
  )
  local b64ssh_script=$(echo "$ssh_script" | iconv -t UTF-16LE | base64 -w 0)
  local b64remove_ssh_script=$(echo "$remove_ssh_script" | iconv -t UTF-16LE | base64 -w 0)

  msg_stdout "> Automation starting for ${CYAN}$ip${NOFORMAT}:\n"

  # Copy IDENTITY_FILE to machine with custom ssh-copy-id powershell script
  msg_stdout ">> Clearing SSH keys and Copying SSH Key \"$IDENTITY_FILE\" ...\n"

  set +e
  echo "$PASSWORD" | sshpass ssh -o StrictHostKeyChecking=no "$WINDOWS_USER@$ip" "powershell -enc $b64remove_ssh_script" 2> /dev/null
  echo "$PASSWORD" | sshpass ssh -o StrictHostKeyChecking=no "$WINDOWS_USER@$ip" "powershell -enc $b64ssh_script" 2> /dev/null
  local exit_code=$?
  set -e

  msg_stdout "<< Cleared SSH keys and Copying SSH Key \"$IDENTITY_FILE\" - "

  if [[ $exit_code == 0 ]]; then
    msg_stdout "${GREEN}OK${NOFORMAT}\n"
  else
    msg_stdout "${RED}FAILED ($exit_code)${NOFORMAT}\n"
    die "Failed to set SSH Key for ${ORANGE}$ip${NOFORMAT}" 2
  fi

  for script in $WINDOWS_SCRIPTS_DIR/*; do
    local script_name="$(basename $script)"
    local script_content=$(cat $script)
    local b64=$(echo "$script_content" | iconv -t UTF-16LE | base64 -w 0)
    local command="powershell -enc $b64"
    
    msg_stdout ">> Executing $script_name ...\n"

    set +e
    ssh -i $IDENTITY_FILE $WINDOWS_USER@$ip $command 2> /dev/null
    exit_code=$?
    set -e

    msg_stdout "<< Executed $script_name - "
    if [[ $exit_code == 0 ]]; then
      msg_stdout "${GREEN}OK${NOFORMAT}\n"
    else
      msg_stdout "${RED}FAILED ($exit_code)${NOFORMAT}\n"
    fi

  done

}

###########################################################
##################       MAIN CODE       ##################
###########################################################

# Global Variables
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
LINUX_SCRIPTS_DIR="$ROOT_DIR/scripts/Linux"
WINDOWS_SCRIPTS_DIR="$ROOT_DIR/scripts/Windows"
OUT_DIR="$ROOT_DIR/output"
SUBNET=""
WINDOWS_USER=""
LINUX_USER=""
PASSWORD=""
IDENTITY_FILE=""
NO_COLOR=""
LINUX_ONLY=""
WINDOWS_ONLY=""
BOTH_OS=""

# Script setup
parse_params "$@"
setup_colors

# Steps for each machine in subnet:
#   1) Detect OS
#   2) Start running appropriate handler
#     1) Copy ssh public key over (with ssh-copy-id or similar)
#     2) Transfer/execute all files in scripts directory
#     3) Capture script execution output (and display failures)

# Prepare output directory
set +e
mkdir $OUT_DIR 2>/dev/null
set -e

msg_stdout "Scanning ${PURPLE}$SUBNET${NOFORMAT} for hosts that are up...\n\n"
IPS="$(sudo nmap -T5 -sn $SUBNET -oG /dev/stdout | grep -E "^Host:" | awk '{print $2}')"
for IP in $IPS; do
  rm -f $OUT_DIR/$IP 2>/dev/null

  # Detected OS:
  #   0 = Windows
  #   1 = Linux
  DETECTED_OS=""

  # CRITICAL SET E; otherwise stops completley if no ssh
  set +e
  msg_stdout "Detecting OS for ${CYAN}$IP${NOFORMAT} - " | tee -a $OUT_DIR/$IP
  SSH_BANNER=$(nc -w 1 "$IP" 22 | head -n 1)
  set -e

  # Convert SSH_BANNER to lowercase and check for substring "windows"
  if [[ ${SSH_BANNER,,} == *"windows"* ]]; then
    msg_stdout "${GREEN}Detected Windows${NOFORMAT}\n" | tee -a $OUT_DIR/$IP
    DETECTED_OS=0
  elif [[ $SSH_BANNER != "" ]]; then
    msg_stdout "${YELLOW}Detected Linux${NOFORMAT}\n" | tee -a $OUT_DIR/$IP
    DETECTED_OS=1
  else
    msg_stdout "${RED}Failed${NOFORMAT}\n" | tee -a $OUT_DIR/$IP
    msg_stdout "${RED}Couldn't detect OS from SSH for $IP! Skipping scripts!\n${NOFORMAT}" | tee -a $OUT_DIR/$IP
    continue
  fi

  # Start appropriate handler
  if [[ ( -n "${WINDOWS_ONLY-}" || -n "${BOTH_OS-}" ) && $DETECTED_OS == 0 ]]; then
    windows_handler $IP | tee -a $OUT_DIR/$IP

  elif [[ ( -n "${LINUX_ONLY-}" || -n "${BOTH_OS-}" ) && $DETECTED_OS == 1 ]]; then
    linux_handler $IP | tee -a $OUT_DIR/$IP
  fi

  msg_stdout "\n\n"
done

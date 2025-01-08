#!/bin/bash

# Usage:
# ./new-iptables-apply.sh -f /path/to/new.rules -t timeout
# 	*NOTE* This script must be run as root to work... and iptables,
# 	  iptables-save, and iptables-restore must be available for use
# 	  as well.
#
#   -f /path/to/new.rules:
#     A path to a valid iptables rules file that will replace the
#     current iptables rules.
#
#   -t timeout:
#     Default 10. The time (in seconds) to wait for confirmation that the new
#     rules don't break connectivity.

########################################
#           HELPER FUNCTIONS           #
########################################

revert_rules() {
	local rules_path="$1"
	echo -e "\nRestoring to rules stored at $rules_path..."
	iptables-restore $rules_path
	return 0
}

cleanup() {
	local file_path="$1"
	echo -e "\nCleaning up $file_path..."
	rm $file_path
	return 0
}

########################################
#              MAIN CODE               #
########################################

# Check if the current user is root
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run as root."
  echo -e "\nUsage: sudo $0 ..."
  exit 1
fi

# Get options
RULES_PATH=""
TIMEOUT=""

# Parse command-line options
while getopts "f:t:" opt; do
    case $opt in
        f)
            RULES_PATH="$OPTARG"  # Store the path to RULES_PATH
            ;;
        t)
            TIMEOUT="$OPTARG"  # Store the number to TIMEOUT
            ;;
        h|*)
            echo "Usage: $0 -f <path> -t <timeout>"
            exit 1
            ;;
    esac
done

# Type checking

# Validation for -f (file path)
if [[ -z "$RULES_PATH" ]]; then
    echo "Error: -f <path> is required."
    exit 1
fi

if [[ ! -f "$RULES_PATH" ]]; then
    echo "Error: The file specified by -f does not exist: $RULES_PATH"
    exit 1
fi

# Default to 10 if TIMEOUT not already set
if [[ -z "$TIMEOUT" ]]; then
    TIMEOUT="10"
fi

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
    echo "Error: -t must be a positive integer."
    exit 1
fi

# Create temporary file and save current rules (for backup incase of timeout)
OLD_RULES_PATH="$(mktemp)"
echo -e "\nSaving current rules to $OLD_RULES_PATH..."
iptables-save -f $OLD_RULES_PATH

# Apply new rules
echo -e "\nTrying to apply the new rules at $RULES_PATH..."
iptables-restore $RULES_PATH

# Make sure rules applied successfully (rolling back if not)
if [ $? -ne 0 ]; then
	echo -e "\nNew rules were not applied successfully.\nPlease ensure the rules can be successfully applied by using the command:\nsudo iptables-restore -tv $RULES_PATH"
	revert_rules $OLD_RULES_PATH
	cleanup $OLD_RULES_PATH
	exit 1
fi

# Get confirmation from user. 
echo "Test the new rules. Are you able to make a new connection? (Y/N)"
read -t $TIMEOUT -n 1 input  # Wait for input for TIMEOUT seconds, read 1 character only

# On timeout or an input of "N|n", restore the old rules
if [ $? -ne 0 ] || [[ "$input" == "N" || "$input" == "n" ]]; then
    echo -e "\n\nExiting. Either no input received within the timeout or 'No' was chosen."
	revert_rules $OLD_RULES_PATH
	cleanup $OLD_RULES_PATH
    exit 1
fi

# Otherwise, rules were successfully applied according to user!
cleanup $OLD_RULES_PATH
echo -e "\nRules successfully applied."

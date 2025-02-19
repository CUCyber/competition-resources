#!/bin/bash

# Credit goes to USF :)

# define directories to search (these are common directories used in competitions)
dirs=("/var/log" "/home" "/etc" "/tmp" "/opt" "/srv" "/mnt" "/media")

# define regex patterns to detect pii (personally identifiable information)
creditCardRegex='\b(?:\d{4}[-\s]?){3}\d{4,6}\b'  # detects credit card numbers
addressRegex='\b\d{1,5}\s[\w\s]+(?:St|Street|Ave|Avenue|Rd|Road|Blvd|Boulevard|Dr|Drive|Ln|Lane|Ct|Court|Way|Place|Pl|Pkwy|Parkway|Loop|Terrace|Square|Commons|Highway|Hwy)\b'  # detects common addresses
ssnRegex='\b(?!666|000|9\d{2})[0-9]{3}-(?!00)[0-9]{2}-(?!0000)[0-9]{4}\b'  # detects social security numbers while avoiding invalid ones
phoneNumberRegex='\b(?:\+?[0-9]{1,3}[-.\s]?)?(?!\b(?:4\d{3}|5[1-5]\d{2}|3[47]\d{2}|6011)\d{4,14}\b)(?!\d{3}-\d{2}-\d{4})(?:\(?[2-9][0-9]{2}\)?[-.\s]?)[0-9]{3}[-.\s]?[0-9]{4}\b'  # detects phone numbers
emailRegex='\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,10}\b'  # detects email addresses
dateRegex='\b(0[1-9]|1[0-2])[-\/.](0[1-9]|[12][0-9]|3[01])[-\/.]([12][0-9]{3})\b'  # detects dates in mm/dd/yyyy format

# function to search for pii inside a given file
searchFileForPII() {
    filePath="$1"  # store the file path
    matches=()  # initialize an empty array for matches
    
    [[ -r "$filePath" ]] || return  # skip unreadable files

    # search for pii types and store results in output
    output=""

    if grep -Pq "$creditCardRegex" "$filePath"; then
        output+="\033[1;33mcredit card numbers:\033[0m $(grep -Po "$creditCardRegex" "$filePath" | tr '\n' ', ') \n"
    fi

    if grep -Pq "$addressRegex" "$filePath"; then
        output+="\033[1;34maddresses:\033[0m $(grep -Po "$addressRegex" "$filePath" | tr '\n' ', ') \n"
    fi

    if grep -Pq "$ssnRegex" "$filePath"; then
        output+="\033[1;31msocial security numbers:\033[0m $(grep -Po "$ssnRegex" "$filePath" | tr '\n' ', ') \n"
    fi

    if grep -Pq "$phoneNumberRegex" "$filePath"; then
        output+="\033[1;32mphone numbers:\033[0m $(grep -Po "$phoneNumberRegex" "$filePath" | tr '\n' ', ') \n"
    fi

    if grep -Pq "$emailRegex" "$filePath"; then
        output+="\033[1;36memails:\033[0m $(grep -Po "$emailRegex" "$filePath" | tr '\n' ', ') \n"
    fi

    if grep -Pq "$dateRegex" "$filePath"; then
        output+="\033[1;35mdates:\033[0m $(grep -Po "$dateRegex" "$filePath" | tr '\n' ', ') \n"
    fi

    # print the results if pii was found
    if [[ -n "$output" ]]; then
        printf "\n------------------------\n"
        printf "🔍 scanned file: $filePath\n"
        printf "$output"
        printf "------------------------\n"
    fi
}

# export function and regex patterns for use in subshells
export -f searchFileForPII
export creditCardRegex addressRegex ssnRegex phoneNumberRegex emailRegex dateRegex

# recursively search for pii in the specified directories
for dir in "${dirs[@]}"; do
    find "$dir" -type f -size -50M -exec bash -c 'searchFileForPII "$0"' {} \; 2>/dev/null
done

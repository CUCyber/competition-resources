#!/usr/bin/env bash
# ccdc_scanner.sh
# Scans a subnet for live hosts, prints them, and runs port/service scans automatically.
# Usage: ./ccdc_scanner.sh [SUBNET] [CONCURRENCY]
# Example: sudo ./ccdc_scanner.sh 10.10.10.0/24 8

set -euo pipefail
IFS=$'\n\t'

SUBNET="${1:-10.10.10.0/24}"
CONCURRENCY="${2:-5}"         # number of hosts to scan in parallel
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTDIR="${OUTDIR:-ccdc_scans_${TIMESTAMP}}"
mkdir -p "$OUTDIR"

# Choose scan type depending on privileges
if [ "$(id -u)" -eq 0 ]; then
  SYN_OR_CONNECT="-sS"
  NOTE_SCAN="Using SYN scans (-sS). Running as root."
else
  SYN_OR_CONNECT="-sT"
  NOTE_SCAN="Using TCP connect scans (-sT). Not running as root."
fi

echo "CCDC auto-scanner starting at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
echo "Subnet: $SUBNET"
echo "Output directory: $OUTDIR"
echo "Concurrency: $CONCURRENCY"
echo "$NOTE_SCAN"
echo

# helper: semaphore for concurrency
running_jobs=0
wait_for_slot() {
  while [ "$running_jobs" -ge "$CONCURRENCY" ]; do
    # wait for any background job to finish
    wait -n || true
    # recount background jobs
    # (jobs -p may include terminated jobs until reap; use wait -n above)
    running_jobs=$(jobs -rp | wc -l)
  done
}

# Clean exit on ctrl-c
trap 'echo; echo "Interrupted. Waiting for background tasks to finish..."; wait; exit 1' INT

# 1) Ping sweep to find live hosts
echo "Running ping sweep (nmap -sn) on $SUBNET ..."
PING_GREP_OUT="$OUTDIR/ping_sweep.gnmap"
# produce greppable output so we can parse IPs
nmap -sn -n "$SUBNET" -oG - | tee "$PING_GREP_OUT" >/dev/null

# Extract IPs marked Up
LIVE_HOSTS=()
while read -r ip; do
  [[ -z "$ip" ]] && continue
  LIVE_HOSTS+=("$ip")
done < <(awk '/Status: Up/{print $2}' "$PING_GREP_OUT" | sort -u)

if [ "${#LIVE_HOSTS[@]}" -eq 0 ]; then
  echo "No live hosts found in $SUBNET."
  exit 0
fi

echo "Discovered live hosts:"
for ip in "${LIVE_HOSTS[@]}"; do
  echo " - $ip"
done
echo

# 2) Function to scan a single host
scan_host() {
  local ip="$1"
  local hostdir="$OUTDIR/$ip"
  mkdir -p "$hostdir"

  # 2a) Full port scan (all ports) - output both greppable and normal
  echo "[$ip] Starting full-port scan (-p-)..."
  local full_gnmap="$hostdir/${ip}_fullports.gnmap"
  local full_nmap="$hostdir/${ip}_fullports.txt"
  # Use -Pn to skip host discovery (we already know it's up)
  nmap $SYN_OR_CONNECT -T4 -p- -Pn -n "$ip" -oG "$full_gnmap" -oN "$full_nmap" >/dev/null 2>&1 || true
  echo "[$ip] Full-port scan finished: $full_nmap"

  # 2b) Parse open ports from greppable output
  # Greppable line example: Host: 10.10.10.5 () Ports: 22/open/tcp//ssh///,80/open/tcp//http/// ...
  local ports_list
  ports_list=$(grep -E "Ports: .*open" "$full_gnmap" || true)
  if [ -z "$ports_list" ]; then
    echo "[$ip] No open ports found in full-port scan."
    echo "[$ip] Saving full-port greppable output to $full_gnmap"
    return 0
  fi

  # Extract numeric ports that are marked 'open'
  local open_ports
  open_ports=$(grep -oP '\d+(?=/open)' "$full_gnmap" | sort -n | uniq | paste -sd, - || true)

  if [ -z "$open_ports" ]; then
    echo "[$ip] Could not parse open ports (unexpected format). See $full_gnmap"
    return 0
  fi

  echo "[$ip] Open ports: $open_ports"

  # 2c) Service/version scan for open ports
  echo "[$ip] Running service/version scan (-sV) on open ports..."
  local sv_out="$hostdir/${ip}_services.txt"
  nmap -T4 -sV -p "$open_ports" -Pn -n "$ip" -oN "$sv_out" >/dev/null 2>&1 || true
  echo "[$ip] Service/version scan saved to $sv_out"

  # 2d) Optional: Aggressive OS + scripts for common HTTP/SSH (use -A or -O)
  # We'll run -A only if common web or ssh ports exist (80,443,22) to speed things
  local extras="80,443,22"
  # check intersection
  local intersect
  intersect=$(echo "$open_ports" | tr ',' '\n' | grep -x -E '^(80|443|22)$' || true)
  if [ -n "$intersect" ]; then
    echo "[$ip] Found common service ports (80/443/22) — running -A scan on 80,443,22"
    local a_out="$hostdir/${ip}_aggressive.txt"
    nmap -A -T4 -p80,443,22 -Pn -n "$ip" -oN "$a_out" >/dev/null 2>&1 || true
    echo "[$ip] Aggressive scan saved to $a_out"
  fi

  # done
  echo "[$ip] Scans complete."
}

# 3) Kick off scans with concurrency
echo "Launching per-host scans (up to $CONCURRENCY parallel jobs)..."
for ip in "${LIVE_HOSTS[@]}"; do
  wait_for_slot
  scan_host "$ip" &
  # increment running job counter
  running_jobs=$(jobs -rp | wc -l)
done

# Wait for remaining background jobs
wait

echo
echo "All host scans complete. Results in: $OUTDIR"
echo "Summary (per-host):"
for ip in "${LIVE_HOSTS[@]}"; do
  echo " - $ip :"
  ls -1 "$OUTDIR/$ip" 2>/dev/null || echo "    (no files)"
done

echo "Done at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"

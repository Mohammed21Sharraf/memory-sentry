#!/usr/bin/env bash
# watch_memory.sh
# Background monitor. Prints alerts when thresholds are crossed.
#
# Start:  bash scripts/watch_memory.sh &
# Stop:   kill %1   (or kill <PID> printed at startup)
#
# Env vars (all optional):
#   MEMORY_SENTRY_INTERVAL=1800   seconds between checks (default 30 min)
#   MEMORY_SENTRY_MAX_AGE=28800   orphan age threshold in seconds (default 8h)
#   MEMORY_SENTRY_RSS_LIMIT=2048  Claude RSS alert threshold in MB (default 2 GB)

set -euo pipefail

INTERVAL=${MEMORY_SENTRY_INTERVAL:-1800}
MAX_AGE=${MEMORY_SENTRY_MAX_AGE:-28800}
RSS_LIMIT=${MEMORY_SENTRY_RSS_LIMIT:-2048}

BLD='\033[1m'
YLW='\033[1;33m'
RED='\033[0;31m'
RST='\033[0m'

echo -e "${BLD}memory-sentry watcher started${RST} — PID $$"
echo "  Checking every ${INTERVAL}s. Stop with: kill $$"
echo ""

etime_to_seconds() {
  local e="$1" s=0
  if [[ "$e" =~ ^([0-9]+)-([0-9]+):([0-9]+):([0-9]+)$ ]]; then
    s=$(( 10#${BASH_REMATCH[1]}*86400 + 10#${BASH_REMATCH[2]}*3600 \
        + 10#${BASH_REMATCH[3]}*60   + 10#${BASH_REMATCH[4]} ))
  elif [[ "$e" =~ ^([0-9]+):([0-9]+):([0-9]+)$ ]]; then
    s=$(( 10#${BASH_REMATCH[1]}*3600 + 10#${BASH_REMATCH[2]}*60 + 10#${BASH_REMATCH[3]} ))
  elif [[ "$e" =~ ^([0-9]+):([0-9]+)$ ]]; then
    s=$(( 10#${BASH_REMATCH[1]}*60 + 10#${BASH_REMATCH[2]} ))
  fi
  echo "$s"
}

while true; do
  ALERTS=()
  TS=$(date '+%H:%M:%S')

  # Check 1: kernel pressure
  P=$(sysctl -n vm.memory_pressure 2>/dev/null || echo "0")
  [[ "$P" == "2" ]] && ALERTS+=("${RED}[CRITICAL] Pressure level 2 — run full cleanup now!${RST}")
  [[ "$P" == "1" ]] && ALERTS+=("${YLW}[WARN] Pressure level 1 — run /compact + kill_orphans.sh${RST}")

  # Check 2: orphan helpers
  ORPHANS=0
  while IFS= read -r line; do
    ET=$(awk '{print $3}' <<< "$line")
    AGE=$(etime_to_seconds "$ET")
    (( AGE > MAX_AGE )) && ORPHANS=$(( ORPHANS + 1 )) || true
  done < <(ps axo pid=,rss=,etime=,comm= | grep -i "Code Helper" | grep -v grep || true)
  (( ORPHANS > 0 )) && \
    ALERTS+=("${YLW}[WARN] $ORPHANS orphan Code Helper(s) — run kill_orphans.sh${RST}")

  # Check 3: Claude RSS
  CLAUDE_KB=$(ps aux | grep -iE "(claude|@anthropic)" | grep -v grep \
              | awk '{s+=$6} END {print s+0}')
  CLAUDE_MB=$(( CLAUDE_KB / 1024 ))
  (( CLAUDE_MB > RSS_LIMIT )) && \
    ALERTS+=("${RED}[WARN] Claude RSS is ${CLAUDE_MB} MB — run /compact now!${RST}")

  # Print only if there are alerts
  if (( ${#ALERTS[@]} > 0 )); then
    echo ""
    echo -e "${BLD}[memory-sentry @ $TS]${RST}"
    for a in "${ALERTS[@]}"; do echo -e "  $a"; done
    echo ""
  fi

  sleep "$INTERVAL"
done
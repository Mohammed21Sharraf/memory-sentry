#!/usr/bin/env bash
# find_orphans.sh
# Lists VS Code Helper processes older than 8 hours.
# These held memory after their parent VS Code window closed.
# Prints: PID, RAM (MB), age (hours), process name, orphan flag.

set -euo pipefail

YLW='\033[1;33m'
RED='\033[0;31m'
BLD='\033[1m'
RST='\033[0m'

MAX_AGE=${MEMORY_SENTRY_MAX_AGE:-28800}   # 8 hours in seconds
MAX_H=$((MAX_AGE / 3600))

echo ""
echo -e "${BLD}Scanning for Code Helper orphans (older than ${MAX_H}h)...${RST}"
echo ""

# etime_to_seconds <etime>
# Converts ps etime output (DD-HH:MM:SS or HH:MM:SS or MM:SS) to seconds
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

FOUND=0

while IFS= read -r line; do
  PID=$(  awk '{print $1}' <<< "$line")
  RSS=$(  awk '{print $2}' <<< "$line")
  ETIME=$(awk '{print $3}' <<< "$line")

  AGE=$(etime_to_seconds "$ETIME")
  (( AGE <= MAX_AGE )) && continue

  # Is the parent gone? (PPID=1 means launchd adopted it)
  PARENT_PID=$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ' || echo "?")
  ORPHAN_FLAG=""
  [[ "$PARENT_PID" == "1" ]] && ORPHAN_FLAG="${RED} ← parent gone (launchd)${RST}"

  RSS_MB=$(echo "scale=1; $RSS/1024" | bc)
  AGE_H=$(( AGE / 3600 ))

  echo -e "  ${YLW}PID $PID${RST}  |  ${RSS_MB} MB  |  ${AGE_H}h old${ORPHAN_FLAG}"
  FOUND=$(( FOUND + 1 ))
done < <(ps axo pid=,rss=,etime=,comm= | grep -i "Code Helper" | grep -v grep || true)

echo ""
if [[ $FOUND -eq 0 ]]; then
  echo "  ✓ No orphans found. All Code Helpers are under ${MAX_H}h old."
else
  echo -e "  ${RED}Found $FOUND orphan(s).${RST}"
  echo "  → Kill them: bash scripts/kill_orphans.sh"
fi
echo ""
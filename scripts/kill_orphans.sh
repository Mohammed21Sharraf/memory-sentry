#!/usr/bin/env bash
# kill_orphans.sh
# Kills VS Code Helper processes older than MAX_AGE seconds.
# Uses SIGTERM first. If the process is still alive after 1s, uses SIGKILL.
# Set DRY_RUN=true to preview what would be killed without doing it.

set -euo pipefail

GRN='\033[0;32m'
RED='\033[0;31m'
YLW='\033[1;33m'
BLD='\033[1m'
RST='\033[0m'

MAX_AGE=${MEMORY_SENTRY_MAX_AGE:-28800}
DRY_RUN=${DRY_RUN:-false}

echo ""
echo -e "${BLD}Memory-Sentry — Orphan Cleanup${RST}"
[[ "$DRY_RUN" == "true" ]] && echo -e "${YLW}(DRY RUN — nothing will be killed)${RST}"
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
KILLED=0; FAILED=0; FREED_KB=0

while IFS= read -r line; do
  PID=$(  awk '{print $1}' <<< "$line")
  RSS=$(  awk '{print $2}' <<< "$line")
  ETIME=$(awk '{print $3}' <<< "$line")

  AGE=$(etime_to_seconds "$ETIME")
  (( AGE <= MAX_AGE )) && continue

  RSS_MB=$(echo "scale=1; $RSS/1024" | bc)
  AGE_H=$(( AGE / 3600 ))

  printf "  Terminating PID %-6s  (%s MB, %sh old) ... " "$PID" "$RSS_MB" "$AGE_H"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YLW}[dry run]${RST}"
    continue
  fi

  if kill -TERM "$PID" 2>/dev/null; then
    sleep 1
    if kill -0 "$PID" 2>/dev/null; then
      # Still alive — force kill
      if kill -9 "$PID" 2>/dev/null; then
        echo -e "${GRN}killed (SIGKILL)${RST}"
        KILLED=$(( KILLED + 1 )); FREED_KB=$(( FREED_KB + RSS ))
      else
        echo -e "${RED}failed${RST}"; FAILED=$(( FAILED + 1 ))
      fi
    else
      echo -e "${GRN}killed (SIGTERM)${RST}"
      KILLED=$(( KILLED + 1 )); FREED_KB=$(( FREED_KB + RSS ))
    fi
  else
    echo -e "${RED}failed (already gone or need sudo)${RST}"
    FAILED=$(( FAILED + 1 ))
  fi

done < <(ps axo pid=,rss=,etime=,comm= | grep -i "Code Helper" | grep -v grep || true)

echo ""
FREED_MB=$(echo "scale=1; $FREED_KB/1024" | bc)

if (( KILLED == 0 && FAILED == 0 )) && [[ "$DRY_RUN" != "true" ]]; then
  echo -e "  ${GRN}✓ Nothing to clean — no orphans found.${RST}"
fi
(( KILLED > 0 )) && echo -e "  ${GRN}✓ Killed $KILLED orphan(s), freed ~${FREED_MB} MB${RST}"
(( FAILED > 0 )) && echo -e "  ${RED}⚠ $FAILED process(es) failed (try with sudo)${RST}"

echo ""
echo "  Verify: bash scripts/check_pressure.sh"
echo ""
#!/usr/bin/env bash
# check_pressure.sh
# Full memory health report for macOS. No sudo needed.
# Reads: vm.memory_pressure, vm_stat pages, swap usage,
#        Claude Code RSS, VS Code Helper process count.

set -euo pipefail

RED='\033[0;31m'
YLW='\033[1;33m'
GRN='\033[0;32m'
BLD='\033[1m'
RST='\033[0m'

echo ""
echo -e "${BLD}╔══════════════════════════════════════════╗${RST}"
echo -e "${BLD}║       Memory-Sentry: Health Report       ║${RST}"
echo -e "${BLD}╚══════════════════════════════════════════╝${RST}"
echo ""

# ── 1. Kernel memory pressure ─────────────────────────────────────────────────
echo -e "${BLD}[1] Memory Pressure Level${RST}"
PRESSURE=$(sysctl -n vm.memory_pressure 2>/dev/null || echo "?")

case "$PRESSURE" in
  0) echo -e "    ${GRN}● Normal  (0)${RST} — RAM supply is healthy" ;;
  1) echo -e "    ${YLW}● Warning (1)${RST} — system under pressure"
     echo -e "    ${YLW}    → Run /compact in Claude Code, then kill_orphans.sh${RST}" ;;
  2) echo -e "    ${RED}● Critical (2)${RST} — heavy swap, system is stressed"
     echo -e "    ${RED}    → Run full sequence: /compact → kill_orphans.sh → sudo purge${RST}" ;;
  *) echo -e "    ⚠ Could not read pressure (got: $PRESSURE)" ;;
esac
echo ""

# ── 2. RAM pages via vm_stat ──────────────────────────────────────────────────
echo -e "${BLD}[2] RAM Pages${RST}"
PAGE_SIZE=$(pagesize 2>/dev/null || echo 4096)

vm_stat | awk -v ps="$PAGE_SIZE" '
  /Pages free/      { gsub(/\./, "", $3); free=$3 }
  /Pages inactive/  { gsub(/\./, "", $3); inactive=$3 }
  /Pages active/    { gsub(/\./, "", $3); active=$3 }
  /Pages wired/     { gsub(/\./, "", $4); wired=$4 }
  END {
    printf "    Free:      %6.0f MB\n",     (free     * ps) / 1048576
    printf "    Inactive:  %6.0f MB  (reclaimable)\n", (inactive * ps) / 1048576
    printf "    Active:    %6.0f MB\n",     (active   * ps) / 1048576
    printf "    Wired:     %6.0f MB  (locked by OS)\n", (wired    * ps) / 1048576
  }
'
echo ""

# ── 3. Swap ───────────────────────────────────────────────────────────────────
echo -e "${BLD}[3] Swap Usage${RST}"
SWAP_LINE=$(sysctl vm.swapusage 2>/dev/null || echo "")
if [[ -n "$SWAP_LINE" ]]; then
  SWAP_USED=$(echo "$SWAP_LINE" | sed 's/.*used = \([0-9.]*\).*/\1/')
  SWAP_UNIT=$(echo "$SWAP_LINE" | sed 's/.*used = [0-9.]*\([MG]\).*/\1/')
  if [[ "$SWAP_UNIT" == "G" ]]; then
    SWAP_MB=$(echo "$SWAP_USED * 1024" | bc | cut -d. -f1)
  else
    SWAP_MB=$(echo "$SWAP_USED" | cut -d. -f1)
  fi
  if   (( SWAP_MB < 512  )); then LABEL="✓ Low"
  elif (( SWAP_MB < 2048 )); then LABEL="⚠ Moderate"
  else                             LABEL="✗ HIGH — system is swapping heavily"
  fi
  echo "    Used: ${SWAP_MB} MB  ${LABEL}"
else
  echo "    (unavailable)"
fi
echo ""

# ── 4. Claude Code process RSS ────────────────────────────────────────────────
echo -e "${BLD}[4] Claude Code RSS${RST}"
PROCS=$(ps aux | grep -iE "(claude|@anthropic)" | grep -v grep || true)

if [[ -z "$PROCS" ]]; then
  echo "    (no Claude Code process found)"
else
  echo "$PROCS" | awk '
    {
      mb = $6/1024
      pid = $2
      n = split($11, p, "/"); name = p[n]
      status = (mb > 2048) ? "✗ HIGH" : (mb > 800) ? "⚠ Elevated" : "✓ OK"
      printf "    PID %-6s  %7.1f MB  %s  %s\n", pid, mb, status, name
    }
  '
fi
echo ""

# ── 5. VS Code Helper summary ─────────────────────────────────────────────────
echo -e "${BLD}[5] VS Code Helpers${RST}"
COUNT=$(ps aux | grep -i "Code Helper" | grep -v grep | wc -l | tr -d ' ')
TOTAL=$(ps aux | grep -i "Code Helper" | grep -v grep \
        | awk '{s+=$6} END {printf "%.0f", s/1024}')

if   [[ "$COUNT" -eq 0 ]];  then echo "    None running."
elif [[ "$COUNT" -gt 10 ]]; then
  echo -e "    ${RED}$COUNT helpers, ~${TOTAL} MB total${RST}"
  echo "    → Run: bash scripts/find_orphans.sh"
else
  echo -e "    ${YLW}$COUNT helpers, ~${TOTAL} MB total${RST}"
  echo "    → Run find_orphans.sh to check for stale ones"
fi
echo ""

echo -e "${BLD}Done.${RST}"
echo ""
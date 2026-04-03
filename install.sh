#!/usr/bin/env bash
# Makes all scripts executable after cloning.
set -e
chmod +x scripts/check_pressure.sh
chmod +x scripts/find_orphans.sh
chmod +x scripts/kill_orphans.sh
chmod +x scripts/watch_memory.sh
echo "✓ memory-sentry scripts are ready."
echo "  Start with: bash scripts/check_pressure.sh"

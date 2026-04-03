---
name: memory-sentry
description: >
  Memory monitor and cleanup utility for Claude Code on macOS. Use this
  skill whenever the user mentions high memory usage, RAM warnings like
  "High memory usage (11.3GB)", Claude Code feeling slow, VS Code Helper
  processes eating RAM, zombie or orphan processes, or asks about /compact,
  sudo purge, heapdump, or killing stale background processes. Also triggers
  for phrases like "my Mac is slow during Claude", "VS Code using too much
  memory", "how do I free up RAM", or "clean up Code Helper processes".
  Always use this skill before giving any manual memory commands — it
  provides structured, safe diagnosis first.
compatibility:
  os: macOS 12+
  requires: bash, sysctl, ps, pkill, vm_stat, bc
---

# Memory-Sentry

Diagnose and fix memory bloat in Claude Code sessions on macOS.
Covers: memory pressure reading, orphan VS Code Helper detection,
safe cleanup ordering, and optional background monitoring.

---

## Why This Skill Exists

Long Claude Code sessions accumulate heap. VS Code Helper child processes
(Renderer, GPU, Extension) keep running after their parent window closes —
they hold RAM but do nothing useful. Together they cause warnings like:

    High memory usage (11.3GB) · /heapdump

This skill gives Claude a structured, safe way to diagnose and fix that —
in the correct order — rather than jumping straight to destructive commands.

---

## Activation Checklist

Before running anything, confirm which situation you're in:

| Signal | Likely cause | Go to |
|---|---|---|
| `/heapdump` warning in Claude Code | Claude's own heap is too large | Step 1 → Step 3a |
| Activity Monitor shows many "Code Helper" entries | Orphan VS Code processes | Step 1 → Step 3b |
| Mac feels slow, fans spinning | System-wide pressure | Step 1 → full Step 3 sequence |
| Just want a status check | Routine health check | Step 1 only |

---

## Step 1 — Read System Memory Health

Run this first, always. It reads macOS-native signals without needing root.
```bash
bash scripts/check_pressure.sh
```

What it reports:
- `vm.memory_pressure` level — the kernel's own verdict (0/1/2)
- Free + inactive RAM pages from `vm_stat`
- Current swap usage
- Claude Code's own RSS (Resident Set Size)
- Count and total RAM of all VS Code Helper processes

**Interpreting pressure levels:**

| Level | Meaning | What to do |
|---|---|---|
| `0` | Normal | Nothing required |
| `1` | Warning | Run Step 3a (/compact) + Step 3b (kill orphans) |
| `2` | Critical | Run full sequence: 3a → 3b → 3c |

---

## Step 2 — Identify Orphan Helpers

Orphan helpers are VS Code child processes still running after their
parent session ended. Criteria: name matches `Code Helper*`, running
longer than 8 hours, parent PID is 1 (adopted by launchd).
```bash
bash scripts/find_orphans.sh
```

Output shows: PID, RSS in MB, age in hours, and whether the parent is gone.
If orphans are found, proceed to Step 3b.

---

## Step 3 — Cleanup (always in this order)

### 3a. Compact Claude's own context — always do this first

Type inside Claude Code:
```
/compact
```

This lets Claude summarize its conversation history and release heap.
Free, reversible, no system impact. Always do this before anything else.

### 3b. Kill orphan helpers — safe, targeted
```bash
bash scripts/kill_orphans.sh
```

Only kills processes matching the orphan criteria from Step 2.
Will NOT kill your active VS Code session. Uses SIGTERM first,
SIGKILL only if the process doesn't exit within 1 second.

### 3c. Flush inactive memory cache — requires sudo
```bash
sudo purge
```

Forces macOS to evict inactive pages from RAM. Expect a few seconds
of disk activity. Safe at any time — the OS refills the cache as needed.

### 3d. Nuclear option — only if VS Code is fully closed
```bash
pkill -9 "Code Helper"
```

⚠ This kills every Helper regardless of age. Only run this if you have
quit VS Code entirely first. Your open editor windows will be lost.

---

## Step 4 — Verify the Fix

After cleanup, re-run the health check to confirm improvement:
```bash
bash scripts/check_pressure.sh
```

Also spot-check Claude's specific process:
```bash
ps aux | grep -i "claude" | grep -v grep | awk '{print $6/1024 " MB\t" $11}'
```

---

## Optional: Background Monitor

To watch memory continuously while you work (checks every 30 minutes):
```bash
bash scripts/watch_memory.sh &
echo "Watcher PID: $!"
```

Alerts print to terminal when:
- Memory pressure exceeds level 0
- Any Code Helper exceeds 8 hours old
- Claude's RSS exceeds 2 GB

Stop the watcher:
```bash
kill %1        # if it's your only background job
# or
kill <PID>     # using the PID printed at startup
```

### Tuning the watcher via environment variables

| Variable | Default | What it controls |
|---|---|---|
| `MEMORY_SENTRY_INTERVAL` | `1800` | Seconds between checks |
| `MEMORY_SENTRY_MAX_AGE` | `28800` | Orphan age threshold (seconds) |
| `MEMORY_SENTRY_RSS_LIMIT` | `2048` | Claude RSS alert threshold (MB) |

Example — check every 10 minutes, alert if Claude exceeds 1.5 GB:
```bash
MEMORY_SENTRY_INTERVAL=600 MEMORY_SENTRY_RSS_LIMIT=1500 bash scripts/watch_memory.sh &
```

---

## Scripts Reference

| Script | Purpose | Needs sudo? |
|---|---|---|
| `scripts/check_pressure.sh` | Full system memory health report | No |
| `scripts/find_orphans.sh` | List stale VS Code Helper processes | No |
| `scripts/kill_orphans.sh` | Safely terminate orphan helpers | No (usually) |
| `scripts/watch_memory.sh` | Background monitor with threshold alerts | No |

---

## Prevention
The single most effective habit is closing VS Code windows you're not
actively using. Each open window spawns 4-6 Helper processes using
150-300 MB each. Three idle windows = ~1.5 GB of avoidable RAM usage.

## What NOT to do

- Don't run `pkill -9 "Code Helper"` while VS Code is open — you'll lose work
- Don't run `sudo purge` repeatedly in a loop — it's a one-shot flush, not a pump
- Don't skip `/compact` — it's free and always the right first move
- Don't ignore level `2` pressure — at that point the Mac is swapping and will feel broken
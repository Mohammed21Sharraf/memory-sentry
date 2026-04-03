# memory-sentry

> A Claude Code skill for proactive memory monitoring and cleanup on macOS.

## The Problem

Long Claude Code sessions accumulate heap. VS Code Helper processes
(Renderer, GPU, Extension) keep running after their parent window closes —
holding RAM but doing nothing useful. Together they cause warnings like:

    High memory usage (11.3GB) · /heapdump

This skill gives Claude structured, safe tooling to diagnose and fix that
in the correct order — rather than jumping straight to destructive commands.

---

## What It Does

- Reads macOS memory pressure using native kernel APIs (`sysctl`, `vm_stat`)
- Identifies stale VS Code Helper processes running longer than 8 hours
- Kills only orphan helpers — leaves your active session untouched
- Flushes inactive memory cache via `sudo purge`
- Optionally monitors memory in the background and alerts when thresholds are crossed

---

## Installation

### Via skills CLI
```bash
skills add Mohammed21Sharraf/memory-sentry
```

### Manual
```bash
git clone https://github.com/Mohammed21Sharraf/memory-sentry.git
cd memory-sentry
bash install.sh
```

---

## Usage

Once installed, Claude will automatically use this skill when you say:

- *"Claude is using too much memory"*
- *"My Mac is slow, help me clean up VS Code helpers"*
- *"Run a memory health check"*
- *"Kill orphan processes"*
- *"I see a heapdump warning in Claude Code"*

### Or run the scripts directly
```bash
# Full health report (always start here)
bash scripts/check_pressure.sh

# List orphan helpers
bash scripts/find_orphans.sh

# Kill orphan helpers
bash scripts/kill_orphans.sh

# Preview what would be killed without doing it
DRY_RUN=true bash scripts/kill_orphans.sh

# Background monitor (alerts every 30 min)
bash scripts/watch_memory.sh &
```

---

## Cleanup Order (important)

Always follow this sequence:

1. `/compact` inside Claude Code — free Claude's own heap first
2. `bash scripts/kill_orphans.sh` — remove stale helpers
3. `sudo purge` — flush inactive memory cache
4. `pkill -9 "Code Helper"` — only if VS Code is fully closed

---

## Configuration

Customize behaviour with environment variables:

| Variable | Default | Description |
|---|---|---|
| `MEMORY_SENTRY_INTERVAL` | `1800` | Seconds between watcher checks |
| `MEMORY_SENTRY_MAX_AGE` | `28800` | Orphan age threshold in seconds (8h) |
| `MEMORY_SENTRY_RSS_LIMIT` | `2048` | Claude RSS alert threshold in MB |

Example:
```bash
MEMORY_SENTRY_INTERVAL=600 MEMORY_SENTRY_RSS_LIMIT=1500 bash scripts/watch_memory.sh &
```

---

## Prevention

The single most effective habit is closing VS Code windows you are not
actively using. Each open window spawns 4-6 Helper processes using
150-300 MB each. Three idle windows = ~1.5 GB of avoidable RAM usage.

---

## Requirements

- macOS 12+
- bash, sysctl, ps, pkill, vm_stat, bc (all built into macOS)
- No external dependencies
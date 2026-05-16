#!/bin/bash

# Watchdog - Monitors system health and adds maintenance tasks
# Run periodically to detect issues and queue maintenance work

set -euo pipefail

WORKSPACE="/agent-workspace"
TASKS_FILE="$WORKSPACE/.claude/loop/tasks.md"
LOG_FILE="$WORKSPACE/.claude/loop/watchdog.log"
HEALTH_JSON="$WORKSPACE/.claude/loop/health.json"

log() {
  echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}

add_task() {
  local task="$1"
  local tasks_file="$TASKS_FILE"

  # Check if task already exists (avoid duplicates)
  if grep -qF "$task" "$tasks_file" 2>/dev/null; then
    log "Task already exists, skipping: $task"
    return 0
  fi

  # Ensure tasks file exists with proper structure
  if [ ! -f "$tasks_file" ]; then
    cat > "$tasks_file" <<'EOF'
# Task Queue

## Pending

## In Progress

## Completed
EOF
  fi

  # Add task after ## Pending
  local temp_file
  temp_file=$(mktemp)
  awk -v task="- [ ] $task" '
    /^## Pending/ {
      print
      print task
      next
    }
    { print }
  ' "$tasks_file" > "$temp_file"
  mv "$temp_file" "$tasks_file"

  log "Added maintenance task: $task"
}

log "Watchdog starting..."

# Check 1: Disk space
DISK_USAGE=$(df "$WORKSPACE" | awk 'NR==2 {gsub(/%/,""); print $5}')
if [ "$DISK_USAGE" -gt 90 ]; then
  add_task "URGENT: Disk usage at ${DISK_USAGE}% - clean up old files"
elif [ "$DISK_USAGE" -gt 80 ]; then
  add_task "Disk usage at ${DISK_USAGE}% - review and clean up files"
fi

# Check 2: Log file sizes (rotate if too large)
for logfile in "$WORKSPACE/.claude/loop/"*.log; do
  if [ -f "$logfile" ]; then
    SIZE=$(stat -f%z "$logfile" 2>/dev/null || stat --printf="%s" "$logfile" 2>/dev/null || echo "0")
    SIZE_MB=$((SIZE / 1024 / 1024))
    if [ "$SIZE_MB" -gt 10 ]; then
      LOGNAME=$(basename "$logfile")
      add_task "Rotate log file $LOGNAME (${SIZE_MB}MB) - archive or truncate"
    fi
  fi
done

# Check 3: Stale lock files (older than 1 hour)
LOCK_FILE="$WORKSPACE/.claude/loop/claude.lock"
if [ -f "$LOCK_FILE" ]; then
  LOCK_AGE=$(($(date +%s) - $(stat -f%m "$LOCK_FILE" 2>/dev/null || stat --printf="%Y" "$LOCK_FILE" 2>/dev/null)))
  if [ "$LOCK_AGE" -gt 3600 ]; then
    PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [ -n "$PID" ] && ! kill -0 "$PID" 2>/dev/null; then
      log "Removing stale lock file (process $PID not running)"
      rm -f "$LOCK_FILE"
      add_task "Review why previous claude instance died (stale lock found)"
    fi
  fi
fi

# Check 4: Health check results
if [ -f "$HEALTH_JSON" ]; then
  # Check if health check is old (hasn't run recently)
  HEALTH_AGE=$(($(date +%s) - $(stat -f%m "$HEALTH_JSON" 2>/dev/null || stat --printf="%Y" "$HEALTH_JSON" 2>/dev/null)))
  if [ "$HEALTH_AGE" -gt 1800 ]; then
    add_task "Run health check - last run ${HEALTH_AGE} seconds ago"
  fi

  # Check for issues in health output
  STATUS=$(jq -r '.status' "$HEALTH_JSON" 2>/dev/null || echo "unknown")
  if [ "$STATUS" = "degraded" ] || [ "$STATUS" = "critical" ]; then
    add_task "Address health issues - system status is $STATUS"
  fi
fi

# Check 5: Systemd service status
if systemctl is-active --quiet claude-agent.timer 2>/dev/null; then
  : # Timer is running, all good
else
  if systemctl list-unit-files | grep -q "claude-agent.timer"; then
    add_task "Restart claude-agent.timer - systemd timer is not active"
  fi
fi

# Check 6: Git status (uncommitted changes for too long)
cd "$WORKSPACE"
if [ -d ".git" ]; then
  CHANGES=$(git status --porcelain 2>/dev/null | wc -l)
  if [ "$CHANGES" -gt 20 ]; then
    add_task "Create git checkpoint - $CHANGES uncommitted changes"
  fi
fi

# Check 7: Memory file freshness
MEMORY_FILE="$WORKSPACE/.claude/loop/memory.md"
if [ -f "$MEMORY_FILE" ]; then
  MEMORY_AGE=$(($(date +%s) - $(stat -f%m "$MEMORY_FILE" 2>/dev/null || stat --printf="%Y" "$MEMORY_FILE" 2>/dev/null)))
  # If memory not updated in 24 hours
  if [ "$MEMORY_AGE" -gt 86400 ]; then
    add_task "Update memory.md - last update was over 24 hours ago"
  fi
fi

# Check 8: Inbox has unprocessed files
INBOX_DIR="$WORKSPACE/.claude/inbox"
if [ -d "$INBOX_DIR" ]; then
  INBOX_FILES=$(find "$INBOX_DIR" -type f \( -name "*.txt" -o -name "*.md" -o -name "*.goal" \) 2>/dev/null | wc -l)
  if [ "$INBOX_FILES" -gt 0 ]; then
    add_task "Process $INBOX_FILES file(s) in inbox"
  fi
fi

# Check 9: Old notifications that might need cleanup
NOTIF_DIR="$WORKSPACE/.claude/notifications"
if [ -d "$NOTIF_DIR" ]; then
  OLD_NOTIFS=$(find "$NOTIF_DIR" -type f -mtime +7 2>/dev/null | wc -l)
  if [ "$OLD_NOTIFS" -gt 10 ]; then
    add_task "Clean up old notifications - $OLD_NOTIFS files older than 7 days"
  fi
fi

log "Watchdog complete"

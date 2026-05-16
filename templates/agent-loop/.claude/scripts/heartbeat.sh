#!/bin/bash

# Heartbeat Daemon for Self-Sustaining Agent
# This script checks if tasks exist and starts claude if needed
# Run via cron: */5 * * * * /agent-workspace/.claude/scripts/heartbeat.sh

set -euo pipefail

WORKSPACE="/agent-workspace"
TASKS_FILE="$WORKSPACE/.claude/loop/tasks.md"
LOCK_FILE="$WORKSPACE/.claude/loop/claude.lock"
LOG_FILE="$WORKSPACE/.claude/loop/heartbeat.log"
PROMPT_FILE="$WORKSPACE/.claude/loop/prompt.md"

# Configuration
MAX_LOG_LINES=${MAX_LOG_LINES:-5000}         # Rotate log when it exceeds this
STARTUP_VERIFY_DELAY=${STARTUP_VERIFY_DELAY:-3}  # Seconds to wait before verifying startup

# Ensure directories exist
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}

# Cleanup function for unexpected exits
cleanup_on_error() {
  # Only remove lock if we created it and claude isn't running
  if [ -f "$LOCK_FILE" ]; then
    local lock_pid
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    # If the PID in lock is our PID (not claude's), remove it
    if [ "$lock_pid" = "$$" ]; then
      rm -f "$LOCK_FILE"
      log "Cleaned up lock file after error"
    fi
  fi
}
trap cleanup_on_error ERR

# Rotate log file if too large
if [ -f "$LOG_FILE" ]; then
  LINE_COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0")
  if [ "$LINE_COUNT" -gt "$MAX_LOG_LINES" ]; then
    tail -n $((MAX_LOG_LINES / 2)) "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
    log "Log file rotated (was $LINE_COUNT lines)"
  fi
fi

# Check if claude is already running
if [ -f "$LOCK_FILE" ]; then
  PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    log "Claude already running (PID $PID), skipping"
    exit 0
  else
    log "Stale lock file found, removing"
    rm -f "$LOCK_FILE"
  fi
fi

# Check resources first (may queue maintenance tasks)
RESOURCE_MONITOR="$WORKSPACE/.claude/scripts/resource-monitor.sh"
if [ -x "$RESOURCE_MONITOR" ]; then
  log "Checking resources..."
  "$RESOURCE_MONITOR" > /dev/null 2>&1 || log "Resource check detected issues"
fi

# Process email inbox (may add new tasks from emails)
EMAIL_INBOX="$WORKSPACE/.claude/scripts/email-inbox.sh"
if [ -x "$EMAIL_INBOX" ]; then
  log "Checking email inbox..."
  "$EMAIL_INBOX" check >> "$LOG_FILE" 2>&1 || log "Email inbox processing failed"
fi

# Check for help responses
HELP_CHECKER="$WORKSPACE/.claude/scripts/check-help-responses.sh"
if [ -x "$HELP_CHECKER" ]; then
  log "Checking help responses..."
  "$HELP_CHECKER" >> "$LOG_FILE" 2>&1 || log "Help response check failed"
fi

# Run watchdog to detect and queue maintenance tasks
WATCHDOG_SCRIPT="$WORKSPACE/.claude/scripts/watchdog.sh"
if [ -x "$WATCHDOG_SCRIPT" ]; then
  log "Running watchdog..."
  "$WATCHDOG_SCRIPT" >> "$LOG_FILE" 2>&1 || log "Watchdog failed"
fi

# Generate status dashboard
DASHBOARD_SCRIPT="$WORKSPACE/.claude/scripts/generate-dashboard.sh"
if [ -x "$DASHBOARD_SCRIPT" ]; then
  "$DASHBOARD_SCRIPT" > /dev/null 2>&1 || log "Dashboard generation failed"
fi

# Generate tasks from standing goals if queue is empty
TASK_GENERATOR="$WORKSPACE/.claude/scripts/generate-tasks.sh"
if [ -x "$TASK_GENERATOR" ]; then
  log "Running task generator..."
  "$TASK_GENERATOR" >> "$LOG_FILE" 2>&1 || log "Task generation failed"
fi

# Check if task file exists
if [ ! -f "$TASKS_FILE" ]; then
  log "No task file found, skipping"
  exit 0
fi

# Count pending and in-progress tasks
# Note: grep -c returns exit code 1 when count is 0, so we use || : pattern
PENDING=$(grep -c '^\- \[ \]' "$TASKS_FILE" 2>/dev/null) || :
PENDING=${PENDING:-0}
IN_PROGRESS=$(grep -c '^\- \[\.\]' "$TASKS_FILE" 2>/dev/null) || :
IN_PROGRESS=${IN_PROGRESS:-0}

if [ "$PENDING" -eq 0 ] && [ "$IN_PROGRESS" -eq 0 ]; then
  log "No pending tasks even after generation, skipping"
  exit 0
fi

log "Found $PENDING pending, $IN_PROGRESS in-progress tasks. Starting claude..."

# Create default prompt if not exists
if [ ! -f "$PROMPT_FILE" ]; then
  cat > "$PROMPT_FILE" <<'EOF'
You are waking up from the heartbeat daemon. Check your memory and task queue, then continue working.

Read /agent-workspace/.claude/loop/memory.md for context.
Read /agent-workspace/.claude/loop/tasks.md for your task queue.

Work through pending tasks. The stop hook will continue the loop while tasks remain.
EOF
fi

# Create lock file with our PID
echo $$ > "$LOCK_FILE"

# Start claude in the background, capturing output
cd "$WORKSPACE"
PROMPT=$(cat "$PROMPT_FILE")

# Run claude with the prompt
# Using --dangerously-skip-permissions since we're running autonomously
nohup claude --dangerously-skip-permissions -p "$PROMPT" >> "$WORKSPACE/.claude/loop/claude.log" 2>&1 &
CLAUDE_PID=$!

# Update lock file with actual claude PID
echo "$CLAUDE_PID" > "$LOCK_FILE"

log "Started claude with PID $CLAUDE_PID"

# Verify startup after a brief delay
sleep "$STARTUP_VERIFY_DELAY"
if kill -0 "$CLAUDE_PID" 2>/dev/null; then
  log "Verified claude is running (PID $CLAUDE_PID)"
else
  log "WARNING: Claude process $CLAUDE_PID not running after startup"
  rm -f "$LOCK_FILE"
  # Notify about startup failure
  NOTIFY_SCRIPT="$WORKSPACE/.claude/scripts/email-notify.sh"
  if [ -x "$NOTIFY_SCRIPT" ]; then
    "$NOTIFY_SCRIPT" "warning" "Claude failed to start - process exited immediately" 2>/dev/null || true
  fi
fi

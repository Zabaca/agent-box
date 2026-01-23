#!/bin/bash

# Health Check for Claude Autonomous Agent
# Returns 0 if healthy, non-zero if problems detected
# Outputs JSON health report

set -euo pipefail

WORKSPACE="/agent-workspace"
HEALTH_FILE="$WORKSPACE/.claude/health.json"
STATE_FILE="$WORKSPACE/.claude/loop/state.json"
TASKS_FILE="$WORKSPACE/.claude/loop/tasks.md"
MEMORY_FILE="$WORKSPACE/.claude/loop/memory.md"
HEARTBEAT_LOG="$WORKSPACE/.claude/loop/heartbeat.log"
LOCK_FILE="$WORKSPACE/.claude/loop/claude.lock"

ISSUES=()
WARNINGS=()

# Check required files exist
check_file() {
  local file="$1"
  local name="$2"
  if [ ! -f "$file" ]; then
    ISSUES+=("$name missing: $file")
    return 1
  fi
  return 0
}

# Check required directories
check_dir() {
  local dir="$1"
  local name="$2"
  if [ ! -d "$dir" ]; then
    ISSUES+=("$name missing: $dir")
    return 1
  fi
  return 0
}

# Run checks
check_file "$TASKS_FILE" "Task queue"
check_file "$MEMORY_FILE" "Memory file"
check_dir "$WORKSPACE/.claude/inbox" "Inbox directory"
check_dir "$WORKSPACE/.claude/scripts" "Scripts directory"

# Check if heartbeat has run recently (within last 10 minutes)
if [ -f "$HEARTBEAT_LOG" ]; then
  LAST_HEARTBEAT=$(stat -c %Y "$HEARTBEAT_LOG" 2>/dev/null || echo "0")
  NOW=$(date +%s)
  AGE=$((NOW - LAST_HEARTBEAT))
  if [ "$AGE" -gt 600 ]; then
    WARNINGS+=("Heartbeat log not updated in ${AGE}s (>10min)")
  fi
else
  WARNINGS+=("No heartbeat log found")
fi

# Check if state file exists and is recent
if [ -f "$STATE_FILE" ]; then
  ITERATION=$(jq -r '.iteration // 0' "$STATE_FILE" 2>/dev/null || echo "0")
  LAST_UPDATE=$(jq -r '.updated_at // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
else
  ITERATION=0
  LAST_UPDATE="never"
  WARNINGS+=("No state file found")
fi

# Check if claude is currently running
RUNNING="false"
if [ -f "$LOCK_FILE" ]; then
  PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    RUNNING="true"
  fi
fi

# Count tasks
PENDING=$(grep -c '^\- \[ \]' "$TASKS_FILE" 2>/dev/null || true)
PENDING=${PENDING:-0}
[ -z "$PENDING" ] && PENDING=0
IN_PROGRESS=$(grep -c '^\- \[\.\]' "$TASKS_FILE" 2>/dev/null || true)
IN_PROGRESS=${IN_PROGRESS:-0}
[ -z "$IN_PROGRESS" ] && IN_PROGRESS=0
COMPLETED=$(grep -c '^\- \[x\]' "$TASKS_FILE" 2>/dev/null || true)
COMPLETED=${COMPLETED:-0}
[ -z "$COMPLETED" ] && COMPLETED=0

# Determine overall health
if [ ${#ISSUES[@]} -gt 0 ]; then
  STATUS="unhealthy"
  EXIT_CODE=1
elif [ ${#WARNINGS[@]} -gt 0 ]; then
  STATUS="degraded"
  EXIT_CODE=0
else
  STATUS="healthy"
  EXIT_CODE=0
fi

# Build JSON report
ISSUES_JSON=$(printf '%s\n' "${ISSUES[@]:-}" | jq -R . | jq -s .)
WARNINGS_JSON=$(printf '%s\n' "${WARNINGS[@]:-}" | jq -R . | jq -s .)

REPORT=$(jq -n \
  --arg status "$STATUS" \
  --arg running "$RUNNING" \
  --argjson iteration "$ITERATION" \
  --arg last_update "$LAST_UPDATE" \
  --argjson pending "$PENDING" \
  --argjson in_progress "$IN_PROGRESS" \
  --argjson completed "$COMPLETED" \
  --argjson issues "$ISSUES_JSON" \
  --argjson warnings "$WARNINGS_JSON" \
  --arg checked_at "$(date -Iseconds)" \
  '{
    status: $status,
    checked_at: $checked_at,
    agent: {
      running: ($running == "true"),
      iteration: $iteration,
      last_update: $last_update
    },
    tasks: {
      pending: $pending,
      in_progress: $in_progress,
      completed: $completed
    },
    issues: $issues,
    warnings: $warnings
  }')

# Output and save report
echo "$REPORT" | tee "$HEALTH_FILE"

exit $EXIT_CODE

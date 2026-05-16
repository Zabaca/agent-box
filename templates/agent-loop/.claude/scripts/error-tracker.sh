#!/bin/bash

# Error Tracker with Backoff
# Tracks task failures and implements exponential backoff

set -euo pipefail

WORKSPACE="/agent-workspace"
ERROR_FILE="$WORKSPACE/.claude/loop/error-state.json"
LOG_FILE="$WORKSPACE/.claude/loop/error-tracker.log"
NOTIFY_SCRIPT="$WORKSPACE/.claude/scripts/email-notify.sh"

log() {
  echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}

notify() {
  if [ -x "$NOTIFY_SCRIPT" ]; then
    "$NOTIFY_SCRIPT" "$1" "$2" "$3" 2>/dev/null || true
  fi
}

# Ensure error state file exists
ensure_state() {
  if [ ! -f "$ERROR_FILE" ]; then
    echo '{"tasks":{}}' > "$ERROR_FILE"
  fi
}

# Get task error count
get_error_count() {
  local task_hash="$1"
  ensure_state
  jq -r --arg h "$task_hash" '.tasks[$h].count // 0' "$ERROR_FILE"
}

# Get backoff time in seconds
get_backoff_time() {
  local count="$1"
  # Exponential backoff: 60, 120, 240, 480, 960, ... max 3600 (1 hour)
  local backoff=$((60 * (2 ** (count - 1))))
  if [ "$backoff" -gt 3600 ]; then
    backoff=3600
  fi
  echo "$backoff"
}

# Check if task should be retried
should_retry() {
  local task_hash="$1"
  ensure_state
  
  local last_attempt=$(jq -r --arg h "$task_hash" '.tasks[$h].last_attempt // 0' "$ERROR_FILE")
  local count=$(jq -r --arg h "$task_hash" '.tasks[$h].count // 0' "$ERROR_FILE")
  
  if [ "$count" -eq 0 ]; then
    echo "yes"
    return
  fi
  
  local backoff=$(get_backoff_time "$count")
  local now=$(date +%s)
  local next_attempt=$((last_attempt + backoff))
  
  if [ "$now" -ge "$next_attempt" ]; then
    echo "yes"
  else
    local wait_time=$((next_attempt - now))
    echo "no:$wait_time"
  fi
}

# Record a task failure
record_failure() {
  local task_desc="$1"
  local error_msg="${2:-Unknown error}"
  local task_hash=$(echo "$task_desc" | md5sum | cut -d' ' -f1)
  
  ensure_state
  
  local count=$(get_error_count "$task_hash")
  count=$((count + 1))
  local now=$(date +%s)
  
  # Update error state
  jq --arg h "$task_hash" \
     --arg desc "$task_desc" \
     --arg err "$error_msg" \
     --argjson count "$count" \
     --argjson time "$now" \
     '.tasks[$h] = {description: $desc, error: $err, count: $count, last_attempt: $time}' \
     "$ERROR_FILE" > "$ERROR_FILE.tmp"
  mv "$ERROR_FILE.tmp" "$ERROR_FILE"
  
  log "Recorded failure #$count for task: $task_desc"
  
  # Determine action based on failure count
  if [ "$count" -ge 5 ]; then
    log "CRITICAL: Task has failed $count times, marking as blocked"
    notify "error" "Task blocked after $count failures" "$task_desc: $error_msg"
    echo "blocked"
  elif [ "$count" -ge 3 ]; then
    local backoff=$(get_backoff_time "$count")
    log "WARNING: Task has failed $count times, backoff: ${backoff}s"
    notify "warning" "Task failing repeatedly ($count times)" "$task_desc"
    echo "backoff:$backoff"
  else
    local backoff=$(get_backoff_time "$count")
    log "Task failed, will retry in ${backoff}s"
    echo "retry:$backoff"
  fi
}

# Record a task success (clears error state)
record_success() {
  local task_desc="$1"
  local task_hash=$(echo "$task_desc" | md5sum | cut -d' ' -f1)
  
  ensure_state
  
  # Check if task had previous failures
  local prev_count=$(get_error_count "$task_hash")
  if [ "$prev_count" -gt 0 ]; then
    log "Task recovered after $prev_count previous failures: $task_desc"
    notify "success" "Task recovered" "After $prev_count failures: $task_desc"
  fi
  
  # Remove from error state
  jq --arg h "$task_hash" 'del(.tasks[$h])' "$ERROR_FILE" > "$ERROR_FILE.tmp"
  mv "$ERROR_FILE.tmp" "$ERROR_FILE"
  
  echo "cleared"
}

# Get status of all tracked errors
get_status() {
  ensure_state
  
  echo "Error Tracker Status"
  echo "===================="
  
  local task_count=$(jq '.tasks | length' "$ERROR_FILE")
  if [ "$task_count" -eq 0 ]; then
    echo "No tracked errors."
    return
  fi
  
  echo "Tracked errors: $task_count"
  echo ""
  
  jq -r '.tasks | to_entries[] | "- \(.value.description)\n  Failures: \(.value.count), Last: \(.value.last_attempt | strftime("%Y-%m-%d %H:%M:%S"))\n  Error: \(.value.error)"' "$ERROR_FILE" 2>/dev/null || echo "(parse error)"
}

# Clean up old error records (older than 24 hours with 0 recent failures)
clean_old_errors() {
  ensure_state
  
  local cutoff=$(($(date +%s) - 86400))
  
  jq --argjson cutoff "$cutoff" \
     '.tasks |= with_entries(select(.value.last_attempt > $cutoff or .value.count >= 3))' \
     "$ERROR_FILE" > "$ERROR_FILE.tmp"
  mv "$ERROR_FILE.tmp" "$ERROR_FILE"
  
  log "Cleaned up old error records"
}

# Main command handler
case "${1:-status}" in
  failure|fail)
    if [ -z "${2:-}" ]; then
      echo "Usage: error-tracker.sh failure <task_description> [error_message]"
      exit 1
    fi
    record_failure "$2" "${3:-}"
    ;;
  success|ok)
    if [ -z "${2:-}" ]; then
      echo "Usage: error-tracker.sh success <task_description>"
      exit 1
    fi
    record_success "$2"
    ;;
  check)
    if [ -z "${2:-}" ]; then
      echo "Usage: error-tracker.sh check <task_description>"
      exit 1
    fi
    task_hash=$(echo "$2" | md5sum | cut -d' ' -f1)
    should_retry "$task_hash"
    ;;
  count)
    if [ -z "${2:-}" ]; then
      echo "Usage: error-tracker.sh count <task_description>"
      exit 1
    fi
    task_hash=$(echo "$2" | md5sum | cut -d' ' -f1)
    get_error_count "$task_hash"
    ;;
  status)
    get_status
    ;;
  clean)
    clean_old_errors
    ;;
  *)
    echo "Error Tracker - Track task failures with exponential backoff"
    echo ""
    echo "Usage: error-tracker.sh <command> [args]"
    echo ""
    echo "Commands:"
    echo "  failure <task> [error]  - Record a task failure"
    echo "  success <task>          - Record task success (clears errors)"
    echo "  check <task>            - Check if task should be retried"
    echo "  count <task>            - Get failure count for task"
    echo "  status                  - Show all tracked errors"
    echo "  clean                   - Remove old error records"
    ;;
esac

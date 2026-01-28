#!/bin/bash

# Safe Execution Wrapper
# Wraps command execution with error handling, logging, and recovery
#
# Usage: safe-exec.sh [options] -- command [args...]
#
# Features:
# - Pre-execution state snapshot (optional)
# - Error logging with context
# - Automatic retry with backoff
# - Post-failure notifications
# - Creates recovery task if all retries fail

set -euo pipefail

WORKSPACE="/agent-workspace"
ERROR_LOG="$WORKSPACE/.claude/loop/errors.log"
TASKS_FILE="$WORKSPACE/.claude/loop/tasks.md"
NOTIFY_SCRIPT="$WORKSPACE/.claude/scripts/email-notify.sh"
RETRY_SCRIPT="$WORKSPACE/.claude/scripts/retry.sh"
SNAPSHOT_SCRIPT="$WORKSPACE/.claude/scripts/snapshot.sh"

# Options
MAX_RETRIES=3
SNAPSHOT_BEFORE=false
TASK_NAME=""
NOTIFY_ON_FAILURE=true

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--retries)
      MAX_RETRIES="$2"
      shift 2
      ;;
    -s|--snapshot)
      SNAPSHOT_BEFORE=true
      shift
      ;;
    -t|--task)
      TASK_NAME="$2"
      shift 2
      ;;
    -q|--quiet)
      NOTIFY_ON_FAILURE=false
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [ $# -eq 0 ]; then
  cat <<EOF
Usage: safe-exec.sh [options] -- command [args...]

Options:
  -r, --retries N     Maximum retry attempts (default: 3)
  -s, --snapshot      Create snapshot before execution
  -t, --task NAME     Task name for logging and recovery
  -q, --quiet         Don't send failure notifications

Examples:
  safe-exec.sh -- npm install
  safe-exec.sh -s -t "database migration" -- ./migrate.sh
  safe-exec.sh -r 5 -- curl https://api.example.com
EOF
  exit 1
fi

COMMAND=("$@")
[ -z "$TASK_NAME" ] && TASK_NAME="${COMMAND[0]}"

log_error() {
  local msg="$1"
  echo "[$(date -Iseconds)] [ERROR] $msg" >> "$ERROR_LOG"
}

notify() {
  local type="$1"
  local msg="$2"
  [ "$NOTIFY_ON_FAILURE" = true ] && [ -x "$NOTIFY_SCRIPT" ] && "$NOTIFY_SCRIPT" "$type" "$msg" 2>/dev/null || true
}

add_recovery_task() {
  local task="$1"
  if [ -f "$TASKS_FILE" ]; then
    # Check if task already exists
    if ! grep -qF "$task" "$TASKS_FILE" 2>/dev/null; then
      TEMP_FILE=$(mktemp)
      awk -v task="- [ ] $task" '
        /^## Pending/ {
          print
          print task
          next
        }
        { print }
      ' "$TASKS_FILE" > "$TEMP_FILE"
      mv "$TEMP_FILE" "$TASKS_FILE"
    fi
  fi
}

# Create pre-execution snapshot if requested
if [ "$SNAPSHOT_BEFORE" = true ] && [ -x "$SNAPSHOT_SCRIPT" ]; then
  "$SNAPSHOT_SCRIPT" create "before-${TASK_NAME// /-}" >/dev/null 2>&1 || true
fi

# Execute with retries
set +e
if [ -x "$RETRY_SCRIPT" ]; then
  OUTPUT=$("$RETRY_SCRIPT" -n "$MAX_RETRIES" -l "$ERROR_LOG" -- "${COMMAND[@]}" 2>&1)
  EXIT_CODE=$?
else
  OUTPUT=$("${COMMAND[@]}" 2>&1)
  EXIT_CODE=$?
fi
set -e

if [ $EXIT_CODE -eq 0 ]; then
  # Success
  echo "$OUTPUT"
  exit 0
fi

# Failure handling
log_error "Task '$TASK_NAME' failed after $MAX_RETRIES attempts"
log_error "Command: ${COMMAND[*]}"
log_error "Output: $OUTPUT"

notify "error" "Task failed: $TASK_NAME"

# Create recovery task
RECOVERY_TASK="RECOVER: Investigate and fix '$TASK_NAME' failure - check errors.log"
add_recovery_task "$RECOVERY_TASK"

echo "ERROR: $TASK_NAME failed" >&2
echo "$OUTPUT" >&2
exit $EXIT_CODE

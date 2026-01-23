#!/bin/bash

# Check Help Responses
# Processes responses to help requests and creates tasks from them

set -euo pipefail

WORKSPACE="/agent-workspace"
HELP_DIR="$WORKSPACE/.claude/help-requests"
TASKS_FILE="$WORKSPACE/.claude/loop/tasks.md"
LOG_FILE="$WORKSPACE/.claude/loop/help.log"

[ -d "$HELP_DIR" ] || exit 0

log() {
  echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}

# Check each pending request for responses
for request_file in "$HELP_DIR"/help-*.md; do
  [ -f "$request_file" ] || continue

  REQUEST_ID=$(basename "$request_file" .md)

  # Check if status is still pending
  if ! grep -q "^\\*\\*Status:\\*\\* pending" "$request_file" 2>/dev/null; then
    continue
  fi

  # Look for response in the file (below the --- line)
  RESPONSE=$(awk '/^---$/{found=1; next} found{print}' "$request_file" | grep -v '^$' | head -20)

  # Also check for .response file
  RESPONSE_FILE="$HELP_DIR/${REQUEST_ID}.response"
  if [ -f "$RESPONSE_FILE" ]; then
    RESPONSE=$(cat "$RESPONSE_FILE")
  fi

  if [ -n "$RESPONSE" ] && [ "$RESPONSE" != "(User: Please add your response below this line)" ]; then
    log "Found response for $REQUEST_ID"

    # Mark as resolved
    sed -i 's/^\*\*Status:\*\* pending/\*\*Status:\*\* resolved/' "$request_file"

    # Add the response as a new task
    TASK_DESCRIPTION="Process help response: $RESPONSE"

    # Add to tasks if not already there
    if [ -f "$TASKS_FILE" ] && ! grep -qF "$TASK_DESCRIPTION" "$TASKS_FILE" 2>/dev/null; then
      TEMP_FILE=$(mktemp)
      awk -v task="- [ ] $TASK_DESCRIPTION" '
        /^## Pending/ {
          print
          print task
          next
        }
        { print }
      ' "$TASKS_FILE" > "$TEMP_FILE"
      mv "$TEMP_FILE" "$TASKS_FILE"
      log "Added task from help response: $TASK_DESCRIPTION"
    fi

    # Move to resolved directory
    mkdir -p "$HELP_DIR/resolved"
    mv "$request_file" "$HELP_DIR/resolved/" 2>/dev/null || true
    [ -f "$RESPONSE_FILE" ] && mv "$RESPONSE_FILE" "$HELP_DIR/resolved/" 2>/dev/null || true

    echo "Processed response for $REQUEST_ID"
  fi
done

# Report pending requests
PENDING_COUNT=$(find "$HELP_DIR" -maxdepth 1 -name "help-*.md" 2>/dev/null | wc -l)
if [ "$PENDING_COUNT" -gt 0 ]; then
  echo "$PENDING_COUNT help request(s) pending"
fi

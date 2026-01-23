#!/bin/bash

# Ask For Help System
# Creates a help request when the agent is genuinely stuck
# The agent continues working on other tasks while waiting for response
#
# Usage: ask-for-help.sh "question" [priority]
# Priority: low, medium, high, critical

set -euo pipefail

WORKSPACE="/agent-workspace"
HELP_DIR="$WORKSPACE/.claude/help-requests"
NOTIFY_SCRIPT="$WORKSPACE/.claude/scripts/email-notify.sh"
WEBHOOK_SCRIPT="$WORKSPACE/.claude/scripts/webhook-notify.sh"
LOG_FILE="$WORKSPACE/.claude/loop/help.log"

mkdir -p "$HELP_DIR"

QUESTION="${1:-}"
PRIORITY="${2:-medium}"

if [ -z "$QUESTION" ]; then
  echo "Usage: ask-for-help.sh \"question\" [priority]"
  echo "Priority: low, medium, high, critical"
  exit 1
fi

log() {
  echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REQUEST_ID="help-${TIMESTAMP}"
REQUEST_FILE="$HELP_DIR/${REQUEST_ID}.md"

# Create help request file
cat > "$REQUEST_FILE" <<EOF
# Help Request: ${REQUEST_ID}

**Priority:** ${PRIORITY}
**Created:** $(date -Iseconds)
**Status:** pending

## Question

${QUESTION}

## Context

$(cat "$WORKSPACE/.claude/loop/tasks.md" 2>/dev/null | grep -A5 "## In Progress" || echo "No tasks in progress")

## Response

(User: Please add your response below this line)

---

EOF

log "Created help request: $REQUEST_ID ($PRIORITY)"
log "Question: $QUESTION"

# Send notifications
if [ -x "$NOTIFY_SCRIPT" ]; then
  "$NOTIFY_SCRIPT" "$PRIORITY" "Help needed: $QUESTION" 2>/dev/null || true
fi

# Try webhook for high/critical priority
if [ "$PRIORITY" = "high" ] || [ "$PRIORITY" = "critical" ]; then
  if [ -x "$WEBHOOK_SCRIPT" ]; then
    "$WEBHOOK_SCRIPT" "$PRIORITY" "Agent needs help: $QUESTION" 2>/dev/null || true
  fi
fi

echo "Help request created: $REQUEST_FILE"
echo "Request ID: $REQUEST_ID"
echo ""
echo "The user can respond by editing this file or placing a response in:"
echo "  $HELP_DIR/${REQUEST_ID}.response"

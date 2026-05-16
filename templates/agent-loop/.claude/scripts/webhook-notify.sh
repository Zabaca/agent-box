#!/bin/bash
#
# Webhook Notification Script
# Sends notifications to configured webhook endpoints
#
# Usage: webhook-notify.sh <type> <message> [title]
# Types: info, success, warning, error, stuck
#
# Configure endpoints in: /agent-workspace/.claude/config/webhooks.json

set -euo pipefail

WORKSPACE="/agent-workspace"
CONFIG_FILE="$WORKSPACE/.claude/config/webhooks.json"
LOG_FILE="$WORKSPACE/.claude/loop/webhook.log"

log() {
  echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}

TYPE="${1:-info}"
MESSAGE="${2:-No message provided}"
TITLE="${3:-Claude Agent}"

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
  log "No webhook config found at $CONFIG_FILE"
  exit 0
fi

# Check if webhooks are enabled
ENABLED=$(jq -r '.enabled // false' "$CONFIG_FILE" 2>/dev/null)
if [ "$ENABLED" != "true" ]; then
  log "Webhooks disabled in config"
  exit 0
fi

# Get settings
TIMEOUT=$(jq -r '.settings.timeout_seconds // 5' "$CONFIG_FILE")
RETRY_COUNT=$(jq -r '.settings.retry_count // 2' "$CONFIG_FILE")
ONLY_CRITICAL=$(jq -r '.settings.only_critical // false' "$CONFIG_FILE")

# If only_critical is true, skip non-critical notifications
if [ "$ONLY_CRITICAL" = "true" ]; then
  if [ "$TYPE" != "error" ] && [ "$TYPE" != "stuck" ]; then
    log "Skipping non-critical notification (type: $TYPE)"
    exit 0
  fi
fi

# Map type to color for different formats
case "$TYPE" in
  success) COLOR="good"; DISCORD_COLOR=3066993; EMOJI="✅" ;;
  warning) COLOR="warning"; DISCORD_COLOR=16776960; EMOJI="⚠️" ;;
  error)   COLOR="danger"; DISCORD_COLOR=15158332; EMOJI="❌" ;;
  stuck)   COLOR="danger"; DISCORD_COLOR=10038562; EMOJI="🆘" ;;
  *)       COLOR="#439FE0"; DISCORD_COLOR=4359668; EMOJI="ℹ️" ;;
esac

TIMESTAMP=$(date -Iseconds)
HOSTNAME=$(hostname)

# Format payload for different services
format_slack() {
  cat <<EOF
{
  "attachments": [
    {
      "color": "$COLOR",
      "title": "$TITLE",
      "text": "$EMOJI $MESSAGE",
      "footer": "Claude Agent on $HOSTNAME",
      "ts": $(date +%s)
    }
  ]
}
EOF
}

format_discord() {
  cat <<EOF
{
  "embeds": [
    {
      "title": "$TITLE",
      "description": "$EMOJI $MESSAGE",
      "color": $DISCORD_COLOR,
      "timestamp": "$TIMESTAMP",
      "footer": {
        "text": "Claude Agent on $HOSTNAME"
      }
    }
  ]
}
EOF
}

format_generic() {
  cat <<EOF
{
  "type": "$TYPE",
  "title": "$TITLE",
  "message": "$MESSAGE",
  "timestamp": "$TIMESTAMP",
  "hostname": "$HOSTNAME",
  "source": "claude-agent"
}
EOF
}

# Send to each configured endpoint
ENDPOINTS=$(jq -c '.endpoints[]?' "$CONFIG_FILE" 2>/dev/null || echo "")

if [ -z "$ENDPOINTS" ]; then
  log "No webhook endpoints configured"
  exit 0
fi

SENT_COUNT=0

while IFS= read -r endpoint; do
  [ -z "$endpoint" ] && continue

  NAME=$(echo "$endpoint" | jq -r '.name // "unnamed"')
  URL=$(echo "$endpoint" | jq -r '.url // ""')
  FORMAT=$(echo "$endpoint" | jq -r '.format // "generic"')
  ENDPOINT_ENABLED=$(echo "$endpoint" | jq -r '.enabled // true')

  if [ "$ENDPOINT_ENABLED" != "true" ]; then
    log "Endpoint $NAME is disabled, skipping"
    continue
  fi

  if [ -z "$URL" ] || [ "$URL" = "null" ]; then
    log "Endpoint $NAME has no URL, skipping"
    continue
  fi

  # Skip example URLs
  if echo "$URL" | grep -qE '(YOUR|WEBHOOK|example\.com)'; then
    log "Endpoint $NAME has placeholder URL, skipping"
    continue
  fi

  # Format payload based on endpoint type
  case "$FORMAT" in
    slack)   PAYLOAD=$(format_slack) ;;
    discord) PAYLOAD=$(format_discord) ;;
    *)       PAYLOAD=$(format_generic) ;;
  esac

  # Send with retry
  SUCCESS=false
  for attempt in $(seq 1 "$RETRY_COUNT"); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
         -X POST "$URL" \
         -H "Content-Type: application/json" \
         -d "$PAYLOAD" \
         --max-time "$TIMEOUT" 2>/dev/null) || HTTP_CODE="000"

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "201" ]; then
      SUCCESS=true
      log "Sent notification to $NAME (HTTP $HTTP_CODE, attempt $attempt)"
      SENT_COUNT=$((SENT_COUNT + 1))
      break
    else
      log "Failed to send to $NAME (HTTP $HTTP_CODE, attempt $attempt/$RETRY_COUNT)"
      [ "$attempt" -lt "$RETRY_COUNT" ] && sleep 1
    fi
  done

  if [ "$SUCCESS" != "true" ]; then
    log "ERROR: All attempts to send to $NAME failed"
  fi

done <<< "$ENDPOINTS"

if [ "$SENT_COUNT" -gt 0 ]; then
  log "Webhook notification complete: $TYPE - ${MESSAGE:0:50}... (sent to $SENT_COUNT endpoints)"
else
  log "No webhooks sent (no valid endpoints configured)"
fi

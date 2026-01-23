#!/bin/bash

# Resource Monitor
# Monitors system resources and alerts/queues tasks when thresholds exceeded

set -euo pipefail

WORKSPACE="/agent-workspace"
TASKS_FILE="$WORKSPACE/.claude/loop/tasks.md"
ALERT_FILE="$WORKSPACE/.claude/ALERT"
LOG_FILE="$WORKSPACE/.claude/loop/resource-monitor.log"
STATE_FILE="$WORKSPACE/.claude/loop/resource-state.json"

log() {
  echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}

# Thresholds
DISK_WARNING=80
DISK_CRITICAL=95
MEM_WARNING=80
MEM_CRITICAL=95
LOAD_WARNING=4
LOAD_CRITICAL=8

# Get current metrics
DISK_PERCENT=$(df "$WORKSPACE" | awk 'NR==2 {gsub(/%/,""); print $5}')
MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/^Mem:/ {print $3}')
MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))
LOAD_AVG=$(cat /proc/loadavg | awk '{print $1}')
LOAD_INT=${LOAD_AVG%.*}

# Check for alerts
ALERTS=""
WARNINGS=""

# Disk check
if [ "$DISK_PERCENT" -ge "$DISK_CRITICAL" ]; then
  ALERTS="${ALERTS}CRITICAL: Disk at ${DISK_PERCENT}%\n"
elif [ "$DISK_PERCENT" -ge "$DISK_WARNING" ]; then
  WARNINGS="${WARNINGS}WARNING: Disk at ${DISK_PERCENT}%\n"
fi

# Memory check
if [ "$MEM_PERCENT" -ge "$MEM_CRITICAL" ]; then
  ALERTS="${ALERTS}CRITICAL: Memory at ${MEM_PERCENT}%\n"
elif [ "$MEM_PERCENT" -ge "$MEM_WARNING" ]; then
  WARNINGS="${WARNINGS}WARNING: Memory at ${MEM_PERCENT}%\n"
fi

# Load check
if [ "$LOAD_INT" -ge "$LOAD_CRITICAL" ]; then
  ALERTS="${ALERTS}CRITICAL: System load at ${LOAD_AVG}\n"
elif [ "$LOAD_INT" -ge "$LOAD_WARNING" ]; then
  WARNINGS="${WARNINGS}WARNING: System load at ${LOAD_AVG}\n"
fi

# Write state
cat > "$STATE_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "disk_percent": $DISK_PERCENT,
  "memory_percent": $MEM_PERCENT,
  "load_avg": $LOAD_AVG,
  "status": "$([ -n "$ALERTS" ] && echo "critical" || ([ -n "$WARNINGS" ] && echo "warning" || echo "healthy"))"
}
EOF

# Handle alerts
if [ -n "$ALERTS" ]; then
  log "CRITICAL ALERTS DETECTED"
  echo -e "Resource Monitor Alerts - $(date)\n${ALERTS}" > "$ALERT_FILE"

  # Add urgent task
  if ! grep -qF "URGENT: Address critical resource issues" "$TASKS_FILE" 2>/dev/null; then
    TEMP_FILE=$(mktemp)
    awk -v task="- [ ] URGENT: Address critical resource issues (disk/memory/load)" '
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

# Handle warnings
if [ -n "$WARNINGS" ]; then
  log "Warnings detected: $WARNINGS"
fi

# Log current state
log "Resources: disk=${DISK_PERCENT}%, mem=${MEM_PERCENT}%, load=${LOAD_AVG}"

# Check for stale processes
ZOMBIE_COUNT=$(ps aux | awk '$8 ~ /Z/ {count++} END {print count+0}')
if [ "$ZOMBIE_COUNT" -gt 5 ]; then
  log "WARNING: $ZOMBIE_COUNT zombie processes detected"
  if ! grep -qF "zombie processes" "$TASKS_FILE" 2>/dev/null; then
    TEMP_FILE=$(mktemp)
    awk -v task="- [ ] Clean up $ZOMBIE_COUNT zombie processes" '
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

echo "Resource check complete. Status: $([ -n "$ALERTS" ] && echo "CRITICAL" || ([ -n "$WARNINGS" ] && echo "WARNING" || echo "OK"))"

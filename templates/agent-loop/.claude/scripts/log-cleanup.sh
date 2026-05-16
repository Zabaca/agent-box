#!/bin/bash

# Log Cleanup Script
# Rotates and removes old log entries

set -euo pipefail

WORKSPACE="/agent-workspace"
LOG_DIR="$WORKSPACE/.claude/loop"
MAX_AGE_DAYS="${1:-7}"
MAX_SIZE_KB="${2:-1024}"  # 1MB default

echo "Log cleanup started at $(date -Iseconds)"
echo "Max age: $MAX_AGE_DAYS days, Max size: ${MAX_SIZE_KB}KB"

# Find all log files
for logfile in "$LOG_DIR"/*.log; do
  [ -f "$logfile" ] || continue

  FILENAME=$(basename "$logfile")
  SIZE_KB=$(du -k "$logfile" | cut -f1)

  echo "Processing $FILENAME (${SIZE_KB}KB)"

  # If file is larger than max size, rotate it
  if [ "$SIZE_KB" -gt "$MAX_SIZE_KB" ]; then
    echo "  Rotating (size exceeds ${MAX_SIZE_KB}KB)"
    mv "$logfile" "${logfile}.old"
    touch "$logfile"
  fi

  # Remove .old files older than MAX_AGE_DAYS
  if [ -f "${logfile}.old" ]; then
    AGE_DAYS=$(( ($(date +%s) - $(stat -c %Y "${logfile}.old")) / 86400 ))
    if [ "$AGE_DAYS" -gt "$MAX_AGE_DAYS" ]; then
      echo "  Removing ${FILENAME}.old (${AGE_DAYS} days old)"
      rm -f "${logfile}.old"
    fi
  fi
done

# Clean up old snapshots
SNAPSHOT_DIR="$WORKSPACE/.claude/snapshots"
if [ -d "$SNAPSHOT_DIR" ]; then
  echo "Cleaning old snapshots..."
  find "$SNAPSHOT_DIR" -name "*.json" -mtime +$MAX_AGE_DAYS -delete -print 2>/dev/null || true
fi

# Clean up old checkpoints
CHECKPOINT_DIR="$WORKSPACE/.claude/checkpoints"
if [ -d "$CHECKPOINT_DIR" ]; then
  echo "Cleaning old checkpoints..."
  find "$CHECKPOINT_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +$MAX_AGE_DAYS -exec rm -rf {} \; -print 2>/dev/null || true
fi

echo "Log cleanup complete"

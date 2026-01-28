#!/bin/bash
#
# File Watcher for Claude Agent Inbox
# Monitors the inbox directory for new files and processes them
#
# Usage: file-watcher.sh [--daemon] [--interval SECONDS]
#        --daemon     Run continuously in background
#        --interval   Check interval in seconds (default: 30)
#

set -euo pipefail

WORKSPACE="/agent-workspace"
INBOX_DIR="$WORKSPACE/.claude/inbox"
PROCESSED_DIR="$INBOX_DIR/processed"
LOG_FILE="$WORKSPACE/.claude/loop/file-watcher.log"
PID_FILE="$WORKSPACE/.claude/loop/file-watcher.pid"
PROCESS_SCRIPT="$WORKSPACE/.claude/scripts/process-inbox.sh"

DAEMON_MODE=false
INTERVAL=30

log() {
  echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
  if [ "$DAEMON_MODE" = "false" ]; then
    echo "[$(date -Iseconds)] $1"
  fi
}

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --daemon|-d)
      DAEMON_MODE=true
      shift
      ;;
    --interval|-i)
      INTERVAL="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: file-watcher.sh [--daemon] [--interval SECONDS]"
      echo "  --daemon     Run continuously in background"
      echo "  --interval   Check interval in seconds (default: 30)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Ensure directories exist
mkdir -p "$INBOX_DIR" "$PROCESSED_DIR"

# Check for new files in inbox
check_inbox() {
  local new_files=0

  # Find files that aren't in the processed directory
  for file in "$INBOX_DIR"/*.txt "$INBOX_DIR"/*.md "$INBOX_DIR"/*.goal; do
    [ -f "$file" ] || continue
    [ "$(dirname "$file")" = "$PROCESSED_DIR" ] && continue

    filename=$(basename "$file")

    # Skip if already processed
    if [ -f "$PROCESSED_DIR/$filename" ]; then
      continue
    fi

    log "Found new file: $filename"
    new_files=$((new_files + 1))
  done

  if [ $new_files -gt 0 ]; then
    log "Processing $new_files new file(s)..."

    # Call the process-inbox script
    if [ -x "$PROCESS_SCRIPT" ]; then
      "$PROCESS_SCRIPT" 2>&1 | while read -r line; do
        log "  $line"
      done
    else
      log "WARNING: process-inbox.sh not executable"
    fi

    log "Processing complete"
    return 0
  else
    return 1
  fi
}

# Single check mode
single_check() {
  log "Checking inbox for new files..."

  if check_inbox; then
    log "New files were processed"
  else
    log "No new files found"
  fi
}

# Daemon mode
daemon_mode() {
  log "Starting file watcher daemon (interval: ${INTERVAL}s)"

  # Save PID
  echo $$ > "$PID_FILE"

  # Trap to clean up on exit
  trap 'rm -f "$PID_FILE"; log "File watcher stopped"; exit 0' SIGTERM SIGINT

  while true; do
    check_inbox || true
    sleep "$INTERVAL"
  done
}

# Main
main() {
  if [ "$DAEMON_MODE" = "true" ]; then
    daemon_mode
  else
    single_check
  fi
}

main

#!/bin/bash

# Retry with Exponential Backoff
# Usage: retry.sh [options] -- command [args...]
#
# Options:
#   -n, --max-retries N    Maximum retry attempts (default: 3)
#   -d, --initial-delay N  Initial delay in seconds (default: 1)
#   -m, --max-delay N      Maximum delay in seconds (default: 60)
#   -f, --factor N         Backoff multiplier (default: 2)
#   -q, --quiet            Suppress progress messages
#   -l, --log FILE         Log failures to file

set -euo pipefail

# Default values
MAX_RETRIES=3
INITIAL_DELAY=1
MAX_DELAY=60
BACKOFF_FACTOR=2
QUIET=false
LOG_FILE=""

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--max-retries)
      MAX_RETRIES="$2"
      shift 2
      ;;
    -d|--initial-delay)
      INITIAL_DELAY="$2"
      shift 2
      ;;
    -m|--max-delay)
      MAX_DELAY="$2"
      shift 2
      ;;
    -f|--factor)
      BACKOFF_FACTOR="$2"
      shift 2
      ;;
    -q|--quiet)
      QUIET=true
      shift
      ;;
    -l|--log)
      LOG_FILE="$2"
      shift 2
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

# Remaining args are the command
if [ $# -eq 0 ]; then
  echo "Usage: retry.sh [options] -- command [args...]" >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  -n, --max-retries N    Maximum retry attempts (default: 3)" >&2
  echo "  -d, --initial-delay N  Initial delay in seconds (default: 1)" >&2
  echo "  -m, --max-delay N      Maximum delay in seconds (default: 60)" >&2
  echo "  -f, --factor N         Backoff multiplier (default: 2)" >&2
  echo "  -q, --quiet            Suppress progress messages" >&2
  echo "  -l, --log FILE         Log failures to file" >&2
  exit 1
fi

COMMAND=("$@")

log_message() {
  local msg="$1"
  [ "$QUIET" = true ] || echo "$msg" >&2
  [ -n "$LOG_FILE" ] && echo "[$(date -Iseconds)] $msg" >> "$LOG_FILE"
}

# Retry loop
ATTEMPT=1
DELAY="$INITIAL_DELAY"

while true; do
  # Try the command
  set +e
  OUTPUT=$("${COMMAND[@]}" 2>&1)
  EXIT_CODE=$?
  set -e

  if [ $EXIT_CODE -eq 0 ]; then
    # Success
    echo "$OUTPUT"
    exit 0
  fi

  # Failed
  if [ $ATTEMPT -ge $MAX_RETRIES ]; then
    log_message "FAILED after $ATTEMPT attempts: ${COMMAND[*]}"
    log_message "Last error: $OUTPUT"
    echo "$OUTPUT" >&2
    exit $EXIT_CODE
  fi

  log_message "Attempt $ATTEMPT failed (exit $EXIT_CODE), retrying in ${DELAY}s..."

  # Wait before retry
  sleep "$DELAY"

  # Calculate next delay with exponential backoff
  DELAY=$((DELAY * BACKOFF_FACTOR))
  [ $DELAY -gt $MAX_DELAY ] && DELAY=$MAX_DELAY

  ATTEMPT=$((ATTEMPT + 1))
done

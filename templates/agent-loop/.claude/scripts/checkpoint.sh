#!/bin/bash

# Checkpoint Script
# Saves current task progress and context for recovery across sessions
# This helps manage context when sessions get long

set -euo pipefail

WORKSPACE="/agent-workspace"
CHECKPOINT_DIR="$WORKSPACE/.claude/checkpoints"
TASKS_FILE="$WORKSPACE/.claude/loop/tasks.md"
MEMORY_FILE="$WORKSPACE/.claude/loop/memory.md"
LEARNINGS_FILE="$WORKSPACE/.claude/learnings.md"
LOG_FILE="$WORKSPACE/.claude/loop/checkpoint.log"

# Ensure directories exist
mkdir -p "$CHECKPOINT_DIR"

log() {
  echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}

# Command: save - Create a checkpoint
save_checkpoint() {
  local CHECKPOINT_NAME="${1:-$(date +%Y%m%d-%H%M%S)}"
  local CHECKPOINT_PATH="$CHECKPOINT_DIR/$CHECKPOINT_NAME"
  
  mkdir -p "$CHECKPOINT_PATH"
  
  # Copy critical files
  cp "$TASKS_FILE" "$CHECKPOINT_PATH/tasks.md" 2>/dev/null || true
  cp "$MEMORY_FILE" "$CHECKPOINT_PATH/memory.md" 2>/dev/null || true
  
  # Create a summary of current state
  local PENDING=$(grep -c '^\- \[ \]' "$TASKS_FILE" 2>/dev/null) || PENDING=0
  local IN_PROGRESS=$(grep -c '^\- \[\.\]' "$TASKS_FILE" 2>/dev/null) || IN_PROGRESS=0
  local COMPLETED=$(grep -c '^\- \[x\]' "$TASKS_FILE" 2>/dev/null) || COMPLETED=0
  
  # Get the in-progress task
  local CURRENT_TASK=""
  if [ "$IN_PROGRESS" -gt 0 ]; then
    CURRENT_TASK=$(grep '^\- \[\.\]' "$TASKS_FILE" 2>/dev/null | head -1 | sed 's/^\- \[\.\] //')
  fi
  
  # Create checkpoint summary
  cat > "$CHECKPOINT_PATH/summary.md" <<EOF
# Checkpoint: $CHECKPOINT_NAME

Created: $(date -Iseconds)

## Task Status
- Pending: $PENDING
- In Progress: $IN_PROGRESS
- Completed: $COMPLETED

## Current Task
${CURRENT_TASK:-None}

## Recent Completed Tasks
$(grep '^\- \[x\]' "$TASKS_FILE" 2>/dev/null | tail -5 | sed 's/^\- \[x\] /- /')

## Git Status
$(cd "$WORKSPACE" && git log -1 --format='Commit: %h - %s (%cr)')

## Resource Status
$(cat "$WORKSPACE/.claude/loop/resource-state.json" 2>/dev/null || echo '{"status":"unknown"}')
EOF

  # Create a handoff prompt for next session
  cat > "$CHECKPOINT_PATH/handoff.md" <<EOF
# Session Handoff

You are continuing work from a previous session. Here's what was happening:

## Current Task
${CURRENT_TASK:-No task was in progress.}

## Context
- $PENDING tasks are waiting in the queue
- $COMPLETED tasks have been completed this session

## To Resume
1. Read /agent-workspace/.claude/loop/memory.md for full context
2. Read /agent-workspace/.claude/loop/tasks.md for the task queue
3. Continue with the in-progress task or pick up the next pending task

## Recent Work
$(grep '^\- \[x\]' "$TASKS_FILE" 2>/dev/null | tail -3 | sed 's/^\- \[x\] /- Completed: /')
EOF

  log "Checkpoint saved: $CHECKPOINT_NAME"
  echo "Checkpoint saved to $CHECKPOINT_PATH"
  echo "Handoff file: $CHECKPOINT_PATH/handoff.md"
}

# Command: restore - Restore from a checkpoint
restore_checkpoint() {
  local CHECKPOINT_NAME="$1"
  local CHECKPOINT_PATH="$CHECKPOINT_DIR/$CHECKPOINT_NAME"
  
  if [ ! -d "$CHECKPOINT_PATH" ]; then
    echo "Error: Checkpoint '$CHECKPOINT_NAME' not found"
    echo "Available checkpoints:"
    ls -1 "$CHECKPOINT_DIR" 2>/dev/null || echo "  (none)"
    return 1
  fi
  
  # Restore files
  if [ -f "$CHECKPOINT_PATH/tasks.md" ]; then
    cp "$CHECKPOINT_PATH/tasks.md" "$TASKS_FILE"
    echo "Restored tasks.md"
  fi
  
  if [ -f "$CHECKPOINT_PATH/memory.md" ]; then
    cp "$CHECKPOINT_PATH/memory.md" "$MEMORY_FILE"
    echo "Restored memory.md"
  fi
  
  log "Restored from checkpoint: $CHECKPOINT_NAME"
  echo "Checkpoint restored from $CHECKPOINT_PATH"
}

# Command: list - List available checkpoints
list_checkpoints() {
  echo "Available checkpoints:"
  if [ -d "$CHECKPOINT_DIR" ]; then
    for cp in "$CHECKPOINT_DIR"/*/; do
      if [ -d "$cp" ]; then
        local name=$(basename "$cp")
        local summary="$cp/summary.md"
        if [ -f "$summary" ]; then
          local created=$(grep '^Created:' "$summary" | cut -d' ' -f2)
          local pending=$(grep 'Pending:' "$summary" | awk '{print $NF}')
          echo "  $name (created: $created, pending: $pending tasks)"
        else
          echo "  $name"
        fi
      fi
    done
  else
    echo "  (no checkpoints)"
  fi
}

# Command: clean - Remove old checkpoints
clean_checkpoints() {
  local KEEP=${1:-5}
  local count=0
  
  if [ -d "$CHECKPOINT_DIR" ]; then
    # Sort by modification time, keep newest
    for cp in $(ls -1t "$CHECKPOINT_DIR" 2>/dev/null); do
      count=$((count + 1))
      if [ $count -gt $KEEP ]; then
        rm -rf "$CHECKPOINT_DIR/$cp"
        log "Removed old checkpoint: $cp"
        echo "Removed: $cp"
      fi
    done
  fi
  
  echo "Kept $KEEP most recent checkpoints"
}

# Main
case "${1:-save}" in
  save)
    save_checkpoint "${2:-}"
    ;;
  restore)
    if [ -z "${2:-}" ]; then
      echo "Usage: checkpoint.sh restore <checkpoint-name>"
      list_checkpoints
      exit 1
    fi
    restore_checkpoint "$2"
    ;;
  list)
    list_checkpoints
    ;;
  clean)
    clean_checkpoints "${2:-5}"
    ;;
  *)
    echo "Usage: checkpoint.sh [save|restore|list|clean] [args]"
    echo ""
    echo "Commands:"
    echo "  save [name]     - Create a checkpoint (default: timestamp)"
    echo "  restore <name>  - Restore from a checkpoint"
    echo "  list            - List available checkpoints"
    echo "  clean [keep]    - Remove old checkpoints (default: keep 5)"
    ;;
esac

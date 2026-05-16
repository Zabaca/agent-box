#!/bin/bash

# Enhanced Autonomous Loop - Stop Hook
# Features:
# - Task-queue driven continuation (loop while tasks remain)
# - Memory injection (memory.md content injected into every iteration)
# - Natural exit (loop ends when all tasks complete)
# - Max iteration safety limit (prevents runaway loops)
# - Memory size monitoring (warns if context too large)
# - Debug logging for troubleshooting

set -euo pipefail

WORKSPACE="/agent-workspace"
TASKS_FILE="$WORKSPACE/.claude/loop/tasks.md"
MEMORY_FILE="$WORKSPACE/.claude/loop/memory.md"
STATE_FILE="$WORKSPACE/.claude/loop/state.json"
STOP_SIGNAL="$WORKSPACE/.claude/loop/stop-signal"
STOP_RULES_FILE="$WORKSPACE/.claude/loop/stop-rules.md"
LOCK_FILE="$WORKSPACE/.claude/loop/claude.lock"
NOTIFY_SCRIPT="$WORKSPACE/.claude/scripts/email-notify.sh"
CHECKPOINT_SCRIPT="$WORKSPACE/.claude/scripts/checkpoint.sh"
LOG_FILE="$WORKSPACE/.claude/logs/stop-hook.log"

# Configuration
MAX_ITERATIONS=${MAX_ITERATIONS:-100}            # Safety limit for iterations
MAX_MEMORY_KB=${MAX_MEMORY_KB:-100}              # Warn if memory.md exceeds this size
DEBUG_MODE=${DEBUG_MODE:-false}                   # Enable debug logging

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Debug logging function
debug_log() {
  if [ "$DEBUG_MODE" = "true" ]; then
    echo "[$(date -Iseconds)] $*" >> "$LOG_FILE"
  fi
}

# Function to send notification
notify() {
  local type="$1"
  local message="$2"
  if [ -x "$NOTIFY_SCRIPT" ]; then
    "$NOTIFY_SCRIPT" "$type" "$message" 2>/dev/null || true
  fi
}

# Function to clean up lock file on exit
cleanup_lock() {
  rm -f "$LOCK_FILE" 2>/dev/null || true
}

# Function to auto-commit progress
git_checkpoint() {
  cd "$WORKSPACE" || return
  if [ -d ".git" ]; then
    # Add all changes
    git add -A 2>/dev/null || true
    # Check if there are changes to commit
    if ! git diff --cached --quiet 2>/dev/null; then
      TIMESTAMP=$(date -Iseconds)
      git commit -m "Auto-checkpoint: $TIMESTAMP" -m "Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>" 2>/dev/null || true
    fi
  fi
}

# Function to save state checkpoint
save_checkpoint() {
  if [ -x "$CHECKPOINT_SCRIPT" ]; then
    "$CHECKPOINT_SCRIPT" save "auto-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    # Clean up old checkpoints (keep 10)
    "$CHECKPOINT_SCRIPT" clean 10 2>/dev/null || true
  fi
}

# Read hook input from stdin
HOOK_INPUT=$(cat)

debug_log "Stop hook triggered"

# Check for manual stop signal
if [ -f "$STOP_SIGNAL" ]; then
  rm -f "$STOP_SIGNAL"
  save_checkpoint
  git_checkpoint
  cleanup_lock
  notify "info" "Loop stopped via stop-signal"
  debug_log "Stop signal detected - exiting"
  echo "🛑 Stop signal detected. Loop ending." >&2
  exit 0
fi

# Check if task file exists - no file means no loop
if [ ! -f "$TASKS_FILE" ]; then
  exit 0
fi

# Count pending and in-progress tasks
# - [ ] = pending
# - [.] = in progress
# Note: grep -c returns 0 count but exit code 1 when no matches
# Using || : to prevent errexit, then defaulting empty to 0
PENDING=$(grep -c '^\- \[ \]' "$TASKS_FILE" 2>/dev/null) || :
PENDING=${PENDING:-0}
IN_PROGRESS=$(grep -c '^\- \[\.\]' "$TASKS_FILE" 2>/dev/null) || :
IN_PROGRESS=${IN_PROGRESS:-0}

# If no pending or in-progress tasks, try to generate from standing goals
if [ "$PENDING" -eq 0 ] && [ "$IN_PROGRESS" -eq 0 ]; then
  TASK_GENERATOR="$WORKSPACE/.claude/scripts/generate-tasks.sh"
  if [ -x "$TASK_GENERATOR" ]; then
    "$TASK_GENERATOR" 2>/dev/null || true
    # Re-count tasks after generation
    PENDING=$(grep -c '^\- \[ \]' "$TASKS_FILE" 2>/dev/null) || :
    PENDING=${PENDING:-0}
  fi
fi

# If still no tasks after generation, allow exit
if [ "$PENDING" -eq 0 ] && [ "$IN_PROGRESS" -eq 0 ]; then
  # Reset iteration counter for next batch of tasks
  echo '{"iteration": 0, "updated_at": "'"$(date -Iseconds)"'", "reset_reason": "all_tasks_complete"}' > "$STATE_FILE"
  save_checkpoint
  git_checkpoint
  cleanup_lock
  notify "success" "All tasks complete - loop finished"
  echo "✅ All tasks complete. Loop ending." >&2
  exit 0
fi

# Tasks remain - continue the loop

# Update iteration count
ITERATION=1
if [ -f "$STATE_FILE" ]; then
  ITERATION=$(jq -r '.iteration // 0' "$STATE_FILE" 2>/dev/null || echo "0")
  ITERATION=$((ITERATION + 1))
fi

# Write updated state
jq -n --argjson iter "$ITERATION" '{iteration: $iter, updated_at: (now | todate)}' > "$STATE_FILE"

debug_log "Iteration $ITERATION: $PENDING pending, $IN_PROGRESS in progress"

# Safety check: max iterations limit
if [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
  save_checkpoint
  git_checkpoint
  cleanup_lock
  notify "warning" "Max iterations ($MAX_ITERATIONS) reached - loop paused"
  debug_log "Max iterations reached - exiting"
  echo "⚠️ Max iterations ($MAX_ITERATIONS) reached. Loop paused for safety." >&2
  exit 0
fi

# Read memory content
MEMORY_CONTENT=""
if [ -f "$MEMORY_FILE" ]; then
  MEMORY_CONTENT=$(cat "$MEMORY_FILE")

  # Check memory size
  MEMORY_SIZE_KB=$(du -k "$MEMORY_FILE" 2>/dev/null | cut -f1 || echo "0")
  if [ "$MEMORY_SIZE_KB" -gt "$MAX_MEMORY_KB" ]; then
    notify "warning" "Memory file is ${MEMORY_SIZE_KB}KB (limit: ${MAX_MEMORY_KB}KB) - consider trimming"
    debug_log "Memory size warning: ${MEMORY_SIZE_KB}KB"
  fi
fi

# Read tasks content
TASKS_CONTENT=$(cat "$TASKS_FILE")

# Read stop rules content
STOP_RULES_CONTENT=""
if [ -f "$STOP_RULES_FILE" ]; then
  STOP_RULES_CONTENT=$(cat "$STOP_RULES_FILE")
fi

# Construct the enriched prompt with memory injection
# Note: Using unquoted heredoc (<<PROMPT_EOF not <<'PROMPT_EOF') to expand variables
# This avoids the bash ${var/pattern/replacement} bug where & is treated specially
PROMPT=$(cat <<PROMPT_EOF
<stop-rules>
$STOP_RULES_CONTENT
</stop-rules>

<memory>
$MEMORY_CONTENT
</memory>

<tasks>
$TASKS_CONTENT
</tasks>

## Instructions

You are in an autonomous loop. Work through the task queue:

1. Read the memory and tasks above
2. Pick the next pending task (or continue in-progress task)
3. Mark it as in-progress: \`- [.]\`
4. Do the work
5. Mark it as complete: \`- [x]\`
6. Update /agent-workspace/.claude/loop/memory.md with any important context
7. Add new tasks to /agent-workspace/.claude/loop/tasks.md if you discover them

The loop will continue automatically while tasks remain.
To stop early: create /agent-workspace/.claude/loop/stop-signal

**REMEMBER: Before stopping or asking the user anything, re-read <stop-rules> above.**
PROMPT_EOF
)

# Output JSON to block exit and feed enriched prompt back
jq -n \
  --arg prompt "$PROMPT" \
  --arg msg "🔄 Loop iteration $ITERATION | $PENDING pending, $IN_PROGRESS in progress" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0

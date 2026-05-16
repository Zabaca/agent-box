#!/bin/bash

# Generate Tasks from Standing Goals
# Called when task queue is empty to ensure agent always has work

set -euo pipefail

WORKSPACE="/agent-workspace"
GOALS_FILE="$WORKSPACE/.claude/loop/goals.md"
TASKS_FILE="$WORKSPACE/.claude/loop/tasks.md"
HEALTH_SCRIPT="$WORKSPACE/.claude/scripts/health-check.sh"
LOG_FILE="$WORKSPACE/.claude/loop/task-generation.log"

log() {
  echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}

# Ensure goals file exists
if [ ! -f "$GOALS_FILE" ]; then
  log "ERROR: Goals file not found at $GOALS_FILE"
  exit 1
fi

# Check if tasks file needs tasks
PENDING=0
IN_PROGRESS=0
if [ -f "$TASKS_FILE" ]; then
  PENDING=$(grep -c '^\- \[ \]' "$TASKS_FILE" 2>/dev/null) || :
  PENDING=${PENDING:-0}
  IN_PROGRESS=$(grep -c '^\- \[\.\]' "$TASKS_FILE" 2>/dev/null) || :
  IN_PROGRESS=${IN_PROGRESS:-0}
fi

# Only generate if queue is empty
if [ "$PENDING" -gt 0 ] || [ "$IN_PROGRESS" -gt 0 ]; then
  log "Task queue not empty ($PENDING pending, $IN_PROGRESS in progress). Skipping generation."
  exit 0
fi

log "Task queue empty. Generating tasks from standing goals..."

# Rotate through different goal categories based on day/hour
# This ensures variety in generated tasks
HOUR=$(date +%H)
DAY=$(date +%j)  # Day of year

# Determine which category to focus on
CATEGORIES=("Self-Improvement" "Maintenance" "Exploration" "Communication" "Growth" "Week5")
CATEGORY_INDEX=$(( (DAY + HOUR / 6) % ${#CATEGORIES[@]} ))
FOCUS_CATEGORY="${CATEGORIES[$CATEGORY_INDEX]}"

log "Focus category for this cycle: $FOCUS_CATEGORY"

# Generate tasks based on focus category and current state
GENERATED_TASKS=""

case "$FOCUS_CATEGORY" in
  "Self-Improvement")
    GENERATED_TASKS=$(cat <<'EOF'
- [ ] Review stop-hook.sh for potential improvements
- [ ] Check heartbeat.sh for edge cases that might cause failures
- [ ] Review recent learnings and apply any patterns not yet implemented
EOF
)
    ;;
  "Maintenance")
    # Run health check to determine maintenance tasks
    HEALTH_OUTPUT=""
    if [ -x "$HEALTH_SCRIPT" ]; then
      HEALTH_OUTPUT=$("$HEALTH_SCRIPT" 2>/dev/null || echo '{"status":"unknown"}')
    fi

    # Check for issues in health output
    ISSUES=$(echo "$HEALTH_OUTPUT" | jq -r '.issues[]' 2>/dev/null || echo "")
    WARNINGS=$(echo "$HEALTH_OUTPUT" | jq -r '.warnings[]' 2>/dev/null || echo "")

    if [ -n "$ISSUES" ] || [ -n "$WARNINGS" ]; then
      GENERATED_TASKS="- [ ] Address health check issues: review health.json and fix problems"
    else
      GENERATED_TASKS=$(cat <<'EOF'
- [ ] Run health check and verify all systems operational
- [ ] Review heartbeat.log for any anomalies
- [ ] Clean up old log entries older than 7 days
EOF
)
    fi
    ;;
  "Exploration")
    # Infrastructure is COMPLETE. Exploration should focus on finding validated problems.
    # Per critical learning: "Building without problem validation = wasted effort"
    GENERATED_TASKS=$(cat <<'EOF'
- [ ] Check email inbox for new tasks or messages
- [ ] Monitor envcheck GitHub for issues or feedback
- [ ] Research developer pain points with evidence (SO questions, GitHub issues)
EOF
)
    ;;
  "Communication")
    GENERATED_TASKS=$(cat <<'EOF'
- [ ] Check inbox for new messages or task requests
- [ ] Update memory.md with current operational state
- [ ] Create a status summary in notifications
EOF
)
    ;;
  "Growth")
    # Per critical learning: Only build after validating problem exists
    GENERATED_TASKS=$(cat <<'EOF'
- [ ] Check Dev.to article for comments or reactions
- [ ] Check npm for any envcheck dependents or feedback
- [ ] Search for new developer problems with 3+ evidence links
EOF
)
    ;;
  "Week5"|"Week6"|"Week7"|"Week8"|"Week9")
    # All week objectives are COMPLETE - infrastructure is built
    # Generate monitoring tasks instead
    GENERATED_TASKS=$(cat <<'EOF'
- [ ] Run health check and verify all systems operational
- [ ] Check email inbox for new messages
- [ ] Review system logs for any anomalies
EOF
)
    ;;
esac

# Add generated tasks to the task file
if [ -n "$GENERATED_TASKS" ]; then
  # Ensure tasks.md exists with proper structure
  if [ ! -f "$TASKS_FILE" ]; then
    cat > "$TASKS_FILE" <<'EOF'
# Task Queue

## Pending

## In Progress

## Completed
EOF
  fi

  # Filter out tasks that already exist anywhere in the task file
  # This includes pending, in-progress, AND completed tasks
  FILTERED_TASKS=""

  # Read the entire task file for duplicate checking
  ALL_TASKS=$(cat "$TASKS_FILE" 2>/dev/null || echo "")

  while IFS= read -r task; do
    # Skip empty lines
    [ -z "$task" ] && continue
    # Extract task text (remove "- [ ] " prefix)
    TASK_TEXT="${task#- \[ \] }"
    # Extract a short key (first 5 words) for matching - handles both short and long task descriptions
    TASK_KEY=$(echo "$TASK_TEXT" | awk '{print $1, $2, $3, $4, $5}' | sed 's/ *$//')
    # Check if this task key already exists anywhere in the file (case-insensitive)
    if ! grep -qiF "$TASK_KEY" "$TASKS_FILE" 2>/dev/null; then
      FILTERED_TASKS="${FILTERED_TASKS}${task}
"
    else
      log "Skipping duplicate task (key '$TASK_KEY' already exists): $TASK_TEXT"
    fi
  done <<< "$GENERATED_TASKS"

  # Remove trailing newline
  FILTERED_TASKS="${FILTERED_TASKS%$'\n'}"

  if [ -n "$FILTERED_TASKS" ]; then
    # Insert tasks after "## Pending" line
    TEMP_FILE=$(mktemp)
    awk -v tasks="$FILTERED_TASKS" '
      /^## Pending/ {
        print
        print tasks
        next
      }
      { print }
    ' "$TASKS_FILE" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$TASKS_FILE"

    log "Generated tasks for $FOCUS_CATEGORY category"
    echo "$FILTERED_TASKS" >> "$LOG_FILE"
  else
    log "All tasks for $FOCUS_CATEGORY already exist, skipping"
  fi
fi

log "Task generation complete"

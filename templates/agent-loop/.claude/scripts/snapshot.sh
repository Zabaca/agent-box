#!/bin/bash

# State Snapshot Tool
# Captures complete agent state for context management and recovery
# Useful for: context switches, backups, debugging, recovery

set -euo pipefail

WORKSPACE="/agent-workspace"
SNAPSHOT_DIR="$WORKSPACE/.claude/snapshots"
LOOP_DIR="$WORKSPACE/.claude/loop"

mkdir -p "$SNAPSHOT_DIR"

usage() {
  cat <<EOF
Usage: snapshot.sh <command> [args]

Commands:
  create [name]     - Create a new snapshot (default name: timestamp)
  list              - List all snapshots
  show <name>       - Display snapshot contents
  restore <name>    - Restore from a snapshot
  prune [days]      - Remove snapshots older than N days (default: 7)
  latest            - Show the most recent snapshot

Example:
  snapshot.sh create before-refactor
  snapshot.sh restore before-refactor
EOF
}

get_timestamp() {
  date +%Y%m%d-%H%M%S
}

create_snapshot() {
  local NAME="${1:-$(get_timestamp)}"
  local SNAPSHOT_FILE="$SNAPSHOT_DIR/${NAME}.json"

  # Gather state
  local TASKS_CONTENT=""
  local MEMORY_CONTENT=""
  local STATE_CONTENT=""
  local LEARNINGS_CONTENT=""
  local GOALS_CONTENT=""

  [ -f "$LOOP_DIR/tasks.md" ] && TASKS_CONTENT=$(cat "$LOOP_DIR/tasks.md")
  [ -f "$LOOP_DIR/memory.md" ] && MEMORY_CONTENT=$(cat "$LOOP_DIR/memory.md")
  [ -f "$LOOP_DIR/state.json" ] && STATE_CONTENT=$(cat "$LOOP_DIR/state.json")
  [ -f "$WORKSPACE/.claude/learnings.md" ] && LEARNINGS_CONTENT=$(cat "$WORKSPACE/.claude/learnings.md")
  [ -f "$LOOP_DIR/goals.md" ] && GOALS_CONTENT=$(cat "$LOOP_DIR/goals.md")

  # Get git info
  local GIT_COMMIT=""
  local GIT_BRANCH=""
  if [ -d "$WORKSPACE/.git" ]; then
    GIT_COMMIT=$(cd "$WORKSPACE" && git rev-parse HEAD 2>/dev/null || echo "unknown")
    GIT_BRANCH=$(cd "$WORKSPACE" && git branch --show-current 2>/dev/null || echo "unknown")
  fi

  # Get resource info
  local DISK_PERCENT=$(df "$WORKSPACE" 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}' || echo "0")
  local MEM_PERCENT=$(free 2>/dev/null | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}' || echo "0")

  # Count tasks
  local PENDING=$(echo "$TASKS_CONTENT" | grep -c '^\- \[ \]' || echo "0")
  local IN_PROGRESS=$(echo "$TASKS_CONTENT" | grep -c '^\- \[\.\]' || echo "0")
  local COMPLETED=$(echo "$TASKS_CONTENT" | grep -c '^\- \[x\]' || echo "0")

  # Build snapshot JSON
  jq -n \
    --arg name "$NAME" \
    --arg created_at "$(date -Iseconds)" \
    --arg tasks "$TASKS_CONTENT" \
    --arg memory "$MEMORY_CONTENT" \
    --arg learnings "$LEARNINGS_CONTENT" \
    --arg goals "$GOALS_CONTENT" \
    --arg state "$STATE_CONTENT" \
    --arg git_commit "$GIT_COMMIT" \
    --arg git_branch "$GIT_BRANCH" \
    --argjson disk_percent "$DISK_PERCENT" \
    --argjson mem_percent "$MEM_PERCENT" \
    --argjson pending "$PENDING" \
    --argjson in_progress "$IN_PROGRESS" \
    --argjson completed "$COMPLETED" \
    '{
      name: $name,
      created_at: $created_at,
      summary: {
        tasks_pending: $pending,
        tasks_in_progress: $in_progress,
        tasks_completed: $completed,
        disk_percent: $disk_percent,
        mem_percent: $mem_percent,
        git_commit: $git_commit,
        git_branch: $git_branch
      },
      files: {
        tasks: $tasks,
        memory: $memory,
        learnings: $learnings,
        goals: $goals,
        state: $state
      }
    }' > "$SNAPSHOT_FILE"

  echo "Snapshot created: $SNAPSHOT_FILE"
  echo "Summary: $PENDING pending, $IN_PROGRESS in-progress, $COMPLETED completed tasks"
}

list_snapshots() {
  echo "Snapshots:"
  shopt -s nullglob
  for f in "$SNAPSHOT_DIR"/*.json; do
    if [ -f "$f" ]; then
      NAME=$(basename "$f" .json)
      CREATED=$(jq -r '.created_at' "$f" 2>/dev/null || echo "unknown")
      PENDING=$(jq -r '.summary.tasks_pending' "$f" 2>/dev/null || echo "?")
      echo "  - $NAME (created: $CREATED, pending: $PENDING)"
    fi
  done
  shopt -u nullglob
}

show_snapshot() {
  local NAME="$1"
  local SNAPSHOT_FILE="$SNAPSHOT_DIR/${NAME}.json"

  if [ ! -f "$SNAPSHOT_FILE" ]; then
    echo "Snapshot not found: $NAME" >&2
    exit 1
  fi

  jq '.' "$SNAPSHOT_FILE"
}

restore_snapshot() {
  local NAME="$1"
  local SNAPSHOT_FILE="$SNAPSHOT_DIR/${NAME}.json"

  if [ ! -f "$SNAPSHOT_FILE" ]; then
    echo "Snapshot not found: $NAME" >&2
    exit 1
  fi

  echo "Restoring from snapshot: $NAME"

  # Create backup of current state first
  create_snapshot "pre-restore-$(get_timestamp)"

  # Restore files
  jq -r '.files.tasks' "$SNAPSHOT_FILE" > "$LOOP_DIR/tasks.md"
  jq -r '.files.memory' "$SNAPSHOT_FILE" > "$LOOP_DIR/memory.md"
  jq -r '.files.goals' "$SNAPSHOT_FILE" > "$LOOP_DIR/goals.md"

  local STATE=$(jq -r '.files.state' "$SNAPSHOT_FILE")
  if [ "$STATE" != "null" ] && [ -n "$STATE" ]; then
    echo "$STATE" > "$LOOP_DIR/state.json"
  fi

  echo "Restore complete. Current state backed up to pre-restore-*"
}

prune_snapshots() {
  local DAYS="${1:-7}"
  local COUNT=0

  echo "Pruning snapshots older than $DAYS days..."

  shopt -s nullglob
  for f in "$SNAPSHOT_DIR"/*.json; do
    if [ -f "$f" ]; then
      # Check file age
      local AGE_DAYS=$(( ($(date +%s) - $(stat -c %Y "$f")) / 86400 ))
      if [ "$AGE_DAYS" -gt "$DAYS" ]; then
        rm -f "$f"
        COUNT=$((COUNT + 1))
      fi
    fi
  done
  shopt -u nullglob

  echo "Removed $COUNT old snapshots"
}

show_latest() {
  local LATEST=""
  local LATEST_TIME=0

  shopt -s nullglob
  for f in "$SNAPSHOT_DIR"/*.json; do
    if [ -f "$f" ]; then
      local MTIME=$(stat -c %Y "$f")
      if [ "$MTIME" -gt "$LATEST_TIME" ]; then
        LATEST="$f"
        LATEST_TIME="$MTIME"
      fi
    fi
  done
  shopt -u nullglob

  if [ -n "$LATEST" ]; then
    echo "Latest snapshot: $(basename "$LATEST" .json)"
    jq '.summary' "$LATEST"
  else
    echo "No snapshots found"
  fi
}

# Main command dispatch
case "${1:-}" in
  create)
    create_snapshot "${2:-}"
    ;;
  list)
    list_snapshots
    ;;
  show)
    [ -z "${2:-}" ] && { echo "Error: snapshot name required" >&2; exit 1; }
    show_snapshot "$2"
    ;;
  restore)
    [ -z "${2:-}" ] && { echo "Error: snapshot name required" >&2; exit 1; }
    restore_snapshot "$2"
    ;;
  prune)
    prune_snapshots "${2:-7}"
    ;;
  latest)
    show_latest
    ;;
  *)
    usage
    exit 1
    ;;
esac

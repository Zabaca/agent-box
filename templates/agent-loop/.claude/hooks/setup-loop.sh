#!/bin/bash

# Enhanced Autonomous Loop - Setup Script
# Initializes the loop directory structure

set -euo pipefail

WORKSPACE="/agent-workspace"
LOOP_DIR="$WORKSPACE/.claude/loop"

mkdir -p "$LOOP_DIR"

# Initialize state
echo '{"iteration": 0}' > "$LOOP_DIR/state.json"

# Create tasks.md if not exists
if [ ! -f "$LOOP_DIR/tasks.md" ]; then
  cat > "$LOOP_DIR/tasks.md" <<'EOF'
# Task Queue

## Pending
- [ ] (Add your tasks here)

## In Progress

## Completed
EOF
  echo "Created: $LOOP_DIR/tasks.md"
else
  echo "Exists:  $LOOP_DIR/tasks.md"
fi

# Create memory.md if not exists
if [ ! -f "$LOOP_DIR/memory.md" ]; then
  cat > "$LOOP_DIR/memory.md" <<'EOF'
# Memory

## Context
(Describe what you're working on)

## Key Decisions
(None yet)

## Findings
(None yet)

## Last Updated
(Not yet)
EOF
  echo "Created: $LOOP_DIR/memory.md"
else
  echo "Exists:  $LOOP_DIR/memory.md"
fi

echo ""
echo "✅ Loop initialized"
echo ""
echo "Files:"
echo "  Tasks:  $LOOP_DIR/tasks.md"
echo "  Memory: $LOOP_DIR/memory.md"
echo "  State:  $LOOP_DIR/state.json"
echo ""
echo "Usage:"
echo "  1. Edit tasks.md to add your tasks"
echo "  2. Start claude and send any message"
echo "  3. Loop continues while tasks remain"
echo ""
echo "To stop: touch $LOOP_DIR/stop-signal"

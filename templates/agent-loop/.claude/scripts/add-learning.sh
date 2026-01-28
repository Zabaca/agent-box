#!/bin/bash

# Add Learning Script
# Usage: add-learning.sh "title" "issue" "discovery" "solution" "apply"
# Or: add-learning.sh -i for interactive mode

set -euo pipefail

WORKSPACE="/agent-workspace"
LEARNINGS_FILE="$WORKSPACE/.claude/learnings.md"

if [ "${1:-}" = "-i" ]; then
  echo "Interactive mode - enter learning details:"
  read -p "Title: " TITLE
  read -p "Issue/Context: " ISSUE
  read -p "How discovered: " DISCOVERY
  read -p "Solution: " SOLUTION
  read -p "How to apply: " APPLY
else
  TITLE="${1:-Untitled Learning}"
  ISSUE="${2:-}"
  DISCOVERY="${3:-}"
  SOLUTION="${4:-}"
  APPLY="${5:-}"
fi

DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date -Iseconds)

# Validate - must have at least some content
if [ -z "$ISSUE" ] && [ -z "$DISCOVERY" ] && [ -z "$SOLUTION" ] && [ -z "$APPLY" ]; then
  echo "Error: Learning must have at least one field filled in (issue, discovery, solution, or apply)"
  exit 1
fi

# Check file size - warn if getting large
if [ -f "$LEARNINGS_FILE" ]; then
  LINE_COUNT=$(wc -l < "$LEARNINGS_FILE" 2>/dev/null || echo "0")
  if [ "$LINE_COUNT" -gt 1000 ]; then
    echo "Warning: Learnings file has $LINE_COUNT lines - consider reviewing and archiving old entries"
  fi
fi

cat >> "$LEARNINGS_FILE" <<EOF
## $DATE: $TITLE

- **Issue**: $ISSUE
- **Discovery**: $DISCOVERY
- **Solution**: $SOLUTION
- **Apply**: $APPLY

---

EOF

echo "Learning added: $TITLE"

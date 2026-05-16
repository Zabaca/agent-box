#!/bin/bash

# Script Test Framework
# Validates all infrastructure scripts

set -uo pipefail

WORKSPACE="/agent-workspace"
SCRIPTS_DIR="$WORKSPACE/.claude/scripts"
HOOKS_DIR="$WORKSPACE/.claude/hooks"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASSED=0
FAILED=0

echo "============================================"
echo "  Infrastructure Script Tests"
echo "============================================"
echo ""

# Test all scripts in scripts directory
echo "Scripts:"
for script in "$SCRIPTS_DIR"/*.sh; do
  [ -f "$script" ] || continue
  name=$(basename "$script")

  errors=""

  # Check executable
  if [ ! -x "$script" ]; then
    errors="not executable"
  fi

  # Check syntax
  if ! bash -n "$script" 2>/dev/null; then
    errors="${errors:+$errors, }syntax error"
  fi

  if [ -z "$errors" ]; then
    echo -e "  ${GREEN}✓${NC} $name"
    PASSED=$((PASSED + 1))
  else
    echo -e "  ${RED}✗${NC} $name ($errors)"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "Hooks:"
for hook in "$HOOKS_DIR"/*.sh; do
  [ -f "$hook" ] || continue
  name=$(basename "$hook")

  errors=""

  if [ ! -x "$hook" ]; then
    errors="not executable"
  fi

  if ! bash -n "$hook" 2>/dev/null; then
    errors="${errors:+$errors, }syntax error"
  fi

  if [ -z "$errors" ]; then
    echo -e "  ${GREEN}✓${NC} $name"
    PASSED=$((PASSED + 1))
  else
    echo -e "  ${RED}✗${NC} $name ($errors)"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "============================================"
echo -e "  Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"
echo "============================================"

exit $FAILED

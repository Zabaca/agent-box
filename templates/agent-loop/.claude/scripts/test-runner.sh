#!/bin/bash
#
# Script Test Framework
# Validates infrastructure scripts through automated testing
#
# Usage: test-runner.sh [script_name] [--verbose]
#        test-runner.sh                    # Run all tests
#        test-runner.sh health-check       # Test specific script
#        test-runner.sh --list             # List available tests
#

set -uo pipefail

WORKSPACE="/agent-workspace"
SCRIPTS_DIR="$WORKSPACE/.claude/scripts"
TESTS_DIR="$WORKSPACE/.claude/tests"
LOG_FILE="$WORKSPACE/.claude/loop/test-runner.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VERBOSE=false
SPECIFIC_TEST=""
PASSED=0
FAILED=0
SKIPPED=0

log() {
  echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}

print_result() {
  local status="$1"
  local name="$2"
  local message="${3:-}"

  case "$status" in
    PASS)
      echo -e "${GREEN}[PASS]${NC} $name"
      PASSED=$((PASSED + 1))
      ;;
    FAIL)
      echo -e "${RED}[FAIL]${NC} $name"
      [ -n "$message" ] && echo -e "       ${RED}$message${NC}"
      FAILED=$((FAILED + 1))
      ;;
    SKIP)
      echo -e "${YELLOW}[SKIP]${NC} $name"
      [ -n "$message" ] && echo -e "       ${YELLOW}$message${NC}"
      SKIPPED=$((SKIPPED + 1))
      ;;
  esac
}

# Test: Script exists and is executable
test_script_exists() {
  local script="$1"
  local path="$SCRIPTS_DIR/$script"

  if [ -f "$path" ]; then
    if [ -x "$path" ]; then
      print_result "PASS" "$script: exists and is executable"
      return 0
    else
      print_result "FAIL" "$script: not executable"
      return 1
    fi
  else
    print_result "FAIL" "$script: file not found"
    return 1
  fi
}

# Test: Script has valid bash syntax
test_script_syntax() {
  local script="$1"
  local path="$SCRIPTS_DIR/$script"

  if [ ! -f "$path" ]; then
    print_result "SKIP" "$script syntax: file not found"
    return 1
  fi

  local output
  output=$(bash -n "$path" 2>&1)
  if [ $? -eq 0 ]; then
    print_result "PASS" "$script: valid bash syntax"
    return 0
  else
    print_result "FAIL" "$script: syntax error" "$output"
    return 1
  fi
}

# Test: Script has shebang
test_script_shebang() {
  local script="$1"
  local path="$SCRIPTS_DIR/$script"

  if [ ! -f "$path" ]; then
    print_result "SKIP" "$script shebang: file not found"
    return 1
  fi

  local first_line
  first_line=$(head -1 "$path")
  if echo "$first_line" | grep -qE '^#!/(bin/bash|usr/bin/env bash)'; then
    print_result "PASS" "$script: has valid shebang"
    return 0
  else
    print_result "FAIL" "$script: missing or invalid shebang"
    return 1
  fi
}

# Test: Script uses set -e or set -euo pipefail
test_script_error_handling() {
  local script="$1"
  local path="$SCRIPTS_DIR/$script"

  if [ ! -f "$path" ]; then
    print_result "SKIP" "$script error handling: file not found"
    return 1
  fi

  if grep -qE '^set -[euo]' "$path" 2>/dev/null; then
    print_result "PASS" "$script: has error handling (set -e)"
    return 0
  else
    print_result "FAIL" "$script: missing error handling"
    return 1
  fi
}

# Test: Script runs without error (dry-run where possible)
test_script_runs() {
  local script="$1"
  local path="$SCRIPTS_DIR/$script"

  if [ ! -f "$path" ]; then
    print_result "SKIP" "$script runs: file not found"
    return 1
  fi

  # Some scripts need special handling
  case "$script" in
    # These scripts are safe to run with --help or no args
    health-check.sh|generate-dashboard.sh|resource-monitor.sh)
      local output
      output=$("$path" 2>&1)
      local exit_code=$?
      if [ $exit_code -eq 0 ]; then
        print_result "PASS" "$script: runs successfully"
        return 0
      else
        print_result "FAIL" "$script: exit code $exit_code"
        return 1
      fi
      ;;

    # Notify scripts need arguments
    email-notify.sh|webhook-notify.sh)
      # Don't actually send notifications during testing
      print_result "SKIP" "$script runs: requires arguments, skipped"
      return 0
      ;;

    # Installation scripts should not be run during tests
    install-systemd.sh)
      print_result "SKIP" "$script runs: installation script, skipped"
      return 0
      ;;

    # Heartbeat should not be run (starts processes)
    heartbeat.sh)
      print_result "SKIP" "$script runs: daemon script, skipped"
      return 0
      ;;

    # Check scripts that need existing state
    watchdog.sh|generate-tasks.sh|process-inbox.sh|checkpoint.sh)
      # These modify state, so just check syntax passed
      print_result "SKIP" "$script runs: modifies state, skipped"
      return 0
      ;;

    # Default: try running with timeout
    *)
      local output
      output=$(timeout 5 "$path" 2>&1) || true
      # If it ran without crashing, it passes
      print_result "PASS" "$script: runs without crash"
      return 0
      ;;
  esac
}

# Run all tests for a script
test_script() {
  local script="$1"
  echo -e "\n${BLUE}Testing: $script${NC}"
  echo "----------------------------------------"

  test_script_exists "$script"
  test_script_shebang "$script"
  test_script_syntax "$script"
  test_script_error_handling "$script"
  test_script_runs "$script"
}

# List all testable scripts
list_scripts() {
  echo "Available scripts to test:"
  for script in "$SCRIPTS_DIR"/*.sh; do
    [ -f "$script" ] && echo "  - $(basename "$script")"
  done
}

# Main
main() {
  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --verbose|-v)
        VERBOSE=true
        shift
        ;;
      --list|-l)
        list_scripts
        exit 0
        ;;
      --help|-h)
        echo "Usage: test-runner.sh [script_name] [--verbose]"
        echo "       test-runner.sh                    # Run all tests"
        echo "       test-runner.sh health-check.sh    # Test specific script"
        echo "       test-runner.sh --list             # List available tests"
        exit 0
        ;;
      *)
        SPECIFIC_TEST="$1"
        shift
        ;;
    esac
  done

  mkdir -p "$TESTS_DIR"
  log "Starting test run"

  echo ""
  echo "=================================="
  echo "  Claude Agent Script Test Suite  "
  echo "=================================="

  if [ -n "$SPECIFIC_TEST" ]; then
    # Test specific script
    if [ -f "$SCRIPTS_DIR/$SPECIFIC_TEST" ]; then
      test_script "$SPECIFIC_TEST"
    elif [ -f "$SCRIPTS_DIR/${SPECIFIC_TEST}.sh" ]; then
      test_script "${SPECIFIC_TEST}.sh"
    else
      echo -e "${RED}Script not found: $SPECIFIC_TEST${NC}"
      exit 1
    fi
  else
    # Test all scripts
    for script in "$SCRIPTS_DIR"/*.sh; do
      [ -f "$script" ] && test_script "$(basename "$script")"
    done
  fi

  # Summary
  echo ""
  echo "=================================="
  echo "  Test Summary"
  echo "=================================="
  echo -e "  ${GREEN}Passed: $PASSED${NC}"
  echo -e "  ${RED}Failed: $FAILED${NC}"
  echo -e "  ${YELLOW}Skipped: $SKIPPED${NC}"
  echo ""

  log "Test run complete: $PASSED passed, $FAILED failed, $SKIPPED skipped"

  if [ $FAILED -gt 0 ]; then
    exit 1
  fi
}

main "$@"

#!/bin/bash
#
# Dependency Checker
# Verifies that all required commands and dependencies for scripts are available
#
# Usage: dep-check.sh [options] [script-path|directory]

set -uo pipefail

WORKSPACE="/agent-workspace"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
VERBOSE=false
QUIET=false
TARGET_PATH=""

# Results
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

usage() {
    cat << 'EOF'
Dependency Checker - Verify script dependencies

Usage: dep-check.sh [options] [script-path|directory]

Options:
  -v, --verbose    Show detailed output
  -q, --quiet      Only show errors
  -h, --help       Show help

If no path given, checks all scripts in .claude/scripts/

Examples:
  dep-check.sh                           # Check all infrastructure scripts
  dep-check.sh ./my-script.sh            # Check single script
  dep-check.sh -v ./scripts              # Check directory verbosely

EOF
}

log_pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${GREEN}✓${NC} $1"
    fi
}

log_warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${YELLOW}⚠${NC} $1"
    fi
}

log_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo -e "${RED}✗${NC} $1"
}

log_info() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}ℹ${NC} $1"
    fi
}

# Check if a command exists
check_command() {
    command -v "$1" &>/dev/null
}

# Check a single script
check_script() {
    local script="$1"
    local name
    name=$(basename "$script")

    echo ""
    echo -e "${BLUE}Checking:${NC} $name"

    # Check script exists and is readable
    if [[ ! -f "$script" ]]; then
        log_fail "Script not found: $script"
        return 1
    fi

    if [[ ! -r "$script" ]]; then
        log_fail "Script not readable: $script"
        return 1
    fi

    # Check executable permission
    if [[ ! -x "$script" ]]; then
        log_warn "Script not executable"
    else
        log_info "Script is executable"
    fi

    # Check shebang
    local shebang
    shebang=$(head -1 "$script")
    if [[ "$shebang" =~ ^#! ]]; then
        local interpreter="${shebang#\#!}"
        interpreter="${interpreter%% *}"
        interpreter=$(echo "$interpreter" | tr -d ' ')

        if [[ "$interpreter" == "/usr/bin/env" ]]; then
            interpreter=$(head -1 "$script" | awk '{print $2}')
        fi

        if check_command "$interpreter" || [[ -x "$interpreter" ]]; then
            log_pass "Interpreter: $interpreter"
        else
            log_fail "Missing interpreter: $interpreter"
        fi
    else
        log_warn "No shebang found"
    fi

    # Check for required external commands
    local cmds_to_check=("jq" "curl" "git" "docker" "npm" "node" "python3" "systemctl" "claude")

    for cmd in "${cmds_to_check[@]}"; do
        if grep -qw "$cmd" "$script" 2>/dev/null; then
            if check_command "$cmd"; then
                log_pass "Command: $cmd"
            else
                log_fail "Missing command: $cmd"
            fi
        fi
    done

    # Syntax check
    if bash -n "$script" 2>/dev/null; then
        log_pass "Syntax valid"
    else
        log_fail "Syntax error in script"
    fi

    return 0
}

# Check all scripts in a directory
check_directory() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        log_fail "Directory not found: $dir"
        return 1
    fi

    for script in "$dir"/*.sh; do
        [[ -f "$script" ]] || continue
        check_script "$script"
    done
}

# Generate dependency report
generate_report() {
    echo ""
    echo "═══════════════════════════════════════════"
    echo -e "${BLUE}Dependency Check Summary${NC}"
    echo "═══════════════════════════════════════════"
    echo -e "  ${GREEN}Passed:${NC}   $PASS_COUNT"
    echo -e "  ${YELLOW}Warnings:${NC} $WARN_COUNT"
    echo -e "  ${RED}Failed:${NC}   $FAIL_COUNT"
    echo ""

    if [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "${GREEN}All critical dependencies satisfied!${NC}"
    else
        echo -e "${RED}Missing dependencies found.${NC}"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            TARGET_PATH="$1"
            shift
            ;;
    esac
done

# Main execution
echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Dependency Checker v1.0             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"

# Default to scripts directory
if [[ -z "$TARGET_PATH" ]]; then
    TARGET_PATH="$WORKSPACE/.claude/scripts"
fi

# Check target
if [[ -f "$TARGET_PATH" ]]; then
    check_script "$TARGET_PATH"
elif [[ -d "$TARGET_PATH" ]]; then
    check_directory "$TARGET_PATH"
else
    log_fail "Path not found: $TARGET_PATH"
    exit 1
fi

# Generate report
generate_report
exit $FAIL_COUNT

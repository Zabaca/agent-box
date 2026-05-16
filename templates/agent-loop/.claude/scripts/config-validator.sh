#!/bin/bash
#
# Config Validator
# Validates all configuration files and settings for the agent infrastructure
#
# Usage: config-validator.sh [options]
#   --fix          Attempt to fix issues
#   -v, --verbose  Verbose output
#   -q, --quiet    Only show errors
#   -h, --help     Show help

set -uo pipefail

WORKSPACE="/agent-workspace"
CLAUDE_DIR="$WORKSPACE/.claude"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Results
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# Options
VERBOSE=false
QUIET=false
FIX_ISSUES=false

usage() {
    cat << 'EOF'
Config Validator - Validate agent configuration files

Usage: config-validator.sh [options]

Options:
  --fix          Attempt to fix issues automatically
  -v, --verbose  Show detailed output
  -q, --quiet    Only show errors
  -h, --help     Show this help

Validates:
  - JSON files (syntax)
  - Markdown files (structure)
  - Required files exist
  - Directory structure
  - File permissions
  - Service configurations

Examples:
  config-validator.sh           # Run all validations
  config-validator.sh --fix     # Fix issues automatically
  config-validator.sh -v        # Verbose output

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

# Validate JSON file
validate_json() {
    local file="$1"
    local name
    name=$(basename "$file")

    if [[ ! -f "$file" ]]; then
        log_warn "JSON file not found: $name"
        return 1
    fi

    if jq empty "$file" 2>/dev/null; then
        log_pass "JSON valid: $name"
        return 0
    else
        log_fail "JSON invalid: $name"
        if [[ "$FIX_ISSUES" == "true" ]]; then
            log_info "Cannot auto-fix JSON syntax errors"
        fi
        return 1
    fi
}

# Validate markdown structure
validate_markdown() {
    local file="$1"
    local name
    name=$(basename "$file")

    if [[ ! -f "$file" ]]; then
        log_warn "Markdown file not found: $name"
        return 1
    fi

    # Check file is not empty
    if [[ ! -s "$file" ]]; then
        log_fail "Markdown empty: $name"
        return 1
    fi

    # Check has at least one header
    if grep -q '^#' "$file"; then
        log_pass "Markdown structure: $name"
        return 0
    else
        log_warn "Markdown has no headers: $name"
        return 1
    fi
}

# Validate required files exist
validate_required_files() {
    echo -e "\n${BLUE}Checking Required Files${NC}"
    echo "─────────────────────────────────────────"

    local required_files=(
        "$WORKSPACE/CLAUDE.md"
        "$CLAUDE_DIR/loop/memory.md"
        "$CLAUDE_DIR/loop/tasks.md"
        "$CLAUDE_DIR/loop/goals.md"
        "$CLAUDE_DIR/learnings.md"
    )

    for file in "${required_files[@]}"; do
        local name
        name=$(basename "$file")
        if [[ -f "$file" ]]; then
            log_pass "Required file exists: $name"
        else
            log_fail "Required file missing: $name"
            if [[ "$FIX_ISSUES" == "true" ]]; then
                touch "$file"
                log_info "Created empty file: $name"
            fi
        fi
    done
}

# Validate directory structure
validate_directories() {
    echo -e "\n${BLUE}Checking Directory Structure${NC}"
    echo "─────────────────────────────────────────"

    local required_dirs=(
        "$CLAUDE_DIR"
        "$CLAUDE_DIR/loop"
        "$CLAUDE_DIR/scripts"
        "$CLAUDE_DIR/hooks"
        "$CLAUDE_DIR/inbox"
        "$CLAUDE_DIR/notifications"
        "$CLAUDE_DIR/backups"
    )

    for dir in "${required_dirs[@]}"; do
        local name="${dir#$WORKSPACE/}"
        if [[ -d "$dir" ]]; then
            log_pass "Directory exists: $name"
        else
            log_fail "Directory missing: $name"
            if [[ "$FIX_ISSUES" == "true" ]]; then
                mkdir -p "$dir"
                log_info "Created directory: $name"
            fi
        fi
    done
}

# Validate JSON config files
validate_json_configs() {
    echo -e "\n${BLUE}Checking JSON Configurations${NC}"
    echo "─────────────────────────────────────────"

    local json_files=(
        "$CLAUDE_DIR/loop/state.json"
        "$CLAUDE_DIR/health.json"
        "$CLAUDE_DIR/loop/resource-state.json"
    )

    for file in "${json_files[@]}"; do
        if [[ -f "$file" ]]; then
            validate_json "$file"
        else
            log_info "Optional JSON not found: $(basename "$file")"
        fi
    done

    # Check Claude settings
    local settings_file="$HOME/.claude/settings.json"
    if [[ -f "$settings_file" ]]; then
        validate_json "$settings_file"
    else
        log_warn "Claude settings not found"
    fi
}

# Validate markdown files
validate_markdown_files() {
    echo -e "\n${BLUE}Checking Markdown Files${NC}"
    echo "─────────────────────────────────────────"

    validate_markdown "$WORKSPACE/CLAUDE.md"
    validate_markdown "$CLAUDE_DIR/loop/memory.md"
    validate_markdown "$CLAUDE_DIR/loop/tasks.md"
    validate_markdown "$CLAUDE_DIR/loop/goals.md"
    validate_markdown "$CLAUDE_DIR/learnings.md"
}

# Validate task file structure
validate_tasks_structure() {
    echo -e "\n${BLUE}Checking Tasks File Structure${NC}"
    echo "─────────────────────────────────────────"

    local tasks_file="$CLAUDE_DIR/loop/tasks.md"

    if [[ ! -f "$tasks_file" ]]; then
        log_fail "Tasks file missing"
        return 1
    fi

    # Check for required sections
    if grep -q "## Pending" "$tasks_file"; then
        log_pass "Tasks has Pending section"
    else
        log_fail "Tasks missing Pending section"
        if [[ "$FIX_ISSUES" == "true" ]]; then
            echo -e "\n## Pending\n" >> "$tasks_file"
            log_info "Added Pending section"
        fi
    fi

    if grep -q "## In Progress" "$tasks_file"; then
        log_pass "Tasks has In Progress section"
    else
        log_fail "Tasks missing In Progress section"
    fi

    if grep -q "## Completed" "$tasks_file"; then
        log_pass "Tasks has Completed section"
    else
        log_fail "Tasks missing Completed section"
    fi
}

# Validate script permissions
validate_script_permissions() {
    echo -e "\n${BLUE}Checking Script Permissions${NC}"
    echo "─────────────────────────────────────────"

    local scripts_dir="$CLAUDE_DIR/scripts"
    local issues=0

    if [[ ! -d "$scripts_dir" ]]; then
        log_fail "Scripts directory missing"
        return 1
    fi

    for script in "$scripts_dir"/*.sh; do
        [[ -f "$script" ]] || continue
        local name
        name=$(basename "$script")

        if [[ -x "$script" ]]; then
            log_info "Executable: $name"
        else
            log_warn "Not executable: $name"
            ((issues++))
            if [[ "$FIX_ISSUES" == "true" ]]; then
                chmod +x "$script"
                log_info "Made executable: $name"
            fi
        fi
    done

    if [[ $issues -eq 0 ]]; then
        log_pass "All scripts executable"
    fi
}

# Validate systemd service
validate_systemd() {
    echo -e "\n${BLUE}Checking Systemd Service${NC}"
    echo "─────────────────────────────────────────"

    if systemctl is-enabled claude-agent.timer &>/dev/null; then
        log_pass "Timer enabled: claude-agent.timer"
    else
        log_warn "Timer not enabled: claude-agent.timer"
    fi

    if systemctl is-active claude-agent.timer &>/dev/null; then
        log_pass "Timer active: claude-agent.timer"
    else
        log_warn "Timer not active: claude-agent.timer"
    fi
}

# Validate git configuration
validate_git() {
    echo -e "\n${BLUE}Checking Git Configuration${NC}"
    echo "─────────────────────────────────────────"

    if git -C "$WORKSPACE" rev-parse --git-dir &>/dev/null; then
        log_pass "Git repository initialized"
    else
        log_fail "Not a git repository"
        return 1
    fi

    # Check git user config
    local git_user
    git_user=$(git -C "$WORKSPACE" config user.name 2>/dev/null)
    if [[ -n "$git_user" ]]; then
        log_pass "Git user configured: $git_user"
    else
        log_warn "Git user not configured"
    fi

    # Check for uncommitted changes
    local changes
    changes=$(git -C "$WORKSPACE" status --porcelain 2>/dev/null | wc -l)
    if [[ $changes -gt 0 ]]; then
        log_info "Uncommitted changes: $changes files"
    else
        log_pass "Working tree clean"
    fi
}

# Validate hooks
validate_hooks() {
    echo -e "\n${BLUE}Checking Git Hooks${NC}"
    echo "─────────────────────────────────────────"

    local hooks_dir="$WORKSPACE/.git/hooks"

    if [[ ! -d "$hooks_dir" ]]; then
        log_warn "Git hooks directory not found"
        return 1
    fi

    local hook_count=0
    for hook in pre-commit commit-msg post-commit; do
        if [[ -x "$hooks_dir/$hook" ]]; then
            log_pass "Hook installed: $hook"
            ((hook_count++))
        else
            log_info "Hook not installed: $hook"
        fi
    done

    if [[ $hook_count -gt 0 ]]; then
        log_info "Total hooks: $hook_count"
    fi
}

# Validate environment
validate_environment() {
    echo -e "\n${BLUE}Checking Environment${NC}"
    echo "─────────────────────────────────────────"

    # Check required commands
    local required_cmds=("git" "jq" "bash" "node")

    for cmd in "${required_cmds[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            log_pass "Command available: $cmd"
        else
            log_fail "Command missing: $cmd"
        fi
    done

    # Check Claude CLI
    if command -v claude &>/dev/null; then
        log_pass "Claude CLI available"
    else
        log_warn "Claude CLI not found"
    fi
}

# Generate summary report
generate_report() {
    echo ""
    echo "═══════════════════════════════════════════"
    echo -e "${BLUE}Config Validation Summary${NC}"
    echo "═══════════════════════════════════════════"
    echo -e "  ${GREEN}Passed:${NC}   $PASS_COUNT"
    echo -e "  ${YELLOW}Warnings:${NC} $WARN_COUNT"
    echo -e "  ${RED}Failed:${NC}   $FAIL_COUNT"
    echo ""

    local total=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT))
    local score=$((PASS_COUNT * 100 / total))

    echo -e "Health Score: ${BLUE}${score}%${NC}"
    echo ""

    if [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "${GREEN}All critical validations passed!${NC}"
        return 0
    else
        echo -e "${RED}Found $FAIL_COUNT critical issues${NC}"
        if [[ "$FIX_ISSUES" != "true" ]]; then
            echo "Run with --fix to attempt automatic fixes"
        fi
        return 1
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --fix)
            FIX_ISSUES=true
            shift
            ;;
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
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main execution
echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Config Validator v1.0             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"

# Run all validations
validate_required_files
validate_directories
validate_json_configs
validate_markdown_files
validate_tasks_structure
validate_script_permissions
validate_systemd
validate_git
validate_hooks
validate_environment

# Generate report
generate_report
exit $FAIL_COUNT

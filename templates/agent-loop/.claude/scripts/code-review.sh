#!/bin/bash
#
# Code Review Helper
# Analyze git changes and provide review feedback
#
# Usage: code-review.sh <command> [options]
#   staged                    Review staged changes
#   branch [name]             Review changes on branch vs main
#   commit [ref]              Review specific commit
#   file <path>               Review changes in specific file
#   stats                     Show change statistics
#   checklist                 Generate review checklist
#   -h, --help                Show help

set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

usage() {
    cat << 'EOF'
Code Review Helper - Analyze git changes

Usage: code-review.sh <command> [options]

Commands:
  staged                    Review currently staged changes
  branch [name]             Review branch changes vs main/master
  commit [ref]              Review specific commit (default: HEAD)
  file <path>               Review changes for specific file
  pr <number>               Review PR changes (if using GitHub)
  stats                     Show detailed change statistics
  checklist                 Generate review checklist
  issues                    Scan for common issues in changes

Options:
  --base <ref>              Base ref for comparison (default: main/master)
  --format <type>           Output format: text, json, markdown
  -v, --verbose             Show more details
  -h, --help                Show this help

Review Checks:
  - Security patterns (hardcoded secrets, SQL injection, etc.)
  - Code style (large functions, complex logic)
  - Best practices (error handling, logging)
  - Testing (test coverage for changed code)

Examples:
  code-review.sh staged               # Review what's staged
  code-review.sh branch feature/auth  # Review feature branch
  code-review.sh commit HEAD~3        # Review 3 commits ago
  code-review.sh stats                # Show change statistics
  code-review.sh issues               # Find potential issues
EOF
}

# Detect main branch
get_main_branch() {
    if git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
        echo "main"
    elif git show-ref --verify --quiet refs/heads/master 2>/dev/null; then
        echo "master"
    else
        echo "HEAD"
    fi
}

# Get diff for analysis
get_diff() {
    local mode="$1"
    shift

    case "$mode" in
        staged)
            git diff --cached
            ;;
        branch)
            local branch="${1:-$(git branch --show-current)}"
            local base="${2:-$(get_main_branch)}"
            git diff "$base...$branch"
            ;;
        commit)
            local ref="${1:-HEAD}"
            git show "$ref" --format=""
            ;;
        file)
            local path="$1"
            git diff -- "$path"
            ;;
    esac
}

# Get file stats
get_file_stats() {
    local mode="$1"
    shift

    case "$mode" in
        staged)
            git diff --cached --stat
            ;;
        branch)
            local branch="${1:-$(git branch --show-current)}"
            local base="${2:-$(get_main_branch)}"
            git diff "$base...$branch" --stat
            ;;
        commit)
            local ref="${1:-HEAD}"
            git show "$ref" --stat --format=""
            ;;
    esac
}

# Check for security issues
check_security() {
    local diff_content="$1"

    echo -e "${RED}Security Checks:${NC}"
    echo "────────────────────"

    local issues=0

    # Check for hardcoded secrets
    if echo "$diff_content" | grep -iE "(password|secret|api_key|apikey|token)\s*[:=]\s*['\"][^'\"]{8,}" > /dev/null 2>&1; then
        echo -e "  ${RED}⚠${NC}  Possible hardcoded secret detected"
        ((issues++))
    fi

    # Check for AWS keys
    if echo "$diff_content" | grep -E "AKIA[0-9A-Z]{16}" > /dev/null 2>&1; then
        echo -e "  ${RED}⚠${NC}  Possible AWS access key detected"
        ((issues++))
    fi

    # Check for private keys
    if echo "$diff_content" | grep -E "-----BEGIN (RSA |DSA |EC )?PRIVATE KEY-----" > /dev/null 2>&1; then
        echo -e "  ${RED}⚠${NC}  Private key detected in diff"
        ((issues++))
    fi

    # Check for SQL injection risks
    if echo "$diff_content" | grep -iE '\$.*\+.*[\"'\''](select|insert|update|delete|drop)' > /dev/null 2>&1; then
        echo -e "  ${YELLOW}⚠${NC}  Potential SQL injection pattern"
        ((issues++))
    fi

    # Check for eval usage
    if echo "$diff_content" | grep -E '^\+.*\beval\s*\(' > /dev/null 2>&1; then
        echo -e "  ${YELLOW}⚠${NC}  eval() usage detected - potential security risk"
        ((issues++))
    fi

    # Check for exec/system calls with variables
    if echo "$diff_content" | grep -E '^\+.*\b(exec|system|popen|subprocess)\s*\(' > /dev/null 2>&1; then
        echo -e "  ${YELLOW}⚠${NC}  Shell execution detected - verify input sanitization"
        ((issues++))
    fi

    if [[ $issues -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC}  No obvious security issues found"
    fi

    echo ""
    return $issues
}

# Check code quality
check_quality() {
    local diff_content="$1"

    echo -e "${YELLOW}Code Quality Checks:${NC}"
    echo "────────────────────"

    local issues=0

    # Check for large additions
    local lines_added
    lines_added=$(echo "$diff_content" | grep -c "^+" || echo 0)
    if [[ $lines_added -gt 500 ]]; then
        echo -e "  ${YELLOW}⚠${NC}  Large change: $lines_added lines added"
        echo "     Consider breaking into smaller commits"
        ((issues++))
    fi

    # Check for TODO/FIXME
    local todos
    todos=$(echo "$diff_content" | grep -c "^\+.*\(TODO\|FIXME\|HACK\|XXX\)" 2>/dev/null | head -1 || echo 0)
    todos=${todos:-0}
    if [[ "$todos" =~ ^[0-9]+$ ]] && [[ $todos -gt 0 ]]; then
        echo -e "  ${CYAN}ℹ${NC}  $todos TODO/FIXME comments added"
    fi

    # Check for console.log / print statements
    local debug_stmts
    debug_stmts=$(echo "$diff_content" | grep -cE '^\+.*(console\.log|print\(|println|System\.out)' 2>/dev/null | head -1 || echo 0)
    debug_stmts=${debug_stmts:-0}
    if [[ "$debug_stmts" =~ ^[0-9]+$ ]] && [[ $debug_stmts -gt 0 ]]; then
        echo -e "  ${YELLOW}⚠${NC}  $debug_stmts debug statements added"
        ((issues++))
    fi

    # Check for commented out code
    local commented
    commented=$(echo "$diff_content" | grep -cE '^\+\s*(//|#)\s*(if|for|while|function|def|class)' 2>/dev/null | head -1 || echo 0)
    commented=${commented:-0}
    if [[ "$commented" =~ ^[0-9]+$ ]] && [[ $commented -gt 0 ]]; then
        echo -e "  ${YELLOW}⚠${NC}  Commented-out code detected"
        ((issues++))
    fi

    # Check for long lines
    local long_lines
    long_lines=$(echo "$diff_content" | grep -c "^+.\{120\}" || echo 0)
    if [[ $long_lines -gt 5 ]]; then
        echo -e "  ${YELLOW}⚠${NC}  $long_lines lines exceed 120 characters"
        ((issues++))
    fi

    if [[ $issues -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC}  Code quality looks good"
    fi

    echo ""
    return $issues
}

# Check for testing
check_testing() {
    local diff_content="$1"

    echo -e "${BLUE}Testing Analysis:${NC}"
    echo "────────────────────"

    # Check if tests were modified
    local test_changes
    test_changes=$(echo "$diff_content" | grep -cE '^(\+\+\+|---).*(test|spec|_test\.|\.test\.)' || echo 0)

    if [[ $test_changes -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC}  Test files were modified"
    else
        # Check if code was added
        local code_added
        code_added=$(echo "$diff_content" | grep -cE '^(\+\+\+|---).*\.(js|ts|py|go|rs|java|rb|sh)$' || echo 0)
        if [[ $code_added -gt 0 ]]; then
            echo -e "  ${YELLOW}⚠${NC}  Code changed but no test updates"
        fi
    fi

    # Check for test assertions
    local assertions
    assertions=$(echo "$diff_content" | grep -cE '^\+.*(assert|expect|should|test\(|it\(|describe\()' 2>/dev/null | head -1 || echo 0)
    assertions=${assertions:-0}
    if [[ "$assertions" =~ ^[0-9]+$ ]] && [[ $assertions -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC}  $assertions test assertions/blocks added"
    fi

    echo ""
}

# Generate statistics
cmd_stats() {
    local mode="${1:-staged}"
    shift 2>/dev/null || true

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Change Statistics                                            ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local diff_content
    diff_content=$(get_diff "$mode" "$@" 2>/dev/null)

    if [[ -z "$diff_content" ]]; then
        echo "No changes to analyze"
        return
    fi

    # Overall stats
    local lines_added lines_removed files_changed
    lines_added=$(echo "$diff_content" | grep -c "^+" || echo 0)
    lines_removed=$(echo "$diff_content" | grep -c "^-" || echo 0)
    files_changed=$(echo "$diff_content" | grep -c "^diff --git" || echo 0)

    echo "Summary:"
    echo -e "  Files changed: ${CYAN}$files_changed${NC}"
    echo -e "  Lines added:   ${GREEN}+$lines_added${NC}"
    echo -e "  Lines removed: ${RED}-$lines_removed${NC}"
    echo ""

    # Per-file breakdown
    echo "File Details:"
    get_file_stats "$mode" "$@" 2>/dev/null | head -20

    # Language breakdown
    echo ""
    echo "Languages:"
    echo "$diff_content" | grep "^+++ " | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -10 | while read count ext; do
        echo "  $ext: $count file(s)"
    done
}

# Generate checklist
cmd_checklist() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Code Review Checklist                                        ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    cat << 'CHECKLIST'
## General
- [ ] Code follows project style guidelines
- [ ] No unnecessary changes included
- [ ] Commit message is clear and descriptive

## Functionality
- [ ] Code does what it's supposed to do
- [ ] Edge cases are handled
- [ ] Error handling is appropriate

## Security
- [ ] No hardcoded secrets or credentials
- [ ] Input validation is present
- [ ] No SQL injection vulnerabilities
- [ ] No XSS vulnerabilities (for web)

## Performance
- [ ] No obvious performance issues
- [ ] No unnecessary loops or iterations
- [ ] Database queries are efficient

## Testing
- [ ] Tests are included for new code
- [ ] Tests pass locally
- [ ] Edge cases are tested

## Documentation
- [ ] Code is self-documenting or has comments
- [ ] API changes are documented
- [ ] README updated if needed

## Dependencies
- [ ] New dependencies are justified
- [ ] Dependencies are up to date
- [ ] No security vulnerabilities in dependencies
CHECKLIST
}

# Scan for issues
cmd_issues() {
    local mode="${1:-staged}"
    shift 2>/dev/null || true

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Issue Scanner                                                ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local diff_content
    diff_content=$(get_diff "$mode" "$@" 2>/dev/null)

    if [[ -z "$diff_content" ]]; then
        echo "No changes to analyze"
        return
    fi

    check_security "$diff_content"
    check_quality "$diff_content"
    check_testing "$diff_content"
}

# Review staged changes
cmd_staged() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Reviewing Staged Changes                                     ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local diff_content
    diff_content=$(git diff --cached 2>/dev/null)

    if [[ -z "$diff_content" ]]; then
        echo "No staged changes to review"
        return
    fi

    # Show file stats
    echo -e "${CYAN}Changed Files:${NC}"
    git diff --cached --stat
    echo ""

    # Run checks
    check_security "$diff_content"
    check_quality "$diff_content"
    check_testing "$diff_content"

    # Summary
    echo -e "${GREEN}Review Complete${NC}"
    echo "Run 'git diff --cached' to see full diff"
}

# Review branch
cmd_branch() {
    local branch="${1:-$(git branch --show-current)}"
    local base="${2:-$(get_main_branch)}"

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Reviewing Branch: $branch"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Comparing to: ${CYAN}$base${NC}"
    echo ""

    local diff_content
    diff_content=$(git diff "$base...$branch" 2>/dev/null)

    if [[ -z "$diff_content" ]]; then
        echo "No changes between $base and $branch"
        return
    fi

    # Show commits
    echo -e "${CYAN}Commits:${NC}"
    git log --oneline "$base..$branch" | head -10
    echo ""

    # Show file stats
    echo -e "${CYAN}Changed Files:${NC}"
    git diff "$base...$branch" --stat
    echo ""

    # Run checks
    check_security "$diff_content"
    check_quality "$diff_content"
    check_testing "$diff_content"
}

# Review specific commit
cmd_commit() {
    local ref="${1:-HEAD}"

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Reviewing Commit: $ref"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Show commit info
    git show "$ref" --format="Author: %an <%ae>%nDate: %ai%nMessage: %s%n" --no-patch
    echo ""

    local diff_content
    diff_content=$(git show "$ref" --format="" 2>/dev/null)

    if [[ -z "$diff_content" ]]; then
        echo "No changes in commit"
        return
    fi

    # Show file stats
    echo -e "${CYAN}Changed Files:${NC}"
    git show "$ref" --stat --format=""
    echo ""

    # Run checks
    check_security "$diff_content"
    check_quality "$diff_content"
    check_testing "$diff_content"
}

# Review specific file
cmd_file() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        echo -e "${RED}Error:${NC} File not found: $path"
        return 1
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Reviewing File: $path"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local diff_content
    diff_content=$(git diff -- "$path" 2>/dev/null)

    if [[ -z "$diff_content" ]]; then
        diff_content=$(git diff --cached -- "$path" 2>/dev/null)
    fi

    if [[ -z "$diff_content" ]]; then
        echo "No uncommitted changes in $path"
        return
    fi

    # Show diff preview
    echo -e "${CYAN}Changes:${NC}"
    git diff -- "$path" | head -30
    echo ""

    # Run checks
    check_security "$diff_content"
    check_quality "$diff_content"
}

# Main command dispatch
BASE_REF=""
FORMAT="text"
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --base)
            BASE_REF="$2"
            shift 2
            ;;
        --format)
            FORMAT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        staged|branch|commit|file|stats|checklist|issues)
            CMD="$1"
            shift
            break
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

case "${CMD:-staged}" in
    staged)
        cmd_staged
        ;;
    branch)
        cmd_branch "$@"
        ;;
    commit)
        cmd_commit "$@"
        ;;
    file)
        if [[ $# -lt 1 ]]; then
            echo "Usage: code-review.sh file <path>"
            exit 1
        fi
        cmd_file "$1"
        ;;
    stats)
        cmd_stats "$@"
        ;;
    checklist)
        cmd_checklist
        ;;
    issues)
        cmd_issues "$@"
        ;;
    *)
        usage
        ;;
esac

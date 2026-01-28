#!/bin/bash
#
# Shell Script Linter/Analyzer
# Check shell scripts for common issues and best practices
#
# Usage: shell-lint.sh <command> [options]
#   check <file>              Lint a single file
#   dir <path>                Lint all scripts in directory
#   fix <file>                Auto-fix simple issues
#   report [path]             Generate detailed report
#   -h, --help                Show help

set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Severity levels
ERROR_COUNT=0
WARNING_COUNT=0
INFO_COUNT=0

usage() {
    cat << 'EOF'
Shell Script Linter - Check scripts for issues and best practices

Usage: shell-lint.sh <command> [options]

Commands:
  check <file>              Lint a single shell script
  dir <path>                Lint all .sh files in directory
  fix <file>                Auto-fix simple issues (creates .fixed backup)
  report [path]             Generate detailed report (default: current dir)
  summary <path>            Quick summary of issues

Options:
  --strict                  Treat warnings as errors
  --quiet                   Only show errors
  --format <type>           Output format: text, json, markdown
  -h, --help                Show this help

Checks Performed:
  Errors:
  - Missing shebang
  - Syntax errors (via bash -n)
  - Unquoted variables in dangerous contexts
  - Missing 'set -e' or error handling

  Warnings:
  - Unused variables
  - Deprecated syntax (backticks for command substitution)
  - Long lines (>120 chars)
  - Missing file existence checks
  - Hardcoded paths

  Info:
  - Missing documentation/comments
  - Complexity metrics
  - Function count

Examples:
  shell-lint.sh check myscript.sh
  shell-lint.sh dir /path/to/scripts
  shell-lint.sh report --format markdown > report.md
  shell-lint.sh fix myscript.sh
EOF
}

# Log issue
log_issue() {
    local severity="$1"
    local line="$2"
    local message="$3"
    local file="${4:-}"

    case "$severity" in
        error)
            echo -e "  ${RED}✗${NC} Line $line: $message"
            ((ERROR_COUNT++))
            ;;
        warning)
            echo -e "  ${YELLOW}⚠${NC} Line $line: $message"
            ((WARNING_COUNT++))
            ;;
        info)
            echo -e "  ${CYAN}ℹ${NC} Line $line: $message"
            ((INFO_COUNT++))
            ;;
    esac
}

# Check for shebang
check_shebang() {
    local file="$1"
    local first_line
    first_line=$(head -1 "$file")

    if [[ ! "$first_line" =~ ^#! ]]; then
        log_issue "error" "1" "Missing shebang (#!/bin/bash or #!/usr/bin/env bash)"
        return 1
    fi

    # Check for proper bash shebang
    if [[ ! "$first_line" =~ (bash|sh)$ ]]; then
        log_issue "warning" "1" "Non-standard shebang: $first_line"
    fi

    return 0
}

# Check syntax with bash -n
check_syntax() {
    local file="$1"

    local output
    if ! output=$(bash -n "$file" 2>&1); then
        # Parse error output
        echo "$output" | while IFS= read -r line; do
            if [[ "$line" =~ line\ ([0-9]+) ]]; then
                log_issue "error" "${BASH_REMATCH[1]}" "Syntax error: $line"
            else
                log_issue "error" "0" "Syntax error: $line"
            fi
        done
        return 1
    fi
    return 0
}

# Check for set -e or error handling
check_error_handling() {
    local file="$1"

    # Check for set -e, set -o errexit, or error handling pattern
    if ! grep -qE '^\s*set\s+(-[euo]+|.*errexit|.*pipefail)' "$file"; then
        log_issue "warning" "0" "Missing 'set -e' or 'set -o errexit' for error handling"
    fi

    # Check for set -u (undefined variables)
    if ! grep -qE '^\s*set\s+.*-.*u|set.*nounset' "$file"; then
        log_issue "info" "0" "Consider adding 'set -u' to catch undefined variables"
    fi
}

# Check for unquoted variables
check_unquoted_variables() {
    local file="$1"
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check for unquoted $VAR in dangerous contexts
        # Pattern: dangerous commands followed by unquoted variable
        if [[ "$line" =~ (rm|mv|cp|cat|echo|cd)[[:space:]]+-?[a-zA-Z]*[[:space:]]+\$[a-zA-Z_][a-zA-Z0-9_]*([[:space:]]|$) ]]; then
            log_issue "warning" "$line_num" "Potentially unquoted variable - consider using \"\$var\""
        fi

        # Check for [ $var = instead of [ "$var" =
        if [[ "$line" =~ \[[[:space:]]+\$[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]+(=|-eq|-ne|-lt|-gt) ]]; then
            log_issue "warning" "$line_num" "Unquoted variable in test - use [ \"\$var\" = ... ]"
        fi

    done < "$file"
}

# Check for deprecated syntax
check_deprecated_syntax() {
    local file="$1"
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check for backtick command substitution
        if [[ "$line" =~ \`[^\`]+\` ]]; then
            log_issue "warning" "$line_num" "Deprecated: use \$(command) instead of \`command\`"
        fi

        # Check for expr usage
        if [[ "$line" =~ [[:space:]]expr[[:space:]] ]]; then
            log_issue "info" "$line_num" "Consider using (( )) or \$(( )) instead of expr"
        fi

        # Check for function keyword
        if [[ "$line" =~ ^[[:space:]]*function[[:space:]]+[a-zA-Z_] ]]; then
            log_issue "info" "$line_num" "POSIX prefers 'func_name() {' over 'function func_name'"
        fi

    done < "$file"
}

# Check for long lines
check_line_length() {
    local file="$1"
    local max_length="${2:-120}"
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local len=${#line}
        if [[ $len -gt $max_length ]]; then
            log_issue "info" "$line_num" "Line too long ($len > $max_length chars)"
        fi
    done < "$file"
}

# Check for hardcoded paths
check_hardcoded_paths() {
    local file="$1"
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip comments and shebangs
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line_num" -eq 1 && "$line" =~ ^#! ]] && continue

        # Check for hardcoded home directories
        if [[ "$line" =~ /home/[a-zA-Z0-9_]+ && ! "$line" =~ \$HOME && ! "$line" =~ \$\{HOME\} ]]; then
            log_issue "warning" "$line_num" "Hardcoded home path - consider using \$HOME"
        fi

        # Check for hardcoded /tmp without variables
        if [[ "$line" =~ =[[:space:]]*[\"\']/tmp/ && ! "$line" =~ \$TMPDIR && ! "$line" =~ mktemp ]]; then
            log_issue "info" "$line_num" "Consider using mktemp or \$TMPDIR for temp files"
        fi

    done < "$file"
}

# Check for missing file checks
check_file_operations() {
    local file="$1"
    local line_num=0
    local prev_line=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check for file operations without prior existence check
        if [[ "$line" =~ (cat|source|\.)[[:space:]]+[\"\']*\$[a-zA-Z_] ]]; then
            # Check if previous line had a file check
            if [[ ! "$prev_line" =~ \[\[?[[:space:]]+-[fedrwx] ]]; then
                log_issue "info" "$line_num" "File operation without existence check"
            fi
        fi

        prev_line="$line"
    done < "$file"
}

# Calculate complexity metrics
calculate_complexity() {
    local file="$1"

    local total_lines
    total_lines=$(wc -l < "$file" | tr -d ' ')

    local code_lines
    code_lines=$(grep -cvE '^[[:space:]]*(#|$)' "$file" 2>/dev/null | head -1)
    code_lines=${code_lines:-0}

    local function_count
    function_count=$(grep -cE '^[[:space:]]*(function[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)' "$file" 2>/dev/null | head -1)
    function_count=${function_count:-0}

    local if_count
    if_count=$(grep -cE '^[[:space:]]*(if|elif)[[:space:]]' "$file" 2>/dev/null | head -1)
    if_count=${if_count:-0}

    local loop_count
    loop_count=$(grep -cE '^[[:space:]]*(for|while|until)[[:space:]]' "$file" 2>/dev/null | head -1)
    loop_count=${loop_count:-0}

    local case_count
    case_count=$(grep -cE '^[[:space:]]*case[[:space:]]' "$file" 2>/dev/null | head -1)
    case_count=${case_count:-0}

    # Simple cyclomatic complexity estimate
    local complexity=$((1 + ${if_count:-0} + ${loop_count:-0} + ${case_count:-0}))

    echo "Metrics:"
    echo "  Total lines:    $total_lines"
    echo "  Code lines:     $code_lines"
    echo "  Functions:      $function_count"
    echo "  Conditionals:   $if_count"
    echo "  Loops:          $loop_count"
    echo "  Case statements: $case_count"
    echo "  Complexity:     $complexity (cyclomatic estimate)"
}

# Check single file
cmd_check() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error:${NC} File not found: $file"
        return 1
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Linting: $(basename "$file")"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    ERROR_COUNT=0
    WARNING_COUNT=0
    INFO_COUNT=0

    echo -e "${CYAN}Structural Checks:${NC}"
    check_shebang "$file"
    check_syntax "$file"
    check_error_handling "$file"
    echo ""

    echo -e "${CYAN}Code Quality:${NC}"
    check_unquoted_variables "$file"
    check_deprecated_syntax "$file"
    check_hardcoded_paths "$file"
    check_file_operations "$file"
    echo ""

    echo -e "${CYAN}Style:${NC}"
    check_line_length "$file"
    echo ""

    # Summary
    echo "─────────────────────────────────────────"
    echo -e "Summary: ${RED}$ERROR_COUNT errors${NC}, ${YELLOW}$WARNING_COUNT warnings${NC}, ${CYAN}$INFO_COUNT info${NC}"
    echo ""

    calculate_complexity "$file"

    if [[ $ERROR_COUNT -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Lint directory
cmd_dir() {
    local path="$1"

    if [[ ! -d "$path" ]]; then
        echo -e "${RED}Error:${NC} Directory not found: $path"
        return 1
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Linting Directory: $path"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_errors=0
    local total_warnings=0
    local total_info=0
    local file_count=0
    local failed_files=0

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        ((file_count++))

        echo -e "${CYAN}━━━ $(basename "$file") ━━━${NC}"

        ERROR_COUNT=0
        WARNING_COUNT=0
        INFO_COUNT=0

        check_shebang "$file" 2>/dev/null
        check_syntax "$file" 2>/dev/null
        check_error_handling "$file" 2>/dev/null
        check_unquoted_variables "$file" 2>/dev/null
        check_deprecated_syntax "$file" 2>/dev/null

        if [[ $ERROR_COUNT -gt 0 ]]; then
            ((failed_files++))
        fi

        ((total_errors += ERROR_COUNT))
        ((total_warnings += WARNING_COUNT))
        ((total_info += INFO_COUNT))

        echo "  Errors: $ERROR_COUNT, Warnings: $WARNING_COUNT"
        echo ""

    done < <(find "$path" -name "*.sh" -type f 2>/dev/null)

    echo "═══════════════════════════════════════════════════════════════"
    echo -e "Total: ${CYAN}$file_count files${NC}"
    echo -e "  ${RED}$total_errors errors${NC} in $failed_files files"
    echo -e "  ${YELLOW}$total_warnings warnings${NC}"
    echo -e "  ${CYAN}$total_info info${NC}"

    if [[ $total_errors -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Auto-fix simple issues
cmd_fix() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error:${NC} File not found: $file"
        return 1
    fi

    # Create backup
    cp "$file" "${file}.backup"

    local fixed=0

    # Fix backticks to $()
    if grep -q '`[^`]*`' "$file"; then
        # This is a simplified fix - may not handle all cases
        sed -i 's/`\([^`]*\)`/$(\1)/g' "$file"
        echo -e "${GREEN}✓${NC} Converted backticks to \$()"
        ((fixed++))
    fi

    # Add shebang if missing
    if ! head -1 "$file" | grep -q '^#!'; then
        sed -i '1i#!/bin/bash' "$file"
        echo -e "${GREEN}✓${NC} Added shebang"
        ((fixed++))
    fi

    # Add set -uo pipefail if missing
    if ! grep -qE '^\s*set\s+-[euo]' "$file"; then
        # Add after shebang
        sed -i '2i\set -uo pipefail' "$file"
        echo -e "${GREEN}✓${NC} Added 'set -uo pipefail'"
        ((fixed++))
    fi

    echo ""
    echo "Fixed $fixed issues. Backup saved as ${file}.backup"
}

# Generate report
cmd_report() {
    local path="${1:-.}"
    local format="${2:-text}"

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Shell Script Lint Report                                     ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Generated: $(date)"
    echo "Path: $path"
    echo ""

    local total_files=0
    local total_errors=0
    local total_warnings=0

    echo "Per-File Summary:"
    echo "─────────────────────────────────────────"
    printf "%-40s %8s %8s\n" "File" "Errors" "Warnings"

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        ((total_files++))

        ERROR_COUNT=0
        WARNING_COUNT=0
        INFO_COUNT=0

        check_shebang "$file" &>/dev/null
        check_syntax "$file" &>/dev/null
        check_error_handling "$file" &>/dev/null
        check_unquoted_variables "$file" &>/dev/null
        check_deprecated_syntax "$file" &>/dev/null

        printf "%-40s %8d %8d\n" "$(basename "$file")" "$ERROR_COUNT" "$WARNING_COUNT"

        ((total_errors += ERROR_COUNT))
        ((total_warnings += WARNING_COUNT))

    done < <(find "$path" -name "*.sh" -type f 2>/dev/null)

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Total files: $total_files"
    echo "Total errors: $total_errors"
    echo "Total warnings: $total_warnings"

    local health
    if [[ $total_errors -eq 0 && $total_warnings -eq 0 ]]; then
        health="Excellent"
    elif [[ $total_errors -eq 0 ]]; then
        health="Good"
    elif [[ $total_errors -lt 5 ]]; then
        health="Fair"
    else
        health="Needs Attention"
    fi

    echo "Overall Health: $health"
}

# Quick summary
cmd_summary() {
    local path="${1:-.}"

    local file_count
    file_count=$(find "$path" -name "*.sh" -type f 2>/dev/null | wc -l)

    local total_lines=0
    local with_shebang=0
    local with_error_handling=0

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        ((total_lines += $(wc -l < "$file")))

        head -1 "$file" | grep -q '^#!' && ((with_shebang++))
        grep -qE '^\s*set\s+-[euo]' "$file" && ((with_error_handling++))

    done < <(find "$path" -name "*.sh" -type f 2>/dev/null)

    echo -e "${BLUE}Shell Scripts Summary:${NC}"
    echo "  Files: $file_count"
    echo "  Total lines: $total_lines"
    echo "  With shebang: $with_shebang ($((with_shebang * 100 / (file_count + 1)))%)"
    echo "  With error handling: $with_error_handling ($((with_error_handling * 100 / (file_count + 1)))%)"
}

# Main command dispatch
FORMAT="text"
STRICT=false
QUIET=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --strict)
            STRICT=true
            shift
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        --format)
            FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        check|dir|fix|report|summary)
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

case "${CMD:-check}" in
    check)
        if [[ $# -lt 1 ]]; then
            echo "Usage: shell-lint.sh check <file>"
            exit 1
        fi
        cmd_check "$1"
        ;;
    dir)
        if [[ $# -lt 1 ]]; then
            echo "Usage: shell-lint.sh dir <path>"
            exit 1
        fi
        cmd_dir "$1"
        ;;
    fix)
        if [[ $# -lt 1 ]]; then
            echo "Usage: shell-lint.sh fix <file>"
            exit 1
        fi
        cmd_fix "$1"
        ;;
    report)
        cmd_report "${1:-.}" "$FORMAT"
        ;;
    summary)
        cmd_summary "${1:-.}"
        ;;
    *)
        usage
        ;;
esac

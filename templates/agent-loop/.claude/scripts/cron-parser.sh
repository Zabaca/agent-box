#!/bin/bash
#
# Cron Expression Parser and Validator
# Parse, validate, and explain cron expressions
#
# Usage: cron-parser.sh [options] <cron-expression>
#   -v, --validate    Validate only (exit 0 if valid, 1 if invalid)
#   -n, --next N      Show next N scheduled times (default: 5)
#   -e, --explain     Explain the expression in plain English
#   --json            Output as JSON
#   -h, --help        Show help
#
# Supports standard 5-field cron format:
#   minute hour day-of-month month day-of-week
#
# Examples:
#   cron-parser.sh "*/5 * * * *"      # Every 5 minutes
#   cron-parser.sh "0 9 * * 1-5"      # 9am weekdays
#   cron-parser.sh -n 10 "0 0 1 * *"  # Show next 10 runs

set -uo pipefail

# Defaults
VALIDATE_ONLY=false
SHOW_NEXT=5
EXPLAIN=true
OUTPUT_JSON=false
CRON_EXPR=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat << 'EOF'
Cron Expression Parser and Validator

Usage: cron-parser.sh [options] <cron-expression>

Options:
  -v, --validate    Validate only (exit 0/1)
  -n, --next N      Show next N scheduled times (default: 5)
  -e, --explain     Explain in plain English (default: on)
  --json            Output as JSON
  -h, --help        Show this help

Cron Format:
  ┌───────────── minute (0-59)
  │ ┌───────────── hour (0-23)
  │ │ ┌───────────── day of month (1-31)
  │ │ │ ┌───────────── month (1-12 or JAN-DEC)
  │ │ │ │ ┌───────────── day of week (0-6 or SUN-SAT, 0=Sunday)
  │ │ │ │ │
  * * * * *

Special Characters:
  *       Any value
  ,       List separator (1,3,5)
  -       Range (1-5)
  /       Step values (*/5 = every 5)

Common Patterns:
  */5 * * * *       Every 5 minutes
  0 * * * *         Every hour
  0 0 * * *         Daily at midnight
  0 9 * * 1-5       Weekdays at 9am
  0 0 1 * *         Monthly on the 1st
  0 0 * * 0         Weekly on Sunday

Examples:
  cron-parser.sh "*/15 * * * *"
  cron-parser.sh -n 10 "0 9 * * MON"
  cron-parser.sh --json "0 0 1 1 *"
EOF
}

# Validate a single cron field
validate_field() {
    local value="$1"
    local min="$2"
    local max="$3"
    local field_name="$4"

    # Handle wildcard
    if [[ "$value" == "*" ]]; then
        return 0
    fi

    # Handle step with wildcard (*/n)
    if [[ "$value" =~ ^\*/([0-9]+)$ ]]; then
        local step="${BASH_REMATCH[1]}"
        if [[ $step -lt 1 || $step -gt $max ]]; then
            echo "Invalid step value in $field_name: $step"
            return 1
        fi
        return 0
    fi

    # Handle list (1,2,3)
    if [[ "$value" == *","* ]]; then
        IFS=',' read -ra parts <<< "$value"
        for part in "${parts[@]}"; do
            if ! validate_field "$part" "$min" "$max" "$field_name"; then
                return 1
            fi
        done
        return 0
    fi

    # Handle range (1-5)
    if [[ "$value" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        if [[ $start -lt $min || $start -gt $max || $end -lt $min || $end -gt $max || $start -gt $end ]]; then
            echo "Invalid range in $field_name: $value"
            return 1
        fi
        return 0
    fi

    # Handle range with step (1-10/2)
    if [[ "$value" =~ ^([0-9]+)-([0-9]+)/([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        local step="${BASH_REMATCH[3]}"
        if [[ $start -lt $min || $end -gt $max || $start -gt $end || $step -lt 1 ]]; then
            echo "Invalid range/step in $field_name: $value"
            return 1
        fi
        return 0
    fi

    # Handle plain number
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        if [[ $value -lt $min || $value -gt $max ]]; then
            echo "Value out of range in $field_name: $value (must be $min-$max)"
            return 1
        fi
        return 0
    fi

    echo "Invalid format in $field_name: $value"
    return 1
}

# Convert month/day names to numbers
normalize_field() {
    local value="$1"
    local field_type="$2"

    # Convert month names
    if [[ "$field_type" == "month" ]]; then
        value="${value//JAN/1}"
        value="${value//FEB/2}"
        value="${value//MAR/3}"
        value="${value//APR/4}"
        value="${value//MAY/5}"
        value="${value//JUN/6}"
        value="${value//JUL/7}"
        value="${value//AUG/8}"
        value="${value//SEP/9}"
        value="${value//OCT/10}"
        value="${value//NOV/11}"
        value="${value//DEC/12}"
    fi

    # Convert day names
    if [[ "$field_type" == "dow" ]]; then
        value="${value//SUN/0}"
        value="${value//MON/1}"
        value="${value//TUE/2}"
        value="${value//WED/3}"
        value="${value//THU/4}"
        value="${value//FRI/5}"
        value="${value//SAT/6}"
    fi

    echo "$value"
}

# Validate entire cron expression
validate_cron() {
    local expr="$1"

    # Split into fields
    read -ra fields <<< "$expr"

    if [[ ${#fields[@]} -ne 5 ]]; then
        echo "Invalid cron expression: expected 5 fields, got ${#fields[@]}"
        return 1
    fi

    local minute="${fields[0]}"
    local hour="${fields[1]}"
    local dom="${fields[2]}"
    local month="${fields[3]}"
    local dow="${fields[4]}"

    # Normalize names to numbers
    month=$(normalize_field "$month" "month")
    dow=$(normalize_field "$dow" "dow")

    # Validate each field
    local errors=""
    errors+=$(validate_field "$minute" 0 59 "minute")
    errors+=$(validate_field "$hour" 0 23 "hour")
    errors+=$(validate_field "$dom" 1 31 "day-of-month")
    errors+=$(validate_field "$month" 1 12 "month")
    errors+=$(validate_field "$dow" 0 6 "day-of-week")

    if [[ -n "$errors" ]]; then
        echo "$errors"
        return 1
    fi

    return 0
}

# Explain a field in English
explain_field() {
    local value="$1"
    local field_name="$2"
    local unit="$3"

    if [[ "$value" == "*" ]]; then
        echo "every $unit"
        return
    fi

    if [[ "$value" =~ ^\*/([0-9]+)$ ]]; then
        echo "every ${BASH_REMATCH[1]} ${unit}s"
        return
    fi

    if [[ "$value" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        echo "${unit}s ${BASH_REMATCH[1]} through ${BASH_REMATCH[2]}"
        return
    fi

    if [[ "$value" == *","* ]]; then
        echo "${unit}s $value"
        return
    fi

    echo "at $unit $value"
}

# Generate human-readable explanation
explain_cron() {
    local expr="$1"
    read -ra fields <<< "$expr"

    local minute="${fields[0]}"
    local hour="${fields[1]}"
    local dom="${fields[2]}"
    local month="${fields[3]}"
    local dow="${fields[4]}"

    local explanation=""

    # Time explanation
    if [[ "$minute" == "0" && "$hour" == "*" ]]; then
        explanation="At the start of every hour"
    elif [[ "$minute" == "*" && "$hour" == "*" ]]; then
        explanation="Every minute"
    elif [[ "$minute" =~ ^\*/([0-9]+)$ && "$hour" == "*" ]]; then
        explanation="Every ${BASH_REMATCH[1]} minutes"
    elif [[ "$minute" =~ ^[0-9]+$ && "$hour" =~ ^[0-9]+$ ]]; then
        local h=$hour
        local ampm="AM"
        if [[ $h -ge 12 ]]; then
            ampm="PM"
            [[ $h -gt 12 ]] && h=$((h - 12))
        fi
        [[ $h -eq 0 ]] && h=12
        explanation="At $(printf '%d:%02d %s' "$h" "$minute" "$ampm")"
    elif [[ "$minute" =~ ^[0-9]+$ && "$hour" == "*" ]]; then
        explanation="At minute $minute of every hour"
    else
        explanation="At minute $minute, hour $hour"
    fi

    # Day of month
    if [[ "$dom" != "*" ]]; then
        if [[ "$dom" =~ ^[0-9]+$ ]]; then
            explanation+=", on day $dom of the month"
        else
            explanation+=", on days $dom of the month"
        fi
    fi

    # Month
    if [[ "$month" != "*" ]]; then
        local month_names=("" "January" "February" "March" "April" "May" "June" "July" "August" "September" "October" "November" "December")
        if [[ "$month" =~ ^[0-9]+$ ]]; then
            explanation+=", in ${month_names[$month]}"
        else
            explanation+=", in months $month"
        fi
    fi

    # Day of week
    if [[ "$dow" != "*" ]]; then
        local dow_names=("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday")
        if [[ "$dow" =~ ^[0-9]+$ ]]; then
            explanation+=", on ${dow_names[$dow]}"
        elif [[ "$dow" == "1-5" ]]; then
            explanation+=", Monday through Friday"
        elif [[ "$dow" == "0,6" || "$dow" == "6,0" ]]; then
            explanation+=", on weekends"
        else
            explanation+=", on days $dow"
        fi
    fi

    echo "$explanation"
}

# Calculate next run times
calculate_next_runs() {
    local expr="$1"
    local count="$2"

    read -ra fields <<< "$expr"
    local minute="${fields[0]}"
    local hour="${fields[1]}"
    local dom="${fields[2]}"
    local month="${fields[3]}"
    local dow="${fields[4]}"

    # Normalize
    month=$(normalize_field "$month" "month")
    dow=$(normalize_field "$dow" "dow")

    local current
    current=$(date +%s)
    local runs=()

    # Simple implementation: check each minute for the next 24 hours
    # For complex expressions, we'd need a more sophisticated algorithm
    local check_time=$current
    local max_checks=$((60 * 24 * 365))  # Max 1 year ahead
    local checks=0

    while [[ ${#runs[@]} -lt $count && $checks -lt $max_checks ]]; do
        check_time=$((check_time + 60))
        checks=$((checks + 1))

        local check_min check_hour check_dom check_mon check_dow
        check_min=$(date -d "@$check_time" +%-M)
        check_hour=$(date -d "@$check_time" +%-H)
        check_dom=$(date -d "@$check_time" +%-d)
        check_mon=$(date -d "@$check_time" +%-m)
        check_dow=$(date -d "@$check_time" +%w)

        # Check each field
        if ! matches_field "$minute" "$check_min" 0 59; then continue; fi
        if ! matches_field "$hour" "$check_hour" 0 23; then continue; fi
        if ! matches_field "$month" "$check_mon" 1 12; then continue; fi

        # Day matching: either dom OR dow must match (unless both are *)
        local dom_match=true
        local dow_match=true
        [[ "$dom" != "*" ]] && ! matches_field "$dom" "$check_dom" 1 31 && dom_match=false
        [[ "$dow" != "*" ]] && ! matches_field "$dow" "$check_dow" 0 6 && dow_match=false

        if [[ "$dom" == "*" && "$dow" == "*" ]]; then
            : # Both wildcards, always matches
        elif [[ "$dom" != "*" && "$dow" != "*" ]]; then
            # Both specified: OR logic
            if ! $dom_match && ! $dow_match; then continue; fi
        else
            # One specified: must match
            if ! $dom_match || ! $dow_match; then continue; fi
        fi

        runs+=("$(date -d "@$check_time" '+%Y-%m-%d %H:%M (%a)')")
    done

    printf '%s\n' "${runs[@]}"
}

# Check if a value matches a cron field pattern
matches_field() {
    local pattern="$1"
    local value="$2"
    local min="$3"
    local max="$4"

    # Wildcard
    [[ "$pattern" == "*" ]] && return 0

    # Step with wildcard
    if [[ "$pattern" =~ ^\*/([0-9]+)$ ]]; then
        local step="${BASH_REMATCH[1]}"
        [[ $((value % step)) -eq 0 ]] && return 0
        return 1
    fi

    # List
    if [[ "$pattern" == *","* ]]; then
        IFS=',' read -ra parts <<< "$pattern"
        for part in "${parts[@]}"; do
            if matches_field "$part" "$value" "$min" "$max"; then
                return 0
            fi
        done
        return 1
    fi

    # Range
    if [[ "$pattern" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        [[ $value -ge $start && $value -le $end ]] && return 0
        return 1
    fi

    # Range with step
    if [[ "$pattern" =~ ^([0-9]+)-([0-9]+)/([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        local step="${BASH_REMATCH[3]}"
        if [[ $value -ge $start && $value -le $end ]]; then
            [[ $(((value - start) % step)) -eq 0 ]] && return 0
        fi
        return 1
    fi

    # Exact match
    [[ "$pattern" == "$value" ]] && return 0
    return 1
}

# Output as JSON
output_json() {
    local expr="$1"
    local valid="$2"
    local explanation="$3"

    echo "{"
    echo "  \"expression\": \"$expr\","
    echo "  \"valid\": $valid,"

    if [[ "$valid" == "true" ]]; then
        read -ra fields <<< "$expr"
        echo "  \"fields\": {"
        echo "    \"minute\": \"${fields[0]}\","
        echo "    \"hour\": \"${fields[1]}\","
        echo "    \"dayOfMonth\": \"${fields[2]}\","
        echo "    \"month\": \"${fields[3]}\","
        echo "    \"dayOfWeek\": \"${fields[4]}\""
        echo "  },"
        echo "  \"explanation\": \"$explanation\","
        echo "  \"nextRuns\": ["

        local runs
        runs=$(calculate_next_runs "$expr" "$SHOW_NEXT")
        local first=true
        while IFS= read -r run; do
            [[ -z "$run" ]] && continue
            $first || echo ","
            echo -n "    \"$run\""
            first=false
        done <<< "$runs"
        echo ""
        echo "  ]"
    else
        echo "  \"error\": \"$explanation\""
    fi

    echo "}"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--validate)
            VALIDATE_ONLY=true
            shift
            ;;
        -n|--next)
            SHOW_NEXT="$2"
            shift 2
            ;;
        -e|--explain)
            EXPLAIN=true
            shift
            ;;
        --json)
            OUTPUT_JSON=true
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
            CRON_EXPR="$1"
            shift
            ;;
    esac
done

# Validate input
if [[ -z "$CRON_EXPR" ]]; then
    usage
    exit 1
fi

# Normalize the expression (convert names, collapse whitespace)
CRON_EXPR=$(echo "$CRON_EXPR" | tr '[:lower:]' '[:upper:]' | tr -s ' ')

# Validate
error_msg=$(validate_cron "$CRON_EXPR" 2>&1)
valid=$?

if [[ "$VALIDATE_ONLY" == "true" ]]; then
    exit $valid
fi

# Generate explanation
explanation=""
if [[ $valid -eq 0 ]]; then
    explanation=$(explain_cron "$CRON_EXPR")
fi

# Output
if [[ "$OUTPUT_JSON" == "true" ]]; then
    if [[ $valid -eq 0 ]]; then
        output_json "$CRON_EXPR" "true" "$explanation"
    else
        output_json "$CRON_EXPR" "false" "$error_msg"
    fi
    exit $valid
fi

# Text output
echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Cron Expression Parser            ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
echo ""

if [[ $valid -eq 0 ]]; then
    echo -e "Expression: ${CYAN}$CRON_EXPR${NC}"
    echo -e "Status:     ${GREEN}Valid${NC}"
    echo ""

    # Show field breakdown
    read -ra fields <<< "$CRON_EXPR"
    echo "Fields:"
    echo -e "  Minute:       ${fields[0]}"
    echo -e "  Hour:         ${fields[1]}"
    echo -e "  Day of Month: ${fields[2]}"
    echo -e "  Month:        ${fields[3]}"
    echo -e "  Day of Week:  ${fields[4]}"
    echo ""

    # Explanation
    if [[ "$EXPLAIN" == "true" ]]; then
        echo -e "${YELLOW}Meaning:${NC}"
        echo "  $explanation"
        echo ""
    fi

    # Next runs
    echo -e "${YELLOW}Next $SHOW_NEXT scheduled runs:${NC}"
    runs=$(calculate_next_runs "$CRON_EXPR" "$SHOW_NEXT")
    i=1
    while IFS= read -r run; do
        [[ -z "$run" ]] && continue
        echo "  $i. $run"
        ((i++))
    done <<< "$runs"
else
    echo -e "Expression: ${CYAN}$CRON_EXPR${NC}"
    echo -e "Status:     ${RED}Invalid${NC}"
    echo ""
    echo -e "${RED}Error:${NC} $error_msg"
fi

exit $valid

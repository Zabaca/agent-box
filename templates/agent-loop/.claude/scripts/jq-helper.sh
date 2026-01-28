#!/bin/bash
#
# JSON Query Helper
# Simplified JSON querying for logs and data files
#
# Usage: jq-helper.sh <command> [options] [file]
#   get <path>              Get value at JSON path
#   filter <expr>           Filter array by expression
#   count                   Count array elements or object keys
#   keys                    List object keys
#   values                  List object values
#   flatten                 Flatten nested structure
#   search <term>           Search for term in values
#   stats <path>            Get statistics for numeric field
#   table                   Format as ASCII table
#   -h, --help              Show help

set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat << 'EOF'
JSON Query Helper - Simplified JSON operations

Usage: jq-helper.sh <command> [options] [file]

Commands:
  get <path>              Get value at path (dot notation: .foo.bar[0])
  filter <key> <op> <val> Filter array (.status == "ok")
  count                   Count array elements or object keys
  keys                    List object keys
  values                  List values (one per line)
  flatten [depth]         Flatten nested structure
  search <term>           Search for term in all values
  stats <path>            Statistics for numeric array
  table [cols...]         Format as ASCII table
  pick <keys...>          Select specific keys from objects
  group <key>             Group array by key
  sort <key> [desc]       Sort array by key

Input:
  - Reads from file if provided
  - Reads from stdin if no file (pipe friendly)

Path Syntax:
  .                       Root object
  .foo                    Key "foo"
  .foo.bar                Nested key
  .[0]                    Array index
  .foo[*]                 All array elements
  .foo[]                  Same as above

Filter Operators:
  ==, !=                  Equality
  >, <, >=, <=            Comparison
  ~                       Contains (string)
  !~                      Not contains

Examples:
  # Get nested value
  jq-helper.sh get .config.timeout config.json

  # Filter array
  cat data.json | jq-helper.sh filter status == active

  # Count items
  jq-helper.sh count users.json

  # Search for term
  jq-helper.sh search error logs.json

  # Get statistics
  jq-helper.sh stats .response_time metrics.json

  # Format as table
  jq-helper.sh table id name status users.json

  # Pipeline
  cat logs.jsonl | jq-helper.sh filter level == error | jq-helper.sh count
EOF
}

# Read input (file or stdin)
read_input() {
    local file="${1:-}"
    if [[ -n "$file" && -f "$file" ]]; then
        cat "$file"
    else
        cat
    fi
}

# Get value at path
cmd_get() {
    local path="${1:-.}"
    shift
    local input
    input=$(read_input "$@")

    # Convert dot notation to jq syntax if needed
    # .foo.bar -> .foo.bar (already valid)
    # foo.bar -> .foo.bar
    [[ "$path" != .* ]] && path=".$path"

    echo "$input" | jq -r "$path" 2>/dev/null
}

# Filter array
cmd_filter() {
    local key="$1"
    local op="$2"
    local value="$3"
    shift 3
    local input
    input=$(read_input "$@")

    # Build jq filter expression
    local jq_expr
    case "$op" in
        "==")
            if [[ "$value" =~ ^[0-9]+$ ]]; then
                jq_expr=".[] | select($key == $value)"
            else
                jq_expr=".[] | select($key == \"$value\")"
            fi
            ;;
        "!=")
            if [[ "$value" =~ ^[0-9]+$ ]]; then
                jq_expr=".[] | select($key != $value)"
            else
                jq_expr=".[] | select($key != \"$value\")"
            fi
            ;;
        ">")
            jq_expr=".[] | select($key > $value)"
            ;;
        "<")
            jq_expr=".[] | select($key < $value)"
            ;;
        ">=")
            jq_expr=".[] | select($key >= $value)"
            ;;
        "<=")
            jq_expr=".[] | select($key <= $value)"
            ;;
        "~"|"contains")
            jq_expr=".[] | select($key | contains(\"$value\"))"
            ;;
        "!~"|"notcontains")
            jq_expr=".[] | select($key | contains(\"$value\") | not)"
            ;;
        *)
            echo "Unknown operator: $op" >&2
            return 1
            ;;
    esac

    echo "$input" | jq -c "[$jq_expr]" 2>/dev/null
}

# Count elements
cmd_count() {
    local input
    input=$(read_input "$@")

    # Try array length first, then object keys
    local count
    count=$(echo "$input" | jq 'if type == "array" then length elif type == "object" then keys | length else 1 end' 2>/dev/null)
    echo "$count"
}

# List keys
cmd_keys() {
    local input
    input=$(read_input "$@")
    echo "$input" | jq -r 'if type == "object" then keys[] elif type == "array" then .[0] | keys[] else empty end' 2>/dev/null
}

# List values
cmd_values() {
    local input
    input=$(read_input "$@")
    echo "$input" | jq -r 'if type == "object" then .[] elif type == "array" then .[] else . end' 2>/dev/null
}

# Flatten structure
cmd_flatten() {
    local depth="${1:-1}"
    shift 2>/dev/null || true
    local input
    input=$(read_input "$@")

    if [[ "$depth" == "deep" ]]; then
        echo "$input" | jq '[.. | scalars]' 2>/dev/null
    else
        echo "$input" | jq "flatten($depth)" 2>/dev/null
    fi
}

# Search for term
cmd_search() {
    local term="$1"
    shift
    local input
    input=$(read_input "$@")

    # Search in all string values
    echo "$input" | jq -c ".. | strings | select(contains(\"$term\"))" 2>/dev/null | while read -r line; do
        echo -e "${CYAN}Found:${NC} $line"
    done
}

# Statistics for numeric array
cmd_stats() {
    local path="${1:-.}"
    shift 2>/dev/null || true
    local input
    input=$(read_input "$@")

    [[ "$path" != .* ]] && path=".$path"

    # Extract numbers
    local numbers
    numbers=$(echo "$input" | jq -r "[$path | .. | numbers] | @csv" 2>/dev/null | tr ',' '\n')

    if [[ -z "$numbers" ]]; then
        echo "No numeric values found at path: $path"
        return 1
    fi

    local count min max sum avg
    count=$(echo "$numbers" | wc -l)
    min=$(echo "$numbers" | sort -n | head -1)
    max=$(echo "$numbers" | sort -n | tail -1)
    sum=$(echo "$numbers" | awk '{s+=$1} END {print s}')
    avg=$(echo "$numbers" | awk '{s+=$1} END {printf "%.2f", s/NR}')

    echo -e "${BLUE}Statistics for ${CYAN}$path${NC}"
    echo "─────────────────────────────"
    echo "  Count: $count"
    echo "  Min:   $min"
    echo "  Max:   $max"
    echo "  Sum:   $sum"
    echo "  Avg:   $avg"
}

# Format as table
cmd_table() {
    local cols=()
    local file=""

    # Parse columns and file
    while [[ $# -gt 0 ]]; do
        if [[ -f "$1" ]]; then
            file="$1"
        else
            cols+=("$1")
        fi
        shift
    done

    local input
    input=$(read_input "$file")

    # If no columns specified, auto-detect from first object
    if [[ ${#cols[@]} -eq 0 ]]; then
        cols=($(echo "$input" | jq -r 'if type == "array" then .[0] else . end | keys[]' 2>/dev/null | head -10))
    fi

    # Print header
    local header=""
    local sep=""
    for col in "${cols[@]}"; do
        header+=$(printf "%-20s" "$col")
        sep+="────────────────────"
    done
    echo -e "${BLUE}$header${NC}"
    echo "$sep"

    # Print rows
    echo "$input" | jq -c 'if type == "array" then .[] else . end' 2>/dev/null | while read -r row; do
        local line=""
        for col in "${cols[@]}"; do
            local val
            val=$(echo "$row" | jq -r ".$col // \"\"" 2>/dev/null)
            # Truncate long values
            [[ ${#val} -gt 18 ]] && val="${val:0:15}..."
            line+=$(printf "%-20s" "$val")
        done
        echo "$line"
    done
}

# Pick specific keys
cmd_pick() {
    local keys=()
    local file=""

    while [[ $# -gt 0 ]]; do
        if [[ -f "$1" ]]; then
            file="$1"
        else
            keys+=("$1")
        fi
        shift
    done

    local input
    input=$(read_input "$file")

    # Build jq expression
    local jq_expr="{"
    local first=true
    for key in "${keys[@]}"; do
        $first || jq_expr+=","
        jq_expr+="$key"
        first=false
    done
    jq_expr+="}"

    echo "$input" | jq "if type == \"array\" then [.[] | $jq_expr] else $jq_expr end" 2>/dev/null
}

# Group by key
cmd_group() {
    local key="$1"
    shift
    local input
    input=$(read_input "$@")

    echo "$input" | jq "group_by($key) | map({key: .[0]$key, items: .})" 2>/dev/null
}

# Sort by key
cmd_sort() {
    local key="$1"
    local order="${2:-asc}"
    shift 2 2>/dev/null || shift
    local input
    input=$(read_input "$@")

    if [[ "$order" == "desc" ]]; then
        echo "$input" | jq "sort_by($key) | reverse" 2>/dev/null
    else
        echo "$input" | jq "sort_by($key)" 2>/dev/null
    fi
}

# Process JSONL (line-delimited JSON)
cmd_jsonl() {
    local subcmd="$1"
    shift
    local input
    input=$(read_input "$@")

    # Convert JSONL to array and process
    local as_array
    as_array=$(echo "$input" | jq -s '.')

    case "$subcmd" in
        count)
            echo "$as_array" | jq 'length'
            ;;
        filter)
            echo "$as_array" | cmd_filter "$@" | jq -c '.[]'
            ;;
        *)
            echo "JSONL subcommand: $subcmd"
            echo "$as_array" | "cmd_$subcmd" "$@"
            ;;
    esac
}

# Main command dispatch
case "${1:-}" in
    get)
        shift
        cmd_get "$@"
        ;;
    filter)
        shift
        cmd_filter "$@"
        ;;
    count)
        shift
        cmd_count "$@"
        ;;
    keys)
        shift
        cmd_keys "$@"
        ;;
    values)
        shift
        cmd_values "$@"
        ;;
    flatten)
        shift
        cmd_flatten "$@"
        ;;
    search)
        shift
        cmd_search "$@"
        ;;
    stats)
        shift
        cmd_stats "$@"
        ;;
    table)
        shift
        cmd_table "$@"
        ;;
    pick)
        shift
        cmd_pick "$@"
        ;;
    group)
        shift
        cmd_group "$@"
        ;;
    sort)
        shift
        cmd_sort "$@"
        ;;
    jsonl)
        shift
        cmd_jsonl "$@"
        ;;
    -h|--help)
        usage
        ;;
    "")
        usage
        ;;
    *)
        echo "Unknown command: $1" >&2
        usage
        exit 1
        ;;
esac

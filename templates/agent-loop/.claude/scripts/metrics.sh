#!/bin/bash
#
# Metrics Collection System
# Tracks and reports agent performance metrics over time
#
# Usage: metrics.sh <command> [options]
#   record <metric> <value>    Record a metric value
#   show [metric]              Show metrics (all or specific)
#   summary                    Show summary statistics
#   export [format]            Export metrics (json, csv)
#   clean [days]               Clean old metrics (default: 30 days)
#   -h, --help                 Show help

set -uo pipefail

WORKSPACE="/agent-workspace"
METRICS_DIR="$WORKSPACE/.claude/metrics"
METRICS_FILE="$METRICS_DIR/metrics.jsonl"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat << 'EOF'
Metrics Collection System - Track agent performance

Usage: metrics.sh <command> [options]

Commands:
  record <metric> <value> [tags]   Record a metric value
  show [metric]                    Show metrics (all or specific)
  summary                          Show summary statistics
  export [format]                  Export metrics (json, csv)
  clean [days]                     Clean metrics older than N days (default: 30)

Metrics:
  Built-in metrics that can be recorded:
  - tasks_completed      Number of tasks completed
  - session_duration     Duration of a session in seconds
  - errors               Error count
  - commits              Git commits made
  - scripts_created      New scripts created
  - lines_written        Lines of code written

Recording:
  metrics.sh record tasks_completed 5
  metrics.sh record session_duration 300 "session=abc123"
  metrics.sh record custom_metric 42 "type=custom,source=test"

Viewing:
  metrics.sh show                  # All recent metrics
  metrics.sh show tasks_completed  # Specific metric
  metrics.sh summary               # Aggregated stats

Export:
  metrics.sh export json > metrics.json
  metrics.sh export csv > metrics.csv

Examples:
  metrics.sh record tasks_completed 3
  metrics.sh show tasks_completed
  metrics.sh summary
  metrics.sh export json
EOF
}

# Initialize metrics directory
init_metrics() {
    mkdir -p "$METRICS_DIR"
    [[ -f "$METRICS_FILE" ]] || touch "$METRICS_FILE"
}

# Record a metric
record_metric() {
    local metric="$1"
    local value="$2"
    local tags="${3:-}"
    local timestamp
    timestamp=$(date -Iseconds)

    init_metrics

    # Create JSON record
    local record="{\"timestamp\":\"$timestamp\",\"metric\":\"$metric\",\"value\":$value"

    # Add tags if provided
    if [[ -n "$tags" ]]; then
        record+=",\"tags\":{"
        local first=true
        IFS=',' read -ra tag_pairs <<< "$tags"
        for pair in "${tag_pairs[@]}"; do
            IFS='=' read -r key val <<< "$pair"
            $first || record+=","
            record+="\"$key\":\"$val\""
            first=false
        done
        record+="}"
    fi

    record+="}"

    echo "$record" >> "$METRICS_FILE"
    echo -e "${GREEN}✓${NC} Recorded: $metric = $value"
}

# Show metrics
show_metrics() {
    local filter_metric="${1:-}"

    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "No metrics recorded yet"
        return
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Metrics Dashboard               ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
    echo ""

    if [[ -n "$filter_metric" ]]; then
        echo -e "Showing metric: ${CYAN}$filter_metric${NC}"
        echo "─────────────────────────────────────────"
        grep "\"metric\":\"$filter_metric\"" "$METRICS_FILE" | while read -r line; do
            local ts value
            ts=$(echo "$line" | jq -r '.timestamp')
            value=$(echo "$line" | jq -r '.value')
            echo "  $ts: $value"
        done
    else
        echo "Recent metrics (last 20):"
        echo "─────────────────────────────────────────"
        tail -20 "$METRICS_FILE" | while read -r line; do
            local ts metric value
            ts=$(echo "$line" | jq -r '.timestamp' | cut -d'T' -f2 | cut -d'-' -f1 | cut -d'+' -f1)
            metric=$(echo "$line" | jq -r '.metric')
            value=$(echo "$line" | jq -r '.value')
            printf "  %-20s %-25s %s\n" "$ts" "$metric" "$value"
        done
    fi
}

# Show summary statistics
show_summary() {
    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "No metrics recorded yet"
        return
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Metrics Summary                 ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
    echo ""

    local total_records
    total_records=$(wc -l < "$METRICS_FILE")
    echo "Total records: $total_records"
    echo ""

    # Get unique metrics and their stats
    echo "Per-metric statistics:"
    echo "─────────────────────────────────────────"
    printf "  %-25s %8s %10s %10s %10s\n" "Metric" "Count" "Sum" "Avg" "Last"

    local metrics
    metrics=$(jq -r '.metric' "$METRICS_FILE" | sort | uniq)

    while IFS= read -r metric; do
        [[ -z "$metric" ]] && continue
        local count sum avg last

        # Extract values for this metric
        local values
        values=$(grep "\"metric\":\"$metric\"" "$METRICS_FILE" | jq -r '.value')

        count=$(echo "$values" | wc -l)
        sum=$(echo "$values" | awk '{s+=$1} END {print s}')
        avg=$(echo "$values" | awk '{s+=$1; c++} END {printf "%.2f", s/c}')
        last=$(echo "$values" | tail -1)

        printf "  %-25s %8d %10.0f %10.2f %10s\n" "$metric" "$count" "$sum" "$avg" "$last"
    done <<< "$metrics"

    echo ""

    # Time range
    local first_ts last_ts
    first_ts=$(head -1 "$METRICS_FILE" | jq -r '.timestamp')
    last_ts=$(tail -1 "$METRICS_FILE" | jq -r '.timestamp')

    echo "Time range:"
    echo "  First: $first_ts"
    echo "  Last:  $last_ts"
}

# Export metrics
export_metrics() {
    local format="${1:-json}"

    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "No metrics to export" >&2
        return 1
    fi

    case "$format" in
        json)
            echo "["
            local first=true
            while read -r line; do
                $first || echo ","
                echo -n "  $line"
                first=false
            done < "$METRICS_FILE"
            echo ""
            echo "]"
            ;;
        csv)
            echo "timestamp,metric,value,tags"
            while read -r line; do
                local ts metric value tags
                ts=$(echo "$line" | jq -r '.timestamp')
                metric=$(echo "$line" | jq -r '.metric')
                value=$(echo "$line" | jq -r '.value')
                tags=$(echo "$line" | jq -r '.tags // {} | to_entries | map("\(.key)=\(.value)") | join(";")')
                echo "$ts,$metric,$value,$tags"
            done < "$METRICS_FILE"
            ;;
        *)
            echo "Unknown format: $format" >&2
            return 1
            ;;
    esac
}

# Clean old metrics
clean_metrics() {
    local days="${1:-30}"
    local cutoff
    cutoff=$(date -d "$days days ago" +%Y-%m-%d)

    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "No metrics to clean"
        return
    fi

    local before
    before=$(wc -l < "$METRICS_FILE")

    # Filter to keep only recent records
    local temp_file
    temp_file=$(mktemp)

    while read -r line; do
        local ts
        ts=$(echo "$line" | jq -r '.timestamp' | cut -d'T' -f1)
        if [[ "$ts" > "$cutoff" ]]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$METRICS_FILE"

    mv "$temp_file" "$METRICS_FILE"

    local after
    after=$(wc -l < "$METRICS_FILE")
    local removed=$((before - after))

    echo -e "${GREEN}✓${NC} Cleaned $removed records older than $days days"
    echo "  Remaining: $after records"
}

# Record automatic metrics from current state
record_auto_metrics() {
    init_metrics

    # Count tasks
    local tasks_file="$WORKSPACE/.claude/loop/tasks.md"
    if [[ -f "$tasks_file" ]]; then
        local completed
        completed=$(grep -c '^\- \[x\]' "$tasks_file" 2>/dev/null || echo 0)
        record_metric "tasks_completed_total" "$completed" "source=auto"
    fi

    # Count commits
    local commits
    commits=$(git -C "$WORKSPACE" rev-list --count HEAD 2>/dev/null || echo 0)
    record_metric "git_commits_total" "$commits" "source=auto"

    # Count scripts
    local scripts
    scripts=$(find "$WORKSPACE/.claude/scripts" -name "*.sh" 2>/dev/null | wc -l)
    record_metric "scripts_count" "$scripts" "source=auto"

    # Disk usage
    local disk_used
    disk_used=$(df "$WORKSPACE" | tail -1 | awk '{print $3}')
    record_metric "disk_used_kb" "$disk_used" "source=auto"

    echo -e "${GREEN}✓${NC} Recorded automatic metrics"
}

# Main command dispatch
case "${1:-}" in
    record)
        if [[ $# -lt 3 ]]; then
            echo "Usage: metrics.sh record <metric> <value> [tags]"
            exit 1
        fi
        record_metric "$2" "$3" "${4:-}"
        ;;
    show)
        show_metrics "${2:-}"
        ;;
    summary)
        show_summary
        ;;
    export)
        export_metrics "${2:-json}"
        ;;
    clean)
        clean_metrics "${2:-30}"
        ;;
    auto)
        record_auto_metrics
        ;;
    -h|--help)
        usage
        ;;
    "")
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac

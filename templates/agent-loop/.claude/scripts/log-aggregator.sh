#!/bin/bash
#
# Log Aggregator
# Combines all log files into a unified, chronologically sorted view
#
# Usage: log-aggregator.sh [options]
#   -n N        Show last N lines (default: 100)
#   -f          Follow mode (like tail -f)
#   -s SOURCE   Filter by log source (heartbeat, watchdog, etc.)
#   -l LEVEL    Filter by level (INFO, ERROR, WARN)
#   -t TIME     Show logs after this time (e.g., "1 hour ago")
#   --json      Output as JSON
#   --html      Output as HTML
#   -h          Show help

set -euo pipefail

WORKSPACE="/agent-workspace"
LOG_DIR="$WORKSPACE/.claude/loop"

# Defaults
LINES=100
FOLLOW=false
SOURCE_FILTER=""
LEVEL_FILTER=""
TIME_FILTER=""
OUTPUT_FORMAT="text"

# Colors for terminal output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

usage() {
    cat << 'EOF'
Log Aggregator - Unified view of all system logs

Usage: log-aggregator.sh [options]

Options:
  -n N        Show last N lines (default: 100)
  -f          Follow mode (watch for new logs)
  -s SOURCE   Filter by log source (heartbeat, watchdog, task-gen, etc.)
  -l LEVEL    Filter by level (INFO, ERROR, WARN)
  -t TIME     Show logs after this time (e.g., "1 hour ago", "2026-01-20")
  --json      Output as JSON
  --html      Output as HTML
  -h, --help  Show this help

Sources:
  heartbeat, watchdog, task-gen, resource, error-tracker,
  checkpoint, api-server, test-runner, file-watcher, claude

Examples:
  log-aggregator.sh -n 50                    # Last 50 lines
  log-aggregator.sh -s heartbeat -n 20       # Last 20 heartbeat lines
  log-aggregator.sh -l ERROR                 # All errors
  log-aggregator.sh -t "1 hour ago"          # Last hour of logs
  log-aggregator.sh -f                       # Follow all logs
  log-aggregator.sh --json                   # JSON output
EOF
}

# Parse log line and extract timestamp
parse_log_line() {
    local line="$1"
    local source="$2"

    # Most logs use format: [TIMESTAMP] message
    if [[ "$line" =~ ^\[([0-9T:+-]+)\] ]]; then
        echo "${BASH_REMATCH[1]}|$source|$line"
    # Some might use ISO format directly
    elif [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
        echo "${BASH_REMATCH[1]}|$source|$line"
    # Fallback - use current time
    else
        echo "$(date -Iseconds)|$source|$line"
    fi
}

# Get source name from log file
get_source_name() {
    local file="$1"
    basename "$file" .log
}

# Colorize level in log line
colorize_level() {
    local line="$1"
    if [[ "$line" == *"ERROR"* ]] || [[ "$line" == *"error"* ]] || [[ "$line" == *"FAIL"* ]]; then
        echo -e "${RED}$line${NC}"
    elif [[ "$line" == *"WARN"* ]] || [[ "$line" == *"warn"* ]]; then
        echo -e "${YELLOW}$line${NC}"
    elif [[ "$line" == *"INFO"* ]] || [[ "$line" == *"info"* ]]; then
        echo -e "${GREEN}$line${NC}"
    elif [[ "$line" == *"DEBUG"* ]] || [[ "$line" == *"debug"* ]]; then
        echo -e "${GRAY}$line${NC}"
    else
        echo "$line"
    fi
}

# Format source name with color
format_source() {
    local source="$1"
    case "$source" in
        heartbeat) echo -e "${CYAN}[heartbeat]${NC}" ;;
        watchdog) echo -e "${YELLOW}[watchdog]${NC}" ;;
        task-generation) echo -e "${GREEN}[task-gen]${NC}" ;;
        resource-monitor) echo -e "${BLUE}[resource]${NC}" ;;
        error-tracker) echo -e "${RED}[error]${NC}" ;;
        api-server) echo -e "${GREEN}[api]${NC}" ;;
        *) echo -e "${GRAY}[$source]${NC}" ;;
    esac
}

# Check if timestamp is after filter time
is_after_time() {
    local log_time="$1"
    local filter_time="$2"

    # Convert filter time to epoch
    local filter_epoch
    filter_epoch=$(date -d "$filter_time" +%s 2>/dev/null) || return 0

    # Convert log time to epoch (handle various formats)
    local log_epoch
    log_epoch=$(date -d "$log_time" +%s 2>/dev/null) || return 0

    [[ $log_epoch -ge $filter_epoch ]]
}

# Aggregate logs from all files
aggregate_logs() {
    local temp_file
    temp_file=$(mktemp)

    # Process each log file
    for log_file in "$LOG_DIR"/*.log; do
        [[ -f "$log_file" ]] || continue

        local source
        source=$(get_source_name "$log_file")

        # Apply source filter if set
        if [[ -n "$SOURCE_FILTER" ]] && [[ "$source" != *"$SOURCE_FILTER"* ]]; then
            continue
        fi

        # Read and process each line
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" ]] && continue

            # Apply level filter if set
            if [[ -n "$LEVEL_FILTER" ]]; then
                if ! echo "$line" | grep -qi "$LEVEL_FILTER"; then
                    continue
                fi
            fi

            # Parse and add to temp file
            local parsed
            parsed=$(parse_log_line "$line" "$source")

            # Apply time filter if set
            if [[ -n "$TIME_FILTER" ]]; then
                local log_time
                log_time=$(echo "$parsed" | cut -d'|' -f1)
                if ! is_after_time "$log_time" "$TIME_FILTER"; then
                    continue
                fi
            fi

            echo "$parsed" >> "$temp_file"
        done < "$log_file"
    done

    # Sort by timestamp and output
    sort -t'|' -k1 "$temp_file" | tail -n "$LINES" > "${temp_file}.sorted"

    # Output based on format
    case "$OUTPUT_FORMAT" in
        json)
            output_json "${temp_file}.sorted"
            ;;
        html)
            output_html "${temp_file}.sorted"
            ;;
        *)
            output_text "${temp_file}.sorted"
            ;;
    esac

    rm -f "$temp_file" "${temp_file}.sorted"
}

# Text output
output_text() {
    local file="$1"
    while IFS='|' read -r timestamp source line; do
        local formatted_source
        formatted_source=$(format_source "$source")
        local colorized_line
        colorized_line=$(colorize_level "$line")
        echo -e "$formatted_source $colorized_line"
    done < "$file"
}

# JSON output
output_json() {
    local file="$1"
    echo "["
    local first=true
    while IFS='|' read -r timestamp source line; do
        if [[ "$first" == true ]]; then
            first=false
        else
            echo ","
        fi
        # Escape JSON special characters
        line="${line//\\/\\\\}"
        line="${line//\"/\\\"}"
        line="${line//$'\n'/\\n}"
        line="${line//$'\r'/\\r}"
        line="${line//$'\t'/\\t}"
        printf '  {"timestamp":"%s","source":"%s","message":"%s"}' "$timestamp" "$source" "$line"
    done < "$file"
    echo ""
    echo "]"
}

# HTML output
output_html() {
    local file="$1"
    cat << 'HTML_HEAD'
<!DOCTYPE html>
<html>
<head>
    <title>Log Aggregator</title>
    <style>
        body { font-family: monospace; background: #1a1a1a; color: #ddd; padding: 20px; }
        .log-line { margin: 2px 0; padding: 4px 8px; border-radius: 2px; }
        .source { font-weight: bold; margin-right: 8px; }
        .heartbeat { color: #00bcd4; }
        .watchdog { color: #ffeb3b; }
        .task-generation { color: #4caf50; }
        .resource-monitor { color: #2196f3; }
        .error-tracker { color: #f44336; }
        .error { background: rgba(244,67,54,0.2); }
        .warn { background: rgba(255,235,59,0.2); }
        .info { background: rgba(76,175,80,0.1); }
        .timestamp { color: #888; font-size: 0.9em; }
    </style>
</head>
<body>
    <h1>🔍 Log Aggregator</h1>
    <div class="logs">
HTML_HEAD

    while IFS='|' read -r timestamp source line; do
        local class=""
        [[ "$line" == *"ERROR"* ]] && class="error"
        [[ "$line" == *"WARN"* ]] && class="warn"
        [[ "$line" == *"INFO"* ]] && class="info"

        # HTML escape
        line="${line//&/&amp;}"
        line="${line//</&lt;}"
        line="${line//>/&gt;}"

        echo "        <div class=\"log-line $class\">"
        echo "            <span class=\"source ${source}\">[${source}]</span>"
        echo "            <span class=\"timestamp\">${timestamp}</span>"
        echo "            <span class=\"message\">${line}</span>"
        echo "        </div>"
    done < "$file"

    cat << 'HTML_FOOT'
    </div>
</body>
</html>
HTML_FOOT
}

# Follow mode - watch all logs
follow_logs() {
    echo "Following all logs (Ctrl+C to stop)..."

    # Use tail -f on all log files
    local files=()
    for log_file in "$LOG_DIR"/*.log; do
        [[ -f "$log_file" ]] || continue

        # Apply source filter if set
        local source
        source=$(get_source_name "$log_file")
        if [[ -n "$SOURCE_FILTER" ]] && [[ "$source" != *"$SOURCE_FILTER"* ]]; then
            continue
        fi

        files+=("$log_file")
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "No log files found matching filters"
        exit 1
    fi

    # Use tail with process substitution to add source labels
    tail -f "${files[@]}" 2>/dev/null | while IFS= read -r line; do
        # tail -f prefixes with ==> filename <== when switching files
        if [[ "$line" =~ ^==\>\ (.+)\ \<== ]]; then
            current_source=$(basename "${BASH_REMATCH[1]}" .log)
            continue
        fi

        [[ -z "$line" ]] && continue

        # Apply level filter
        if [[ -n "$LEVEL_FILTER" ]]; then
            if ! echo "$line" | grep -qi "$LEVEL_FILTER"; then
                continue
            fi
        fi

        local formatted_source
        formatted_source=$(format_source "${current_source:-unknown}")
        local colorized_line
        colorized_line=$(colorize_level "$line")
        echo -e "$formatted_source $colorized_line"
    done
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n)
            LINES="$2"
            shift 2
            ;;
        -f)
            FOLLOW=true
            shift
            ;;
        -s)
            SOURCE_FILTER="$2"
            shift 2
            ;;
        -l)
            LEVEL_FILTER="$2"
            shift 2
            ;;
        -t)
            TIME_FILTER="$2"
            shift 2
            ;;
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        --html)
            OUTPUT_FORMAT="html"
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
if [[ "$FOLLOW" == true ]]; then
    follow_logs
else
    aggregate_logs
fi

#!/bin/bash
#
# Task Scheduler
# Schedule and manage recurring tasks with simple syntax
#
# Usage: scheduler.sh <command> [options]
#   add <name> <schedule> <command>    Add a scheduled task
#   remove <name>                      Remove a task
#   list                               List all scheduled tasks
#   run <name>                         Run a task immediately
#   status                             Show scheduler status
#   start                              Start scheduler daemon
#   stop                               Stop scheduler daemon
#   -h, --help                         Show help

set -uo pipefail

WORKSPACE="/agent-workspace"
SCHEDULER_DIR="$WORKSPACE/.claude/scheduler"
TASKS_FILE="$SCHEDULER_DIR/tasks.json"
LOG_FILE="$SCHEDULER_DIR/scheduler.log"
PID_FILE="$SCHEDULER_DIR/scheduler.pid"
LOCK_FILE="$SCHEDULER_DIR/scheduler.lock"

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
Task Scheduler - Schedule and manage recurring tasks

Usage: scheduler.sh <command> [options]

Commands:
  add <name> <schedule> <command>    Add a scheduled task
  remove <name>                      Remove a task
  list                               List all scheduled tasks
  enable <name>                      Enable a disabled task
  disable <name>                     Disable a task
  run <name>                         Run a task immediately
  history [name]                     Show execution history
  status                             Show scheduler status
  start                              Start scheduler daemon
  stop                               Stop scheduler daemon
  logs [lines]                       Show recent log entries

Schedule Formats:
  @every <duration>     Run every N minutes/hours/days
                        Examples: @every 5m, @every 1h, @every 1d
  @hourly               Run at the start of every hour
  @daily                Run at midnight every day
  @weekly               Run at midnight on Sunday
  @startup              Run when scheduler starts
  <cron>                Standard 5-field cron expression
                        Example: */5 * * * *  (every 5 minutes)

Examples:
  scheduler.sh add backup "@every 6h" "/path/to/backup.sh"
  scheduler.sh add cleanup "@daily" "rm -rf /tmp/old/*"
  scheduler.sh add health "@every 5m" "./health-check.sh"
  scheduler.sh add report "0 9 * * 1" "./weekly-report.sh"
  scheduler.sh list
  scheduler.sh run backup
  scheduler.sh start
EOF
}

# Initialize scheduler
init_scheduler() {
    mkdir -p "$SCHEDULER_DIR"
    [[ -f "$TASKS_FILE" ]] || echo '{"tasks":[]}' > "$TASKS_FILE"
    [[ -f "$LOG_FILE" ]] || touch "$LOG_FILE"
}

# Log message
log() {
    local level="$1"
    local message="$2"
    echo "[$(date -Iseconds)] [$level] $message" >> "$LOG_FILE"
}

# Parse schedule to seconds
parse_schedule() {
    local schedule="$1"

    case "$schedule" in
        @every\ *)
            local duration="${schedule#@every }"
            local num="${duration%[smhd]}"
            local unit="${duration: -1}"

            case "$unit" in
                s) echo "$num" ;;
                m) echo "$((num * 60))" ;;
                h) echo "$((num * 3600))" ;;
                d) echo "$((num * 86400))" ;;
                *) echo "0" ;;
            esac
            ;;
        @hourly)
            echo "3600"
            ;;
        @daily)
            echo "86400"
            ;;
        @weekly)
            echo "604800"
            ;;
        @startup)
            echo "0"
            ;;
        *)
            # Assume cron expression - we'll handle this differently
            echo "cron:$schedule"
            ;;
    esac
}

# Check if cron should run now
should_cron_run() {
    local cron_expr="$1"

    # Parse cron fields
    local minute hour dom month dow
    read -r minute hour dom month dow <<< "$cron_expr"

    local now_minute now_hour now_dom now_month now_dow
    now_minute=$(date +%-M)
    now_hour=$(date +%-H)
    now_dom=$(date +%-d)
    now_month=$(date +%-m)
    now_dow=$(date +%u)  # 1-7, Monday-Sunday

    # Check each field
    match_field() {
        local field="$1"
        local value="$2"

        [[ "$field" == "*" ]] && return 0

        # Handle */n
        if [[ "$field" =~ ^\*/([0-9]+)$ ]]; then
            local step="${BASH_REMATCH[1]}"
            [[ $((value % step)) -eq 0 ]] && return 0
            return 1
        fi

        # Handle ranges
        if [[ "$field" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            [[ $value -ge $start && $value -le $end ]] && return 0
            return 1
        fi

        # Handle lists
        if [[ "$field" == *,* ]]; then
            IFS=',' read -ra values <<< "$field"
            for v in "${values[@]}"; do
                [[ "$v" == "$value" ]] && return 0
            done
            return 1
        fi

        # Direct match
        [[ "$field" == "$value" ]] && return 0
        return 1
    }

    match_field "$minute" "$now_minute" || return 1
    match_field "$hour" "$now_hour" || return 1
    match_field "$dom" "$now_dom" || return 1
    match_field "$month" "$now_month" || return 1
    match_field "$dow" "$now_dow" || return 1

    return 0
}

# Add a task
cmd_add() {
    local name="$1"
    local schedule="$2"
    local command="$3"

    init_scheduler

    # Check if task already exists
    if jq -e ".tasks[] | select(.name == \"$name\")" "$TASKS_FILE" > /dev/null 2>&1; then
        echo -e "${YELLOW}Warning:${NC} Task '$name' already exists. Updating..."
        cmd_remove "$name" > /dev/null
    fi

    local parsed_schedule
    parsed_schedule=$(parse_schedule "$schedule")

    # Create task entry
    local temp_file
    temp_file=$(mktemp)

    jq --arg name "$name" \
       --arg schedule "$schedule" \
       --arg parsed "$parsed_schedule" \
       --arg cmd "$command" \
       --arg created "$(date -Iseconds)" \
       '.tasks += [{
         "name": $name,
         "schedule": $schedule,
         "parsed_schedule": $parsed,
         "command": $cmd,
         "enabled": true,
         "created": $created,
         "last_run": null,
         "next_run": null,
         "run_count": 0,
         "last_status": null
       }]' "$TASKS_FILE" > "$temp_file"

    mv "$temp_file" "$TASKS_FILE"

    log "INFO" "Added task: $name (schedule: $schedule)"
    echo -e "${GREEN}✓${NC} Added task: $name"
    echo "  Schedule: $schedule"
    echo "  Command: $command"
}

# Remove a task
cmd_remove() {
    local name="$1"

    init_scheduler

    if ! jq -e ".tasks[] | select(.name == \"$name\")" "$TASKS_FILE" > /dev/null 2>&1; then
        echo -e "${RED}Error:${NC} Task '$name' not found"
        return 1
    fi

    local temp_file
    temp_file=$(mktemp)

    jq --arg name "$name" '.tasks = [.tasks[] | select(.name != $name)]' "$TASKS_FILE" > "$temp_file"
    mv "$temp_file" "$TASKS_FILE"

    log "INFO" "Removed task: $name"
    echo -e "${GREEN}✓${NC} Removed task: $name"
}

# List tasks
cmd_list() {
    init_scheduler

    local count
    count=$(jq '.tasks | length' "$TASKS_FILE")

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Scheduled Tasks ($count)                                       ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ "$count" -eq 0 ]]; then
        echo "No tasks scheduled"
        return
    fi

    printf "%-15s %-15s %-8s %-10s %s\n" "NAME" "SCHEDULE" "ENABLED" "RUNS" "COMMAND"
    echo "─────────────────────────────────────────────────────────────────────"

    jq -r '.tasks[] | "\(.name)|\(.schedule)|\(.enabled)|\(.run_count)|\(.command)"' "$TASKS_FILE" | while IFS='|' read -r name schedule enabled runs command; do
        local status_icon="●"
        local status_color="$GREEN"
        if [[ "$enabled" != "true" ]]; then
            status_icon="○"
            status_color="$GRAY"
        fi

        # Truncate command
        [[ ${#command} -gt 30 ]] && command="${command:0:27}..."

        printf "%-15s %-15s ${status_color}%-8s${NC} %-10s %s\n" "$name" "$schedule" "$status_icon" "$runs" "$command"
    done
}

# Enable/disable task
cmd_enable() {
    local name="$1"
    local enabled="${2:-true}"

    init_scheduler

    if ! jq -e ".tasks[] | select(.name == \"$name\")" "$TASKS_FILE" > /dev/null 2>&1; then
        echo -e "${RED}Error:${NC} Task '$name' not found"
        return 1
    fi

    local temp_file
    temp_file=$(mktemp)

    jq --arg name "$name" --argjson enabled "$enabled" \
       '(.tasks[] | select(.name == $name)).enabled = $enabled' "$TASKS_FILE" > "$temp_file"
    mv "$temp_file" "$TASKS_FILE"

    if [[ "$enabled" == "true" ]]; then
        echo -e "${GREEN}✓${NC} Enabled task: $name"
    else
        echo -e "${GREEN}✓${NC} Disabled task: $name"
    fi
}

cmd_disable() {
    cmd_enable "$1" "false"
}

# Run a task immediately
cmd_run() {
    local name="$1"

    init_scheduler

    local task
    task=$(jq -r ".tasks[] | select(.name == \"$name\")" "$TASKS_FILE")

    if [[ -z "$task" || "$task" == "null" ]]; then
        echo -e "${RED}Error:${NC} Task '$name' not found"
        return 1
    fi

    local command
    command=$(echo "$task" | jq -r '.command')

    echo -e "${CYAN}Running task: $name${NC}"
    echo "Command: $command"
    echo "─────────────────────────────────────────"

    local start_time
    start_time=$(date +%s.%N)

    local exit_code=0
    if ! eval "$command"; then
        exit_code=$?
    fi

    local end_time
    end_time=$(date +%s.%N)
    local duration
    duration=$(echo "$end_time - $start_time" | bc)

    # Update task status
    local temp_file
    temp_file=$(mktemp)

    jq --arg name "$name" \
       --arg last_run "$(date -Iseconds)" \
       --argjson exit_code "$exit_code" \
       '(.tasks[] | select(.name == $name)) |= . + {
         "last_run": $last_run,
         "last_status": $exit_code,
         "run_count": (.run_count + 1)
       }' "$TASKS_FILE" > "$temp_file"
    mv "$temp_file" "$TASKS_FILE"

    echo ""
    echo "─────────────────────────────────────────"
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} Task completed successfully (${duration}s)"
    else
        echo -e "${RED}✗${NC} Task failed with exit code $exit_code (${duration}s)"
    fi

    log "INFO" "Ran task: $name (exit: $exit_code, duration: ${duration}s)"
}

# Show task history
cmd_history() {
    local name="${1:-}"

    init_scheduler

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Task History                                                 ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ -n "$name" ]]; then
        local task
        task=$(jq -r ".tasks[] | select(.name == \"$name\")" "$TASKS_FILE")

        if [[ -z "$task" || "$task" == "null" ]]; then
            echo "Task not found: $name"
            return 1
        fi

        echo "Task: $name"
        echo "  Created:    $(echo "$task" | jq -r '.created')"
        echo "  Last run:   $(echo "$task" | jq -r '.last_run // "never"')"
        echo "  Run count:  $(echo "$task" | jq -r '.run_count')"
        echo "  Last status: $(echo "$task" | jq -r '.last_status // "n/a"')"
    else
        jq -r '.tasks[] | "Task: \(.name)\n  Runs: \(.run_count)\n  Last: \(.last_run // \"never\")\n  Status: \(.last_status // \"n/a\")\n"' "$TASKS_FILE"
    fi

    echo ""
    echo "Recent log entries:"
    tail -10 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
}

# Show scheduler status
cmd_status() {
    init_scheduler

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Scheduler Status                                             ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Check if daemon is running
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "Daemon: ${GREEN}Running${NC} (PID: $pid)"
        else
            echo -e "Daemon: ${RED}Stale PID file${NC}"
            rm -f "$PID_FILE"
        fi
    else
        echo -e "Daemon: ${YELLOW}Not running${NC}"
    fi

    local task_count enabled_count
    task_count=$(jq '.tasks | length' "$TASKS_FILE")
    enabled_count=$(jq '[.tasks[] | select(.enabled == true)] | length' "$TASKS_FILE")

    echo ""
    echo "Tasks:"
    echo "  Total: $task_count"
    echo "  Enabled: $enabled_count"
    echo "  Disabled: $((task_count - enabled_count))"

    echo ""
    echo "Log file: $LOG_FILE"
    echo "Log size: $(du -h "$LOG_FILE" 2>/dev/null | cut -f1)"
}

# Start scheduler daemon
cmd_start() {
    init_scheduler

    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}Scheduler already running${NC} (PID: $pid)"
            return 0
        fi
        rm -f "$PID_FILE"
    fi

    echo -e "${CYAN}Starting scheduler daemon...${NC}"

    # Run daemon in background
    (
        echo $$ > "$PID_FILE"
        log "INFO" "Scheduler started (PID: $$)"

        # Track last minute to avoid double-runs
        local last_check=""

        while true; do
            # Check for stop signal
            if [[ -f "$SCHEDULER_DIR/stop-signal" ]]; then
                rm -f "$SCHEDULER_DIR/stop-signal"
                log "INFO" "Stop signal received"
                break
            fi

            local current_minute
            current_minute=$(date +%Y-%m-%d-%H-%M)

            if [[ "$current_minute" != "$last_check" ]]; then
                last_check="$current_minute"

                # Check each enabled task
                jq -c '.tasks[] | select(.enabled == true)' "$TASKS_FILE" 2>/dev/null | while read -r task; do
                    local name schedule parsed
                    name=$(echo "$task" | jq -r '.name')
                    schedule=$(echo "$task" | jq -r '.schedule')
                    parsed=$(echo "$task" | jq -r '.parsed_schedule')

                    local should_run=false

                    if [[ "$parsed" == cron:* ]]; then
                        local cron_expr="${parsed#cron:}"
                        if should_cron_run "$cron_expr"; then
                            should_run=true
                        fi
                    elif [[ "$parsed" =~ ^[0-9]+$ ]] && [[ "$parsed" -gt 0 ]]; then
                        local last_run
                        last_run=$(echo "$task" | jq -r '.last_run')

                        if [[ "$last_run" == "null" ]]; then
                            should_run=true
                        else
                            local last_ts now_ts
                            last_ts=$(date -d "$last_run" +%s 2>/dev/null || echo 0)
                            now_ts=$(date +%s)

                            if [[ $((now_ts - last_ts)) -ge $parsed ]]; then
                                should_run=true
                            fi
                        fi
                    fi

                    if [[ "$should_run" == "true" ]]; then
                        log "INFO" "Triggering task: $name"
                        "$0" run "$name" >> "$LOG_FILE" 2>&1 &
                    fi
                done
            fi

            sleep 30
        done

        rm -f "$PID_FILE"
        log "INFO" "Scheduler stopped"
    ) &

    sleep 1

    if [[ -f "$PID_FILE" ]]; then
        echo -e "${GREEN}✓${NC} Scheduler started (PID: $(cat "$PID_FILE"))"
    else
        echo -e "${RED}✗${NC} Failed to start scheduler"
        return 1
    fi
}

# Stop scheduler daemon
cmd_stop() {
    init_scheduler

    if [[ ! -f "$PID_FILE" ]]; then
        echo -e "${YELLOW}Scheduler is not running${NC}"
        return 0
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if kill -0 "$pid" 2>/dev/null; then
        echo "Stopping scheduler (PID: $pid)..."
        touch "$SCHEDULER_DIR/stop-signal"

        # Wait for graceful shutdown
        local timeout=10
        while [[ $timeout -gt 0 ]] && kill -0 "$pid" 2>/dev/null; do
            sleep 1
            ((timeout--))
        done

        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
        fi

        rm -f "$PID_FILE" "$SCHEDULER_DIR/stop-signal"
        echo -e "${GREEN}✓${NC} Scheduler stopped"
    else
        rm -f "$PID_FILE"
        echo -e "${YELLOW}Scheduler was not running (stale PID file removed)${NC}"
    fi
}

# Show logs
cmd_logs() {
    local lines="${1:-20}"

    init_scheduler

    echo -e "${BLUE}Recent log entries ($lines):${NC}"
    echo "─────────────────────────────────────────"
    tail -"$lines" "$LOG_FILE" 2>/dev/null || echo "No logs yet"
}

# Main command dispatch
case "${1:-}" in
    add)
        if [[ $# -lt 4 ]]; then
            echo "Usage: scheduler.sh add <name> <schedule> <command>"
            exit 1
        fi
        cmd_add "$2" "$3" "$4"
        ;;
    remove)
        if [[ $# -lt 2 ]]; then
            echo "Usage: scheduler.sh remove <name>"
            exit 1
        fi
        cmd_remove "$2"
        ;;
    list)
        cmd_list
        ;;
    enable)
        if [[ $# -lt 2 ]]; then
            echo "Usage: scheduler.sh enable <name>"
            exit 1
        fi
        cmd_enable "$2"
        ;;
    disable)
        if [[ $# -lt 2 ]]; then
            echo "Usage: scheduler.sh disable <name>"
            exit 1
        fi
        cmd_disable "$2"
        ;;
    run)
        if [[ $# -lt 2 ]]; then
            echo "Usage: scheduler.sh run <name>"
            exit 1
        fi
        cmd_run "$2"
        ;;
    history)
        cmd_history "${2:-}"
        ;;
    status)
        cmd_status
        ;;
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    logs)
        cmd_logs "${2:-20}"
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

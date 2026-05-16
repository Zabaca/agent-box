#!/bin/bash

# Session Manager - Manage long-running background processes
# Provides a simple interface for starting, monitoring, and controlling background tasks
# Usage: session-manager.sh <command> [options]

set -euo pipefail

WORKSPACE="/agent-workspace"
SESSION_DIR="$WORKSPACE/.claude/sessions"
LOG_DIR="$SESSION_DIR/logs"
PID_DIR="$SESSION_DIR/pids"

# Ensure directories exist
mkdir -p "$SESSION_DIR" "$LOG_DIR" "$PID_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

usage() {
    cat <<EOF
Session Manager - Manage long-running background processes

Usage: session-manager.sh <command> [options]

Commands:
  start       Start a new session
  list        List all sessions (active and completed)
  status      Show status of a session
  logs        View session output/logs
  tail        Follow session output in real-time
  stop        Stop a running session (SIGTERM)
  kill        Force kill a session (SIGKILL)
  restart     Restart a session
  clean       Remove completed/dead sessions
  attach      Attach to session output (interactive follow)

Start Options:
  -n, --name NAME       Session name (default: auto-generated)
  -d, --dir DIR         Working directory
  -e, --env KEY=VAL     Set environment variable (can repeat)
  -l, --log FILE        Custom log file path
  --no-log              Don't save output to log file
  --timeout SECONDS     Auto-stop after timeout
  --restart-on-fail     Automatically restart if process fails
  --max-restarts N      Maximum restart attempts (default: 3)

List Options:
  -a, --all             Include completed sessions
  -q, --quiet           Only show session names
  --json                Output as JSON

Examples:
  # Start a long-running process
  session-manager.sh start -n myserver "python -m http.server 8000"

  # Start with working directory and env vars
  session-manager.sh start -n build -d /project -e NODE_ENV=production "npm run build"

  # List running sessions
  session-manager.sh list

  # View session output
  session-manager.sh logs myserver

  # Follow output in real-time
  session-manager.sh tail myserver

  # Stop a session gracefully
  session-manager.sh stop myserver

  # Clean up old sessions
  session-manager.sh clean
EOF
}

# Generate unique session ID
generate_id() {
    echo "sess_$(date +%Y%m%d_%H%M%S)_$$"
}

# Get session file
get_session_file() {
    local name="$1"
    echo "$SESSION_DIR/${name}.json"
}

# Get session PID file
get_pid_file() {
    local name="$1"
    echo "$PID_DIR/${name}.pid"
}

# Get session log file
get_log_file() {
    local name="$1"
    echo "$LOG_DIR/${name}.log"
}

# Check if session exists
session_exists() {
    local name="$1"
    [ -f "$(get_session_file "$name")" ]
}

# Check if session is running
session_running() {
    local name="$1"
    local pid_file
    pid_file=$(get_pid_file "$name")

    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Get session info
get_session_info() {
    local name="$1"
    local session_file
    session_file=$(get_session_file "$name")

    if [ -f "$session_file" ]; then
        cat "$session_file"
    else
        echo "{}"
    fi
}

# Update session info
update_session_info() {
    local name="$1"
    local key="$2"
    local value="$3"
    local session_file
    session_file=$(get_session_file "$name")

    if [ -f "$session_file" ]; then
        local tmp
        tmp=$(mktemp)
        jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$session_file" > "$tmp"
        mv "$tmp" "$session_file"
    fi
}

# Start a new session
cmd_start() {
    local name=""
    local workdir="$PWD"
    local env_vars=()
    local log_file=""
    local no_log=false
    local timeout=0
    local restart_on_fail=false
    local max_restarts=3
    local command=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--name)
                name="$2"
                shift 2
                ;;
            -d|--dir)
                workdir="$2"
                shift 2
                ;;
            -e|--env)
                env_vars+=("$2")
                shift 2
                ;;
            -l|--log)
                log_file="$2"
                shift 2
                ;;
            --no-log)
                no_log=true
                shift
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --restart-on-fail)
                restart_on_fail=true
                shift
                ;;
            --max-restarts)
                max_restarts="$2"
                shift 2
                ;;
            --)
                shift
                command="$*"
                break
                ;;
            *)
                if [ -z "$command" ]; then
                    command="$*"
                    break
                fi
                shift
                ;;
        esac
    done

    if [ -z "$command" ]; then
        echo -e "${RED}Error: No command specified${NC}" >&2
        echo "Usage: session-manager.sh start [options] <command>" >&2
        return 1
    fi

    # Generate name if not provided
    if [ -z "$name" ]; then
        name=$(generate_id)
    fi

    # Check if session already exists and is running
    if session_exists "$name" && session_running "$name"; then
        echo -e "${RED}Error: Session '$name' is already running${NC}" >&2
        return 1
    fi

    # Set up log file
    if [ -z "$log_file" ] && [ "$no_log" = false ]; then
        log_file=$(get_log_file "$name")
    fi

    local pid_file
    pid_file=$(get_pid_file "$name")

    local session_file
    session_file=$(get_session_file "$name")

    # Create session info
    local session_info
    session_info=$(jq -n \
        --arg name "$name" \
        --arg command "$command" \
        --arg workdir "$workdir" \
        --arg log_file "${log_file:-}" \
        --arg started_at "$(date -Iseconds)" \
        --argjson timeout "$timeout" \
        --argjson restart_on_fail "$restart_on_fail" \
        --argjson max_restarts "$max_restarts" \
        --argjson restarts 0 \
        '{
            name: $name,
            command: $command,
            workdir: $workdir,
            log_file: $log_file,
            started_at: $started_at,
            status: "starting",
            timeout: $timeout,
            restart_on_fail: $restart_on_fail,
            max_restarts: $max_restarts,
            restarts: $restarts
        }')

    echo "$session_info" > "$session_file"

    # Build the wrapper script
    local wrapper_script
    wrapper_script=$(mktemp)

    # Write wrapper script header
    cat > "$wrapper_script" <<'WRAPPER_HEAD'
#!/bin/bash
WRAPPER_HEAD

    echo "cd \"$workdir\" || exit 1" >> "$wrapper_script"

    # Add environment variables
    for env_var in "${env_vars[@]:-}"; do
        [ -n "$env_var" ] && echo "export $env_var" >> "$wrapper_script"
    done

    # Add the command
    cat >> "$wrapper_script" <<WRAPPER_CMD

# Run the command
$command

# Exit with the command's exit code
exit \$?
WRAPPER_CMD

    chmod +x "$wrapper_script"

    # Start the process
    if [ -n "$log_file" ]; then
        # With logging
        nohup bash "$wrapper_script" > "$log_file" 2>&1 &
    else
        # Without logging
        nohup bash "$wrapper_script" > /dev/null 2>&1 &
    fi

    local pid=$!
    echo "$pid" > "$pid_file"

    # Update session info with PID
    local tmp
    tmp=$(mktemp)
    jq --argjson pid "$pid" '.pid = $pid | .status = "running"' "$session_file" > "$tmp"
    mv "$tmp" "$session_file"

    # Clean up wrapper script after a delay (let it start)
    (sleep 2 && rm -f "$wrapper_script") &

    # Set up timeout if specified
    if [ "$timeout" -gt 0 ]; then
        (
            sleep "$timeout"
            if session_running "$name"; then
                echo -e "${YELLOW}Session '$name' timed out after ${timeout}s${NC}" >> "${log_file:-/dev/null}"
                kill "$pid" 2>/dev/null || true
            fi
        ) &
    fi

    echo -e "${GREEN}Started session '$name'${NC}"
    echo -e "  PID: $pid"
    echo -e "  Command: $command"
    [ -n "$log_file" ] && echo -e "  Log: $log_file"

    return 0
}

# List sessions
cmd_list() {
    local show_all=false
    local quiet=false
    local json_output=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all) show_all=true; shift ;;
            -q|--quiet) quiet=true; shift ;;
            --json) json_output=true; shift ;;
            *) shift ;;
        esac
    done

    local sessions=()

    for session_file in "$SESSION_DIR"/*.json; do
        [ -f "$session_file" ] || continue

        local name
        name=$(jq -r '.name' "$session_file")
        local is_running=false

        if session_running "$name"; then
            is_running=true
        fi

        if [ "$show_all" = false ] && [ "$is_running" = false ]; then
            continue
        fi

        if [ "$quiet" = true ]; then
            echo "$name"
            continue
        fi

        local command started_at status pid
        command=$(jq -r '.command // ""' "$session_file")
        started_at=$(jq -r '.started_at // ""' "$session_file")
        status=$(jq -r '.status // "unknown"' "$session_file")
        pid=$(jq -r '.pid // 0' "$session_file")

        # Update status if needed
        if [ "$is_running" = true ]; then
            status="running"
        elif [ "$status" = "running" ]; then
            status="stopped"
        fi

        if [ "$json_output" = true ]; then
            sessions+=("$(jq -n \
                --arg name "$name" \
                --arg command "$command" \
                --arg started_at "$started_at" \
                --arg status "$status" \
                --argjson pid "$pid" \
                --argjson running "$is_running" \
                '{name: $name, command: $command, started_at: $started_at, status: $status, pid: $pid, running: $running}')")
        else
            local status_color=$GRAY
            if [ "$is_running" = true ]; then
                status_color=$GREEN
            elif [ "$status" = "stopped" ]; then
                status_color=$RED
            fi

            echo -e "${CYAN}$name${NC}"
            echo -e "  Status: ${status_color}${status}${NC} (PID: $pid)"
            echo -e "  Command: ${GRAY}${command:0:60}${NC}"
            echo -e "  Started: ${GRAY}$started_at${NC}"
            echo ""
        fi
    done

    if [ "$json_output" = true ]; then
        printf '%s\n' "${sessions[@]:-}" | jq -s '.'
    fi

    if [ "$quiet" = false ] && [ "$json_output" = false ] && [ ${#sessions[@]} -eq 0 ]; then
        local count
        count=$(find "$SESSION_DIR" -name "*.json" 2>/dev/null | wc -l)
        if [ "$count" -eq 0 ]; then
            echo -e "${GRAY}No sessions found${NC}"
        elif [ "$show_all" = false ]; then
            echo -e "${GRAY}No running sessions. Use -a to show all.${NC}"
        fi
    fi
}

# Show session status
cmd_status() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "Usage: session-manager.sh status <name>" >&2
        return 1
    fi

    if ! session_exists "$name"; then
        echo -e "${RED}Session '$name' not found${NC}" >&2
        return 1
    fi

    local session_file
    session_file=$(get_session_file "$name")
    local info
    info=$(cat "$session_file")

    local is_running=false
    if session_running "$name"; then
        is_running=true
    fi

    local status
    status=$(echo "$info" | jq -r '.status')
    if [ "$is_running" = true ]; then
        status="running"
    elif [ "$status" = "running" ]; then
        status="stopped"
    fi

    local pid
    pid=$(echo "$info" | jq -r '.pid // 0')

    echo -e "${CYAN}=== Session: $name ===${NC}"
    echo -e "Status: $([ "$is_running" = true ] && echo -e "${GREEN}running${NC}" || echo -e "${RED}stopped${NC}")"
    echo -e "PID: $pid"
    echo -e "Command: $(echo "$info" | jq -r '.command')"
    echo -e "Working Dir: $(echo "$info" | jq -r '.workdir')"
    echo -e "Started: $(echo "$info" | jq -r '.started_at')"

    local log_file
    log_file=$(echo "$info" | jq -r '.log_file // empty')
    if [ -n "$log_file" ] && [ -f "$log_file" ]; then
        local log_size
        log_size=$(du -h "$log_file" | cut -f1)
        echo -e "Log File: $log_file ($log_size)"
    fi

    # Show resource usage if running
    if [ "$is_running" = true ]; then
        echo ""
        echo -e "${CYAN}Resource Usage:${NC}"
        ps -p "$pid" -o %cpu,%mem,etime,rss --no-headers 2>/dev/null | awk '{
            printf "  CPU: %s%%\n  Memory: %s%% (RSS: %.1f MB)\n  Uptime: %s\n", $1, $2, $4/1024, $3
        }'
    fi
}

# View session logs
cmd_logs() {
    local name="${1:-}"
    local lines=50
    shift || true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--lines) lines="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [ -z "$name" ]; then
        echo "Usage: session-manager.sh logs <name> [-n lines]" >&2
        return 1
    fi

    if ! session_exists "$name"; then
        echo -e "${RED}Session '$name' not found${NC}" >&2
        return 1
    fi

    local log_file
    log_file=$(jq -r '.log_file // empty' "$(get_session_file "$name")")

    if [ -z "$log_file" ] || [ ! -f "$log_file" ]; then
        echo -e "${YELLOW}No log file for session '$name'${NC}" >&2
        return 1
    fi

    tail -n "$lines" "$log_file"
}

# Follow session output
cmd_tail() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "Usage: session-manager.sh tail <name>" >&2
        return 1
    fi

    if ! session_exists "$name"; then
        echo -e "${RED}Session '$name' not found${NC}" >&2
        return 1
    fi

    local log_file
    log_file=$(jq -r '.log_file // empty' "$(get_session_file "$name")")

    if [ -z "$log_file" ] || [ ! -f "$log_file" ]; then
        echo -e "${YELLOW}No log file for session '$name'${NC}" >&2
        return 1
    fi

    echo -e "${CYAN}Following logs for '$name' (Ctrl+C to stop)${NC}"
    tail -f "$log_file"
}

# Stop a session
cmd_stop() {
    local name="${1:-}"
    local force=false

    [ "$1" = "-f" ] && { force=true; shift; name="${1:-}"; }

    if [ -z "$name" ]; then
        echo "Usage: session-manager.sh stop <name>" >&2
        return 1
    fi

    if ! session_exists "$name"; then
        echo -e "${RED}Session '$name' not found${NC}" >&2
        return 1
    fi

    if ! session_running "$name"; then
        echo -e "${YELLOW}Session '$name' is not running${NC}"
        return 0
    fi

    local pid_file
    pid_file=$(get_pid_file "$name")
    local pid
    pid=$(cat "$pid_file")

    if [ "$force" = true ]; then
        kill -9 "$pid" 2>/dev/null || true
        echo -e "${YELLOW}Force killed session '$name' (PID: $pid)${NC}"
    else
        kill "$pid" 2>/dev/null || true
        echo -e "${GREEN}Stopped session '$name' (PID: $pid)${NC}"
    fi

    update_session_info "$name" "status" "stopped"
    update_session_info "$name" "stopped_at" "$(date -Iseconds)"
}

# Kill a session (force)
cmd_kill() {
    cmd_stop -f "$@"
}

# Restart a session
cmd_restart() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "Usage: session-manager.sh restart <name>" >&2
        return 1
    fi

    if ! session_exists "$name"; then
        echo -e "${RED}Session '$name' not found${NC}" >&2
        return 1
    fi

    # Get session info
    local session_file
    session_file=$(get_session_file "$name")
    local command workdir
    command=$(jq -r '.command' "$session_file")
    workdir=$(jq -r '.workdir' "$session_file")

    # Stop if running
    if session_running "$name"; then
        cmd_stop "$name"
        sleep 1
    fi

    # Increment restart counter
    local restarts
    restarts=$(jq -r '.restarts // 0' "$session_file")
    restarts=$((restarts + 1))
    update_session_info "$name" "restarts" "$restarts"

    # Start again
    cmd_start -n "$name" -d "$workdir" "$command"
}

# Clean up old sessions
cmd_clean() {
    local force=false
    local max_age=86400  # 24 hours

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=true; shift ;;
            --max-age) max_age="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local cleaned=0

    for session_file in "$SESSION_DIR"/*.json; do
        [ -f "$session_file" ] || continue

        local name
        name=$(jq -r '.name' "$session_file")

        # Skip running sessions
        if session_running "$name"; then
            continue
        fi

        # Check age
        local file_age
        file_age=$(($(date +%s) - $(stat -c %Y "$session_file")))

        if [ "$force" = true ] || [ "$file_age" -gt "$max_age" ]; then
            # Remove session files
            rm -f "$session_file"
            rm -f "$(get_pid_file "$name")"
            rm -f "$(get_log_file "$name")"
            cleaned=$((cleaned + 1))
            echo -e "${GRAY}Cleaned: $name${NC}"
        fi
    done

    echo -e "${GREEN}Cleaned $cleaned session(s)${NC}"
}

# Attach to session (interactive)
cmd_attach() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "Usage: session-manager.sh attach <name>" >&2
        return 1
    fi

    if ! session_exists "$name"; then
        echo -e "${RED}Session '$name' not found${NC}" >&2
        return 1
    fi

    local log_file
    log_file=$(jq -r '.log_file // empty' "$(get_session_file "$name")")

    if [ -z "$log_file" ] || [ ! -f "$log_file" ]; then
        echo -e "${YELLOW}No log file for session '$name'${NC}" >&2
        return 1
    fi

    local pid
    pid=$(jq -r '.pid // 0' "$(get_session_file "$name")")
    local is_running=false
    session_running "$name" && is_running=true

    echo -e "${CYAN}=== Attached to session '$name' ===${NC}"
    echo -e "PID: $pid | Status: $([ "$is_running" = true ] && echo -e "${GREEN}running${NC}" || echo -e "${RED}stopped${NC}")"
    echo -e "Log: $log_file"
    echo -e "${GRAY}Press Ctrl+C to detach${NC}"
    echo ""

    # Show last 20 lines then follow
    tail -n 20 -f "$log_file"
}

# Main command dispatch
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        start)
            cmd_start "$@"
            ;;
        list|ls)
            cmd_list "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        logs|log)
            cmd_logs "$@"
            ;;
        tail|follow)
            cmd_tail "$@"
            ;;
        stop)
            cmd_stop "$@"
            ;;
        kill)
            cmd_kill "$@"
            ;;
        restart)
            cmd_restart "$@"
            ;;
        clean|cleanup)
            cmd_clean "$@"
            ;;
        attach)
            cmd_attach "$@"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}" >&2
            echo "Run 'session-manager.sh help' for usage" >&2
            return 1
            ;;
    esac
}

main "$@"

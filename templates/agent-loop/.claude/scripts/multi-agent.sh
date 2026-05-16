#!/bin/bash

# Multi-Agent Coordination System
# Spawns and manages worker Claude agents for parallel task execution
# Usage: multi-agent.sh <command> [options]

set -euo pipefail

WORKSPACE="/agent-workspace"
AGENT_DIR="$WORKSPACE/.claude/agents"
RESULTS_DIR="$AGENT_DIR/results"
LOG_DIR="$AGENT_DIR/logs"
STATE_FILE="$AGENT_DIR/state.json"

# Ensure directories exist
mkdir -p "$AGENT_DIR" "$RESULTS_DIR" "$LOG_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat <<EOF
Multi-Agent Coordination System

Usage: multi-agent.sh <command> [options]

Commands:
  spawn       Spawn a new worker agent
  list        List all agents (active and completed)
  status      Show status of an agent
  results     Get results from an agent
  stop        Stop a running agent
  stopall     Stop all running agents
  clean       Remove completed agents
  parallel    Run multiple prompts in parallel
  map         Map a command over multiple inputs

Spawn Options:
  -n, --name NAME       Agent name (default: auto-generated)
  -p, --prompt PROMPT   Task prompt for the agent
  -f, --file FILE       Read prompt from file
  -t, --timeout SECS    Timeout in seconds (default: 300)
  --max-turns N         Max conversation turns (default: 10)
  --model MODEL         Model to use (default: current)

Parallel Options:
  --prompts FILE        File with one prompt per line
  --max-concurrent N    Max concurrent agents (default: 3)
  --collect FILE        Collect all results to file

Examples:
  # Spawn a single worker agent
  multi-agent.sh spawn -n analyzer -p "Analyze the code in /project and list issues"

  # Run prompts in parallel
  multi-agent.sh parallel --prompts tasks.txt --max-concurrent 5

  # Map a command over inputs
  echo -e "file1.py\nfile2.py" | multi-agent.sh map "Review the code in {}"

  # Check agent status
  multi-agent.sh status analyzer

  # Get results
  multi-agent.sh results analyzer
EOF
}

# Generate unique agent ID
generate_agent_id() {
    echo "agent_$(date +%Y%m%d_%H%M%S)_$$_$RANDOM"
}

# Initialize state file
init_state() {
    if [ ! -f "$STATE_FILE" ]; then
        echo '{"agents": {}, "created_at": "'"$(date -Iseconds)"'"}' > "$STATE_FILE"
    fi
}

# Get agent info
get_agent() {
    local name="$1"
    init_state
    jq -r --arg n "$name" '.agents[$n] // empty' "$STATE_FILE"
}

# Update agent info
update_agent() {
    local name="$1"
    local key="$2"
    local value="$3"
    init_state
    local tmp=$(mktemp)
    jq --arg n "$name" --arg k "$key" --arg v "$value" \
        '.agents[$n][$k] = $v' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# Set agent (full object)
set_agent() {
    local name="$1"
    local data="$2"
    init_state
    local tmp=$(mktemp)
    jq --arg n "$name" --argjson d "$data" \
        '.agents[$n] = $d' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# Remove agent from state
remove_agent() {
    local name="$1"
    init_state
    local tmp=$(mktemp)
    jq --arg n "$name" 'del(.agents[$n])' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# Check if agent is running
agent_running() {
    local name="$1"
    local pid=$(get_agent "$name" | jq -r '.pid // 0')
    [ "$pid" != "0" ] && [ "$pid" != "null" ] && kill -0 "$pid" 2>/dev/null
}

# Spawn a worker agent
cmd_spawn() {
    local name=""
    local prompt=""
    local prompt_file=""
    local timeout=300
    local max_turns=10
    local model=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--name) name="$2"; shift 2 ;;
            -p|--prompt) prompt="$2"; shift 2 ;;
            -f|--file) prompt_file="$2"; shift 2 ;;
            -t|--timeout) timeout="$2"; shift 2 ;;
            --max-turns) max_turns="$2"; shift 2 ;;
            --model) model="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Generate name if not provided
    [ -z "$name" ] && name=$(generate_agent_id)

    # Read prompt from file if specified
    if [ -n "$prompt_file" ] && [ -f "$prompt_file" ]; then
        prompt=$(cat "$prompt_file")
    fi

    if [ -z "$prompt" ]; then
        echo -e "${RED}Error: No prompt specified${NC}" >&2
        return 1
    fi

    # Check if agent already exists and is running
    if agent_running "$name" 2>/dev/null; then
        echo -e "${RED}Error: Agent '$name' is already running${NC}" >&2
        return 1
    fi

    local log_file="$LOG_DIR/${name}.log"
    local result_file="$RESULTS_DIR/${name}.md"

    # Create agent state
    local agent_data=$(jq -n \
        --arg name "$name" \
        --arg prompt "$prompt" \
        --arg status "starting" \
        --arg started_at "$(date -Iseconds)" \
        --argjson timeout "$timeout" \
        --argjson max_turns "$max_turns" \
        --arg log_file "$log_file" \
        --arg result_file "$result_file" \
        '{
            name: $name,
            prompt: $prompt,
            status: $status,
            started_at: $started_at,
            timeout: $timeout,
            max_turns: $max_turns,
            log_file: $log_file,
            result_file: $result_file
        }')

    set_agent "$name" "$agent_data"

    # Build claude command
    local claude_cmd="claude --dangerously-skip-permissions"
    [ -n "$model" ] && claude_cmd="$claude_cmd --model $model"
    claude_cmd="$claude_cmd --max-turns $max_turns"
    claude_cmd="$claude_cmd -p"

    # Create wrapper script for the agent
    local wrapper=$(mktemp)
    cat > "$wrapper" <<WRAPPER
#!/bin/bash
cd "$WORKSPACE"

# Write result header
cat > "$result_file" <<'HEADER'
# Agent: $name
Started: $(date -Iseconds)
Prompt: $prompt

## Output
HEADER

# Run claude and capture output
$claude_cmd "$prompt" >> "$result_file" 2>&1
EXIT_CODE=\$?

# Write completion marker
cat >> "$result_file" <<FOOTER

---
Completed: \$(date -Iseconds)
Exit Code: \$EXIT_CODE
FOOTER

exit \$EXIT_CODE
WRAPPER
    chmod +x "$wrapper"

    # Start the agent in background
    nohup bash "$wrapper" > "$log_file" 2>&1 &
    local pid=$!

    # Update state with PID
    update_agent "$name" "pid" "$pid"
    update_agent "$name" "status" "running"

    # Set up timeout
    (
        sleep "$timeout"
        if kill -0 "$pid" 2>/dev/null; then
            echo "[$(date -Iseconds)] Timeout reached, killing agent" >> "$log_file"
            kill "$pid" 2>/dev/null || true
        fi
    ) &

    # Clean up wrapper after delay
    (sleep 5 && rm -f "$wrapper") &

    echo -e "${GREEN}Spawned agent '$name'${NC}"
    echo -e "  PID: $pid"
    echo -e "  Timeout: ${timeout}s"
    echo -e "  Log: $log_file"
    echo -e "  Results: $result_file"
}

# List all agents
cmd_list() {
    local show_all=false
    local json_output=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all) show_all=true; shift ;;
            --json) json_output=true; shift ;;
            *) shift ;;
        esac
    done

    init_state

    if [ "$json_output" = true ]; then
        jq '.agents' "$STATE_FILE"
        return
    fi

    echo -e "${CYAN}=== Agents ===${NC}"

    local agents=$(jq -r '.agents | keys[]' "$STATE_FILE" 2>/dev/null)

    if [ -z "$agents" ]; then
        echo -e "${YELLOW}No agents found${NC}"
        return
    fi

    while IFS= read -r name; do
        local info=$(get_agent "$name")
        local status=$(echo "$info" | jq -r '.status // "unknown"')
        local pid=$(echo "$info" | jq -r '.pid // 0')
        local started=$(echo "$info" | jq -r '.started_at // ""')

        # Update status based on actual process
        local is_running=false
        if [ "$pid" != "0" ] && [ "$pid" != "null" ] && kill -0 "$pid" 2>/dev/null; then
            is_running=true
            status="running"
        elif [ "$status" = "running" ]; then
            status="completed"
            update_agent "$name" "status" "completed"
        fi

        if [ "$show_all" = false ] && [ "$is_running" = false ]; then
            continue
        fi

        local status_color=$YELLOW
        [ "$status" = "running" ] && status_color=$GREEN
        [ "$status" = "completed" ] && status_color=$BLUE
        [ "$status" = "failed" ] && status_color=$RED

        echo -e "\n${CYAN}$name${NC}"
        echo -e "  Status: ${status_color}${status}${NC}"
        echo -e "  PID: $pid"
        echo -e "  Started: $started"
    done <<< "$agents"
}

# Show agent status
cmd_status() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "Usage: multi-agent.sh status <name>" >&2
        return 1
    fi

    local info=$(get_agent "$name")

    if [ -z "$info" ]; then
        echo -e "${RED}Agent '$name' not found${NC}" >&2
        return 1
    fi

    local pid=$(echo "$info" | jq -r '.pid // 0')
    local status=$(echo "$info" | jq -r '.status // "unknown"')

    # Check actual running state
    if [ "$pid" != "0" ] && [ "$pid" != "null" ] && kill -0 "$pid" 2>/dev/null; then
        status="running"
    elif [ "$status" = "running" ]; then
        status="completed"
    fi

    echo -e "${CYAN}=== Agent: $name ===${NC}"
    echo "$info" | jq -r '
        "Status: \(.status // "unknown")",
        "PID: \(.pid // "N/A")",
        "Started: \(.started_at // "N/A")",
        "Timeout: \(.timeout // 300)s",
        "Max Turns: \(.max_turns // 10)",
        "Log: \(.log_file // "N/A")",
        "Results: \(.result_file // "N/A")"
    '

    echo -e "\nActual Status: ${status}"

    # Show resource usage if running
    if [ "$pid" != "0" ] && [ "$pid" != "null" ] && kill -0 "$pid" 2>/dev/null; then
        echo -e "\n${CYAN}Resource Usage:${NC}"
        ps -p "$pid" -o %cpu,%mem,etime --no-headers 2>/dev/null | awk '{
            printf "  CPU: %s%%\n  Memory: %s%%\n  Runtime: %s\n", $1, $2, $3
        }'
    fi
}

# Get agent results
cmd_results() {
    local name="${1:-}"
    local follow=false

    [ "$1" = "-f" ] && { follow=true; shift; name="${1:-}"; }

    if [ -z "$name" ]; then
        echo "Usage: multi-agent.sh results [-f] <name>" >&2
        return 1
    fi

    local info=$(get_agent "$name")

    if [ -z "$info" ]; then
        echo -e "${RED}Agent '$name' not found${NC}" >&2
        return 1
    fi

    local result_file=$(echo "$info" | jq -r '.result_file // ""')

    if [ -z "$result_file" ] || [ ! -f "$result_file" ]; then
        echo -e "${YELLOW}No results yet for agent '$name'${NC}" >&2
        return 1
    fi

    if [ "$follow" = true ]; then
        tail -f "$result_file"
    else
        cat "$result_file"
    fi
}

# Stop an agent
cmd_stop() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "Usage: multi-agent.sh stop <name>" >&2
        return 1
    fi

    local info=$(get_agent "$name")

    if [ -z "$info" ]; then
        echo -e "${RED}Agent '$name' not found${NC}" >&2
        return 1
    fi

    local pid=$(echo "$info" | jq -r '.pid // 0')

    if [ "$pid" = "0" ] || [ "$pid" = "null" ]; then
        echo -e "${YELLOW}Agent '$name' has no PID${NC}"
        return 0
    fi

    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        update_agent "$name" "status" "stopped"
        echo -e "${GREEN}Stopped agent '$name' (PID: $pid)${NC}"
    else
        echo -e "${YELLOW}Agent '$name' is not running${NC}"
        update_agent "$name" "status" "completed"
    fi
}

# Stop all agents
cmd_stopall() {
    init_state

    local agents=$(jq -r '.agents | keys[]' "$STATE_FILE" 2>/dev/null)

    if [ -z "$agents" ]; then
        echo -e "${YELLOW}No agents to stop${NC}"
        return
    fi

    local stopped=0
    while IFS= read -r name; do
        local pid=$(get_agent "$name" | jq -r '.pid // 0')
        if [ "$pid" != "0" ] && [ "$pid" != "null" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            update_agent "$name" "status" "stopped"
            stopped=$((stopped + 1))
        fi
    done <<< "$agents"

    echo -e "${GREEN}Stopped $stopped agent(s)${NC}"
}

# Clean up completed agents
cmd_clean() {
    local max_age=${1:-86400}  # Default: 24 hours

    init_state

    local agents=$(jq -r '.agents | keys[]' "$STATE_FILE" 2>/dev/null)
    local cleaned=0

    while IFS= read -r name; do
        [ -z "$name" ] && continue

        local info=$(get_agent "$name")
        local pid=$(echo "$info" | jq -r '.pid // 0')
        local status=$(echo "$info" | jq -r '.status // "unknown"')

        # Skip running agents
        if [ "$pid" != "0" ] && [ "$pid" != "null" ] && kill -0 "$pid" 2>/dev/null; then
            continue
        fi

        # Remove agent state and files
        local log_file=$(echo "$info" | jq -r '.log_file // ""')
        local result_file=$(echo "$info" | jq -r '.result_file // ""')

        [ -f "$log_file" ] && rm -f "$log_file"
        [ -f "$result_file" ] && rm -f "$result_file"
        remove_agent "$name"
        cleaned=$((cleaned + 1))
    done <<< "$agents"

    echo -e "${GREEN}Cleaned $cleaned agent(s)${NC}"
}

# Run prompts in parallel
cmd_parallel() {
    local prompts_file=""
    local max_concurrent=3
    local collect_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prompts) prompts_file="$2"; shift 2 ;;
            --max-concurrent) max_concurrent="$2"; shift 2 ;;
            --collect) collect_file="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [ -z "$prompts_file" ] || [ ! -f "$prompts_file" ]; then
        echo -e "${RED}Error: Prompts file required${NC}" >&2
        return 1
    fi

    local agents=()
    local running=0
    local line_num=0

    echo -e "${CYAN}Starting parallel execution (max $max_concurrent concurrent)${NC}"

    while IFS= read -r prompt; do
        [ -z "$prompt" ] && continue
        line_num=$((line_num + 1))

        # Wait if at max concurrent
        while [ "$running" -ge "$max_concurrent" ]; do
            sleep 2
            running=0
            for agent in "${agents[@]}"; do
                if agent_running "$agent" 2>/dev/null; then
                    running=$((running + 1))
                fi
            done
        done

        # Spawn new agent
        local name="parallel_${line_num}_$(date +%s)"
        cmd_spawn -n "$name" -p "$prompt" > /dev/null
        agents+=("$name")
        running=$((running + 1))

        echo -e "  Started: $name"
    done < "$prompts_file"

    echo -e "\n${CYAN}Waiting for all agents to complete...${NC}"

    # Wait for all to complete
    for agent in "${agents[@]}"; do
        while agent_running "$agent" 2>/dev/null; do
            sleep 2
        done
        echo -e "  Completed: $agent"
    done

    # Collect results if requested
    if [ -n "$collect_file" ]; then
        echo -e "\n${CYAN}Collecting results to $collect_file${NC}"
        > "$collect_file"
        for agent in "${agents[@]}"; do
            echo -e "\n# $agent\n" >> "$collect_file"
            cmd_results "$agent" >> "$collect_file" 2>/dev/null || true
        done
    fi

    echo -e "\n${GREEN}Parallel execution complete${NC}"
}

# Map command over inputs
cmd_map() {
    local template="${1:-}"

    if [ -z "$template" ]; then
        echo "Usage: echo inputs | multi-agent.sh map \"command with {}\"" >&2
        return 1
    fi

    local agents=()

    while IFS= read -r input; do
        [ -z "$input" ] && continue

        local prompt="${template//\{\}/$input}"
        local name="map_$(echo "$input" | md5sum | cut -c1-8)"

        cmd_spawn -n "$name" -p "$prompt" > /dev/null
        agents+=("$name")
        echo -e "Spawned: $name for '$input'"
    done

    echo -e "\n${CYAN}Waiting for completion...${NC}"

    for agent in "${agents[@]}"; do
        while agent_running "$agent" 2>/dev/null; do
            sleep 2
        done
    done

    echo -e "\n${GREEN}Map complete. Use 'multi-agent.sh results <name>' to view results.${NC}"
}

# Main
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        spawn) cmd_spawn "$@" ;;
        list|ls) cmd_list "$@" ;;
        status) cmd_status "$@" ;;
        results|result) cmd_results "$@" ;;
        stop) cmd_stop "$@" ;;
        stopall) cmd_stopall "$@" ;;
        clean) cmd_clean "$@" ;;
        parallel) cmd_parallel "$@" ;;
        map) cmd_map "$@" ;;
        help|--help|-h) usage ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}" >&2
            usage
            return 1
            ;;
    esac
}

main "$@"

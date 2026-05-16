#!/bin/bash

# Interactive Terminal Dashboard for Agent Monitoring
# Provides real-time view of agent status, tasks, and resources

set -euo pipefail

WORKSPACE="/agent-workspace"
TASKS_FILE="$WORKSPACE/.claude/loop/tasks.md"
MEMORY_FILE="$WORKSPACE/.claude/loop/memory.md"
STATE_FILE="$WORKSPACE/.claude/loop/state.json"
LOCK_FILE="$WORKSPACE/.claude/loop/claude.lock"
NOTIFICATIONS_FILE="$WORKSPACE/.claude/notifications.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Refresh interval in seconds
REFRESH_INTERVAL=${1:-5}

# Clear screen and move cursor to top
clear_screen() {
    printf '\033[2J\033[H'
}

# Move cursor to position
move_cursor() {
    printf '\033[%d;%dH' "$1" "$2"
}

# Draw a horizontal line
draw_line() {
    local width=${1:-$(tput cols)}
    printf '%*s\n' "$width" '' | tr ' ' '─'
}

# Draw a box header
draw_header() {
    local title="$1"
    local width=$(tput cols)
    echo -e "${BOLD}${CYAN}┌$(printf '─%.0s' $(seq 1 $((width-2))))┐${NC}"
    printf "${BOLD}${CYAN}│${NC} %-$((width-4))s ${BOLD}${CYAN}│${NC}\n" "$title"
    echo -e "${BOLD}${CYAN}├$(printf '─%.0s' $(seq 1 $((width-2))))┤${NC}"
}

# Get agent status
get_agent_status() {
    if [ -f "$LOCK_FILE" ]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo -e "${GREEN}● RUNNING${NC} (PID: $pid)"
        else
            echo -e "${YELLOW}◐ STALE LOCK${NC}"
        fi
    else
        echo -e "${DIM}○ IDLE${NC}"
    fi
}

# Get iteration count
get_iteration() {
    if [ -f "$STATE_FILE" ]; then
        local iter=$(jq -r '.iteration // 0' "$STATE_FILE" 2>/dev/null || echo "0")
        local updated=$(jq -r '.updated_at // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
        echo "Iteration: $iter | Last: $updated"
    else
        echo "Iteration: 0 | No state file"
    fi
}

# Count tasks by status
count_tasks() {
    local status="$1"
    local pattern=""
    case "$status" in
        pending) pattern='^\- \[ \]' ;;
        progress) pattern='^\- \[\.\]' ;;
        complete) pattern='^\- \[x\]' ;;
    esac
    grep -c "$pattern" "$TASKS_FILE" 2>/dev/null || echo "0"
}

# Get recent tasks
get_recent_tasks() {
    local count=${1:-5}
    if [ -f "$TASKS_FILE" ]; then
        grep -E '^\- \[' "$TASKS_FILE" 2>/dev/null | tail -n "$count" | while read -r line; do
            if [[ "$line" == *"[x]"* ]]; then
                echo -e "  ${GREEN}✓${NC} ${line#*] }" | head -c 70
                echo
            elif [[ "$line" == *"[.]"* ]]; then
                echo -e "  ${YELLOW}◐${NC} ${line#*] }" | head -c 70
                echo
            else
                echo -e "  ${DIM}○${NC} ${line#*] }" | head -c 70
                echo
            fi
        done
    fi
}

# Get system resources
get_resources() {
    # CPU load
    local load=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | tr -d ' ')

    # Memory
    local mem_info=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')

    # Disk
    local disk_info=$(df -h "$WORKSPACE" | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')

    echo -e "CPU Load: ${CYAN}$load${NC} | Memory: ${CYAN}$mem_info${NC} | Disk: ${CYAN}$disk_info${NC}"
}

# Get recent notifications
get_notifications() {
    local count=${1:-3}
    if [ -f "$NOTIFICATIONS_FILE" ]; then
        grep -E '^\[' "$NOTIFICATIONS_FILE" 2>/dev/null | tail -n "$count" | while read -r line; do
            echo "  $line" | head -c 75
            echo
        done
    else
        echo "  No notifications"
    fi
}

# Get memory summary (last updated line)
get_memory_summary() {
    if [ -f "$MEMORY_FILE" ]; then
        grep "^## Last Updated" -A1 "$MEMORY_FILE" 2>/dev/null | tail -1 | head -c 70
        echo
    else
        echo "No memory file"
    fi
}

# Main dashboard render
render_dashboard() {
    clear_screen

    local width=$(tput cols)
    local now=$(date '+%Y-%m-%d %H:%M:%S')

    # Header
    echo -e "${BOLD}${MAGENTA}"
    echo "   ╔═══════════════════════════════════════════════════════════════╗"
    echo "   ║           🤖 CLAUDE AGENT MONITORING DASHBOARD 🤖             ║"
    echo "   ╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Status bar
    echo -e "${DIM}Last refresh: $now | Refresh every ${REFRESH_INTERVAL}s | Press Ctrl+C to exit${NC}"
    echo

    # Agent Status Section
    echo -e "${BOLD}${BLUE}▸ AGENT STATUS${NC}"
    draw_line 60
    echo -e "  Status: $(get_agent_status)"
    echo -e "  $(get_iteration)"
    echo

    # Tasks Section
    echo -e "${BOLD}${BLUE}▸ TASK QUEUE${NC}"
    draw_line 60
    local pending=$(count_tasks pending)
    local progress=$(count_tasks progress)
    local complete=$(count_tasks complete)
    echo -e "  ${DIM}○${NC} Pending: ${YELLOW}$pending${NC}  ${YELLOW}◐${NC} In Progress: ${CYAN}$progress${NC}  ${GREEN}✓${NC} Complete: ${GREEN}$complete${NC}"
    echo
    echo -e "  ${DIM}Recent tasks:${NC}"
    get_recent_tasks 5
    echo

    # Resources Section
    echo -e "${BOLD}${BLUE}▸ SYSTEM RESOURCES${NC}"
    draw_line 60
    echo -e "  $(get_resources)"
    echo

    # Memory Section
    echo -e "${BOLD}${BLUE}▸ MEMORY (Last Update)${NC}"
    draw_line 60
    echo -e "  $(get_memory_summary)"
    echo

    # Notifications Section
    echo -e "${BOLD}${BLUE}▸ RECENT NOTIFICATIONS${NC}"
    draw_line 60
    get_notifications 3
    echo

    # Footer
    echo -e "${DIM}$(draw_line 60)${NC}"
    echo -e "${DIM}Workspace: $WORKSPACE${NC}"
}

# Handle cleanup on exit
cleanup() {
    clear_screen
    echo "Dashboard closed."
    exit 0
}

trap cleanup SIGINT SIGTERM

# Main loop
main() {
    while true; do
        render_dashboard
        sleep "$REFRESH_INTERVAL"
    done
}

# Run
main

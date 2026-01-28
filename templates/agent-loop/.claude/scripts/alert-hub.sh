#!/bin/bash
#
# Alert Hub - Unified Notification Aggregator
# Combine all alert channels into a single routing system
#
# Usage: alert-hub.sh <command> [options]
#   send <level> <message>    Send alert through configured channels
#   config                    Show current configuration
#   test                      Test all channels
#   history                   Show recent alerts
#   rules                     List routing rules
#   add-rule <rule>           Add routing rule
#   -h, --help                Show help

set -uo pipefail

WORKSPACE="/agent-workspace"
CONFIG_DIR="$WORKSPACE/.claude/alert-hub"
CONFIG_FILE="$CONFIG_DIR/config.json"
HISTORY_FILE="$CONFIG_DIR/history.jsonl"
RULES_FILE="$CONFIG_DIR/rules.json"

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
Alert Hub - Unified Notification Aggregator

Usage: alert-hub.sh <command> [options]

Commands:
  send <level> <message>    Send alert (level: info, warning, error, critical)
  config                    Show current configuration
  set <channel> <setting>   Configure a channel
  test [channel]            Test channel(s)
  history [count]           Show recent alerts (default: 10)
  rules                     List routing rules
  add-rule <rule>           Add routing rule
  stats                     Show alert statistics

Alert Levels:
  info      - Informational messages
  warning   - Warning conditions
  error     - Error conditions (default escalation)
  critical  - Critical alerts (all channels)

Channels:
  file      - Write to notification files (always enabled)
  webhook   - Send to configured webhooks
  email     - Send email (if configured)
  desktop   - Desktop notification (if available)

Routing Rules:
  Rules determine which channels receive which alerts
  Default: info->file, warning->file, error->file+webhook, critical->all

Examples:
  alert-hub.sh send info "Backup completed successfully"
  alert-hub.sh send error "Database connection failed"
  alert-hub.sh send critical "System out of memory"
  alert-hub.sh config
  alert-hub.sh test webhook
  alert-hub.sh history 20
EOF
}

# Initialize configuration
init_config() {
    mkdir -p "$CONFIG_DIR"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'JSON'
{
  "channels": {
    "file": {
      "enabled": true,
      "path": "/agent-workspace/.claude/notifications"
    },
    "webhook": {
      "enabled": false,
      "url": "",
      "type": "generic"
    },
    "email": {
      "enabled": false,
      "to": "",
      "from": "alerts@agent",
      "smtp_host": ""
    },
    "desktop": {
      "enabled": false
    }
  },
  "defaults": {
    "throttle_seconds": 60,
    "max_history": 1000
  }
}
JSON
    fi

    if [[ ! -f "$RULES_FILE" ]]; then
        cat > "$RULES_FILE" << 'JSON'
{
  "rules": [
    {"level": "info", "channels": ["file"]},
    {"level": "warning", "channels": ["file"]},
    {"level": "error", "channels": ["file", "webhook"]},
    {"level": "critical", "channels": ["file", "webhook", "email", "desktop"]}
  ]
}
JSON
    fi

    [[ -f "$HISTORY_FILE" ]] || touch "$HISTORY_FILE"
}

# Get channel config
get_channel_config() {
    local channel="$1"
    jq -r ".channels.$channel" "$CONFIG_FILE"
}

# Check if channel is enabled
is_channel_enabled() {
    local channel="$1"
    local enabled
    enabled=$(jq -r ".channels.$channel.enabled" "$CONFIG_FILE")
    [[ "$enabled" == "true" ]]
}

# Get channels for alert level
get_channels_for_level() {
    local level="$1"
    jq -r ".rules[] | select(.level == \"$level\") | .channels[]" "$RULES_FILE"
}

# Send to file channel
send_file() {
    local level="$1"
    local message="$2"
    local timestamp="$3"

    local path
    path=$(jq -r '.channels.file.path' "$CONFIG_FILE")
    mkdir -p "$path"

    local filename="${timestamp}-${level}.md"
    filename="${filename//:/-}"

    cat > "$path/$filename" << EOF
# Alert: $level

**Time:** $timestamp
**Level:** $level

## Message

$message
EOF

    echo -e "  ${GREEN}✓${NC} File: $path/$filename"
}

# Send to webhook channel
send_webhook() {
    local level="$1"
    local message="$2"
    local timestamp="$3"

    local url
    url=$(jq -r '.channels.webhook.url' "$CONFIG_FILE")

    if [[ -z "$url" || "$url" == "null" ]]; then
        echo -e "  ${YELLOW}⚠${NC} Webhook: Not configured"
        return 1
    fi

    local webhook_type
    webhook_type=$(jq -r '.channels.webhook.type' "$CONFIG_FILE")

    local payload
    case "$webhook_type" in
        slack)
            local color="good"
            [[ "$level" == "warning" ]] && color="warning"
            [[ "$level" == "error" || "$level" == "critical" ]] && color="danger"
            payload=$(cat << EOF
{
  "attachments": [{
    "color": "$color",
    "title": "Alert: $level",
    "text": "$message",
    "ts": $(date +%s)
  }]
}
EOF
)
            ;;
        discord)
            local color=3066993
            [[ "$level" == "warning" ]] && color=16776960
            [[ "$level" == "error" ]] && color=15158332
            [[ "$level" == "critical" ]] && color=10038562
            payload=$(cat << EOF
{
  "embeds": [{
    "title": "Alert: $level",
    "description": "$message",
    "color": $color,
    "timestamp": "$timestamp"
  }]
}
EOF
)
            ;;
        *)
            payload=$(cat << EOF
{
  "level": "$level",
  "message": "$message",
  "timestamp": "$timestamp",
  "source": "alert-hub"
}
EOF
)
            ;;
    esac

    if curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$url" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Webhook: Sent"
    else
        echo -e "  ${RED}✗${NC} Webhook: Failed"
        return 1
    fi
}

# Send desktop notification
send_desktop() {
    local level="$1"
    local message="$2"

    if command -v notify-send &>/dev/null; then
        local urgency="normal"
        [[ "$level" == "critical" ]] && urgency="critical"
        [[ "$level" == "error" ]] && urgency="critical"

        notify-send -u "$urgency" "Alert: $level" "$message" 2>/dev/null
        echo -e "  ${GREEN}✓${NC} Desktop: Sent"
    else
        echo -e "  ${YELLOW}⚠${NC} Desktop: notify-send not available"
        return 1
    fi
}

# Log to history
log_history() {
    local level="$1"
    local message="$2"
    local timestamp="$3"
    local channels="$4"

    # Escape message for JSON
    local escaped_message
    escaped_message=$(echo "$message" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')

    echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$escaped_message\",\"channels\":\"$channels\"}" >> "$HISTORY_FILE"

    # Trim history if too long
    local max_history
    max_history=$(jq -r '.defaults.max_history' "$CONFIG_FILE")
    local current_count
    current_count=$(wc -l < "$HISTORY_FILE")

    if [[ $current_count -gt $max_history ]]; then
        local to_remove=$((current_count - max_history))
        tail -n +"$((to_remove + 1))" "$HISTORY_FILE" > "$HISTORY_FILE.tmp"
        mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
    fi
}

# Send alert
cmd_send() {
    local level="$1"
    local message="$2"

    # Validate level
    case "$level" in
        info|warning|error|critical) ;;
        *)
            echo -e "${RED}Error:${NC} Invalid level: $level"
            echo "Valid levels: info, warning, error, critical"
            return 1
            ;;
    esac

    init_config

    local timestamp
    timestamp=$(date -Iseconds)

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Sending Alert: $level"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Message: $message"
    echo ""

    # Get channels for this level
    local channels_sent=""
    local channels
    channels=$(get_channels_for_level "$level")

    echo "Routing to channels:"
    while IFS= read -r channel; do
        [[ -z "$channel" ]] && continue

        if is_channel_enabled "$channel"; then
            case "$channel" in
                file)
                    send_file "$level" "$message" "$timestamp"
                    channels_sent+="file,"
                    ;;
                webhook)
                    send_webhook "$level" "$message" "$timestamp"
                    channels_sent+="webhook,"
                    ;;
                desktop)
                    send_desktop "$level" "$message"
                    channels_sent+="desktop,"
                    ;;
                email)
                    echo -e "  ${YELLOW}⚠${NC} Email: Not implemented"
                    ;;
            esac
        else
            echo -e "  ${GRAY}○${NC} $channel: Disabled"
        fi
    done <<< "$channels"

    # Log to history
    log_history "$level" "$message" "$timestamp" "${channels_sent%,}"

    echo ""
    echo -e "${GREEN}Alert sent${NC}"
}

# Show config
cmd_config() {
    init_config

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Alert Hub Configuration                                      ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${CYAN}Channels:${NC}"
    echo "─────────────────────────────────────────"

    for channel in file webhook email desktop; do
        local enabled
        enabled=$(jq -r ".channels.$channel.enabled" "$CONFIG_FILE")
        local status_icon="○"
        local status_color="$GRAY"
        if [[ "$enabled" == "true" ]]; then
            status_icon="●"
            status_color="$GREEN"
        fi

        echo -e "  ${status_color}${status_icon}${NC} $channel"

        # Show channel-specific settings
        case "$channel" in
            file)
                local path
                path=$(jq -r '.channels.file.path' "$CONFIG_FILE")
                echo "    Path: $path"
                ;;
            webhook)
                local url type
                url=$(jq -r '.channels.webhook.url' "$CONFIG_FILE")
                type=$(jq -r '.channels.webhook.type' "$CONFIG_FILE")
                [[ "$url" != "null" && -n "$url" ]] && echo "    URL: ${url:0:50}..."
                echo "    Type: $type"
                ;;
            email)
                local to
                to=$(jq -r '.channels.email.to' "$CONFIG_FILE")
                [[ "$to" != "null" && -n "$to" ]] && echo "    To: $to"
                ;;
        esac
    done

    echo ""
    echo -e "${CYAN}Routing Rules:${NC}"
    echo "─────────────────────────────────────────"
    jq -r '.rules[] | "  \(.level): \(.channels | join(", "))"' "$RULES_FILE"

    echo ""
    echo -e "${CYAN}Defaults:${NC}"
    echo "─────────────────────────────────────────"
    echo "  Throttle: $(jq -r '.defaults.throttle_seconds' "$CONFIG_FILE")s"
    echo "  Max history: $(jq -r '.defaults.max_history' "$CONFIG_FILE")"
}

# Test channels
cmd_test() {
    local test_channel="${1:-all}"

    init_config

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Testing Alert Channels                                       ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local test_message="Test alert from alert-hub at $(date)"
    local timestamp
    timestamp=$(date -Iseconds)

    if [[ "$test_channel" == "all" ]]; then
        for channel in file webhook desktop; do
            echo -e "${CYAN}Testing $channel:${NC}"
            if is_channel_enabled "$channel"; then
                case "$channel" in
                    file) send_file "info" "$test_message" "$timestamp" ;;
                    webhook) send_webhook "info" "$test_message" "$timestamp" ;;
                    desktop) send_desktop "info" "$test_message" ;;
                esac
            else
                echo -e "  ${GRAY}Skipped (disabled)${NC}"
            fi
            echo ""
        done
    else
        echo -e "${CYAN}Testing $test_channel:${NC}"
        if is_channel_enabled "$test_channel"; then
            case "$test_channel" in
                file) send_file "info" "$test_message" "$timestamp" ;;
                webhook) send_webhook "info" "$test_message" "$timestamp" ;;
                desktop) send_desktop "info" "$test_message" ;;
                *) echo -e "${RED}Unknown channel:${NC} $test_channel" ;;
            esac
        else
            echo -e "  ${YELLOW}Channel is disabled${NC}"
        fi
    fi
}

# Show history
cmd_history() {
    local count="${1:-10}"

    init_config

    if [[ ! -f "$HISTORY_FILE" ]] || [[ ! -s "$HISTORY_FILE" ]]; then
        echo "No alert history"
        return
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Alert History (last $count)                                    ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    printf "%-20s %-10s %-40s\n" "TIME" "LEVEL" "MESSAGE"
    echo "─────────────────────────────────────────────────────────────────────"

    tail -"$count" "$HISTORY_FILE" | while read -r line; do
        local ts level msg
        ts=$(echo "$line" | jq -r '.timestamp' | cut -d'T' -f2 | cut -d'+' -f1 | cut -d'-' -f1)
        level=$(echo "$line" | jq -r '.level')
        msg=$(echo "$line" | jq -r '.message')

        # Color by level
        local color="$NC"
        case "$level" in
            info) color="$CYAN" ;;
            warning) color="$YELLOW" ;;
            error) color="$RED" ;;
            critical) color="$RED" ;;
        esac

        # Truncate message
        [[ ${#msg} -gt 40 ]] && msg="${msg:0:37}..."

        printf "%-20s ${color}%-10s${NC} %-40s\n" "$ts" "$level" "$msg"
    done
}

# Show rules
cmd_rules() {
    init_config

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Routing Rules                                                ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    jq -r '.rules[] | "\(.level):\n  Channels: \(.channels | join(", "))\n"' "$RULES_FILE"
}

# Show statistics
cmd_stats() {
    init_config

    if [[ ! -f "$HISTORY_FILE" ]] || [[ ! -s "$HISTORY_FILE" ]]; then
        echo "No alert history for statistics"
        return
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Alert Statistics                                             ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total
    total=$(wc -l < "$HISTORY_FILE" | tr -d ' ')
    total=${total:-0}
    echo "Total alerts: $total"
    echo ""

    echo "By Level:"
    local count pct bar bar_len
    for level in info warning error critical; do
        count=$(grep -c "\"level\":\"$level\"" "$HISTORY_FILE" 2>/dev/null || true)
        count=$(echo "$count" | tr -d '[:space:]')
        count=${count:-0}
        pct=0
        if [[ "$total" =~ ^[0-9]+$ ]] && [[ $total -gt 0 ]] && [[ "$count" =~ ^[0-9]+$ ]]; then
            pct=$((count * 100 / total))
        fi

        bar=""
        bar_len=$((pct / 5))
        for ((i=0; i<bar_len; i++)); do bar+="█"; done
        for ((i=bar_len; i<20; i++)); do bar+="░"; done

        printf "  %-10s %4d (%3d%%) %s\n" "$level" "$count" "$pct" "$bar"
    done

    echo ""
    echo "Recent activity:"
    local today yesterday
    today=$(date +%Y-%m-%d)
    yesterday=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null || echo "")

    local today_count yesterday_count
    today_count=$(grep -c "$today" "$HISTORY_FILE" 2>/dev/null || true)
    today_count=$(echo "$today_count" | tr -d '[:space:]')
    today_count=${today_count:-0}

    echo "  Today: $today_count"

    if [[ -n "$yesterday" ]]; then
        yesterday_count=$(grep -c "$yesterday" "$HISTORY_FILE" 2>/dev/null || true)
        yesterday_count=$(echo "$yesterday_count" | tr -d '[:space:]')
        yesterday_count=${yesterday_count:-0}
        echo "  Yesterday: $yesterday_count"
    fi
}

# Configure channel
cmd_set() {
    local channel="$1"
    local setting="$2"

    init_config

    case "$channel" in
        webhook)
            case "$setting" in
                enable)
                    jq '.channels.webhook.enabled = true' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
                    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                    echo -e "${GREEN}✓${NC} Webhook enabled"
                    ;;
                disable)
                    jq '.channels.webhook.enabled = false' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
                    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                    echo -e "${GREEN}✓${NC} Webhook disabled"
                    ;;
                url=*)
                    local url="${setting#url=}"
                    jq --arg url "$url" '.channels.webhook.url = $url' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
                    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                    echo -e "${GREEN}✓${NC} Webhook URL set"
                    ;;
                type=*)
                    local type="${setting#type=}"
                    jq --arg type "$type" '.channels.webhook.type = $type' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
                    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                    echo -e "${GREEN}✓${NC} Webhook type set to $type"
                    ;;
                *)
                    echo "Unknown setting: $setting"
                    echo "Available: enable, disable, url=<url>, type=<slack|discord|generic>"
                    ;;
            esac
            ;;
        desktop)
            case "$setting" in
                enable)
                    jq '.channels.desktop.enabled = true' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
                    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                    echo -e "${GREEN}✓${NC} Desktop notifications enabled"
                    ;;
                disable)
                    jq '.channels.desktop.enabled = false' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
                    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                    echo -e "${GREEN}✓${NC} Desktop notifications disabled"
                    ;;
                *)
                    echo "Unknown setting: $setting"
                    echo "Available: enable, disable"
                    ;;
            esac
            ;;
        *)
            echo "Unknown channel: $channel"
            echo "Available: webhook, desktop"
            ;;
    esac
}

# Main command dispatch
case "${1:-}" in
    send)
        if [[ $# -lt 3 ]]; then
            echo "Usage: alert-hub.sh send <level> <message>"
            exit 1
        fi
        cmd_send "$2" "$3"
        ;;
    config)
        cmd_config
        ;;
    set)
        if [[ $# -lt 3 ]]; then
            echo "Usage: alert-hub.sh set <channel> <setting>"
            exit 1
        fi
        cmd_set "$2" "$3"
        ;;
    test)
        cmd_test "${2:-all}"
        ;;
    history)
        cmd_history "${2:-10}"
        ;;
    rules)
        cmd_rules
        ;;
    stats)
        cmd_stats
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

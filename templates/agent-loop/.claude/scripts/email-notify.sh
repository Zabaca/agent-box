#!/bin/bash
# email-notify.sh - Send notifications via AgentMail API
# Integrates with existing notify.sh for file-based backup

set -euo pipefail

WORKSPACE="/agent-workspace"
CREDENTIALS_DIR="$WORKSPACE/.claude/credentials"
CONFIG_DIR="$WORKSPACE/.claude/config"
LOGS_DIR="$WORKSPACE/.claude/logs"

# AgentMail settings
API_BASE="https://api.agentmail.to/v0"
INBOX_ID="agent-box@agentmail.to"
API_KEY_FILE="$CREDENTIALS_DIR/agentmail-api-key.txt"

# Notification config
CONFIG_FILE="$CONFIG_DIR/email-notify.json"
LOG_FILE="$LOGS_DIR/email-notify.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default recipient (user's email - configure in config file)
DEFAULT_RECIPIENT=""

log() {
    local msg="[$(date -Iseconds)] $1"
    echo -e "${BLUE}[email-notify]${NC} $1"
    mkdir -p "$LOGS_DIR"
    echo "$msg" >> "$LOG_FILE"
}

error() {
    local msg="[$(date -Iseconds)] ERROR: $1"
    echo -e "${RED}[email-notify] ERROR:${NC} $1" >&2
    mkdir -p "$LOGS_DIR"
    echo "$msg" >> "$LOG_FILE"
}

# Load API key
get_api_key() {
    if [[ -f "$API_KEY_FILE" ]]; then
        cat "$API_KEY_FILE" | tr -d '\n'
    else
        error "API key not found at $API_KEY_FILE"
        return 1
    fi
}

# Load config
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        DEFAULT_RECIPIENT=$(jq -r '.recipient // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
    fi
}

# Initialize default config if not exists
init_config() {
    mkdir -p "$CONFIG_DIR"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
  "recipient": "",
  "levels": {
    "critical": true,
    "error": true,
    "warning": true,
    "info": true,
    "success": true
  },
  "sender_name": "Claude Agent",
  "subject_prefix": "[Agent]"
}
EOF
        log "Created default config at $CONFIG_FILE"
    fi
}

# Check if email should be sent for this level
should_email() {
    local level="$1"
    if [[ -f "$CONFIG_FILE" ]]; then
        jq -r ".levels.${level} // false" "$CONFIG_FILE" 2>/dev/null
    else
        # Default: only email critical and error
        case "$level" in
            critical|error) echo "true" ;;
            *) echo "false" ;;
        esac
    fi
}

# Send email via AgentMail API
send_email() {
    local to="$1"
    local subject="$2"
    local body="$3"
    local html="${4:-}"

    local api_key
    api_key=$(get_api_key) || return 1

    # Build request body
    local request_body
    if [[ -n "$html" ]]; then
        request_body=$(jq -n \
            --arg to "$to" \
            --arg subject "$subject" \
            --arg text "$body" \
            --arg html "$html" \
            '{to: $to, subject: $subject, text: $text, html: $html}')
    else
        request_body=$(jq -n \
            --arg to "$to" \
            --arg subject "$subject" \
            --arg text "$body" \
            '{to: $to, subject: $subject, text: $text}')
    fi

    # Send via API
    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" \
        -X POST "$API_BASE/inboxes/$INBOX_ID/messages/send" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        -d "$request_body")

    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')

    if [[ "$http_code" == "200" ]]; then
        local message_id
        message_id=$(echo "$response" | jq -r '.message_id // "unknown"')
        log "Email sent successfully (message_id: $message_id)"
        return 0
    else
        error "Failed to send email (HTTP $http_code): $response"
        return 1
    fi
}

# Also write to file-based notifications (backup)
file_notify() {
    local level="$1"
    local message="$2"

    local notifications_file="$WORKSPACE/.claude/notifications.md"
    echo "- [$(date -Iseconds)] **$level**: $message" >> "$notifications_file"
}

# Main notification function
notify() {
    local level="${1:-info}"
    local message="$2"
    local subject="${3:-}"

    # Normalize level
    level=$(echo "$level" | tr '[:upper:]' '[:lower:]')

    # Load config
    load_config

    # Generate subject if not provided
    if [[ -z "$subject" ]]; then
        local prefix
        prefix=$(jq -r '.subject_prefix // "[Agent]"' "$CONFIG_FILE" 2>/dev/null || echo "[Agent]")
        subject="$prefix ${level^^}: $message"
        # Truncate subject to 100 chars
        subject="${subject:0:100}"
    fi

    # Always write to file (backup)
    file_notify "$level" "$message"

    # Check if we should email
    local should_send
    should_send=$(should_email "$level")

    if [[ "$should_send" == "true" ]]; then
        if [[ -z "$DEFAULT_RECIPIENT" ]]; then
            error "No recipient configured. Set 'recipient' in $CONFIG_FILE"
            return 1
        fi

        # Send email
        send_email "$DEFAULT_RECIPIENT" "$subject" "$message"
    else
        log "Skipped email for level '$level' (file notification written)"
    fi
}

# Show usage
usage() {
    cat << 'EOF'
email-notify.sh - Send notifications via AgentMail

USAGE:
    email-notify.sh <level> <message> [subject]
    email-notify.sh send <to> <subject> <body>
    email-notify.sh config
    email-notify.sh test

LEVELS:
    critical    - Always emails (system down, needs attention)
    error       - Always emails (something failed)
    warning     - File only by default
    info        - File only by default
    success     - File only by default

COMMANDS:
    send        - Send direct email (bypasses level config)
    config      - Show/edit configuration
    test        - Send test email to configured recipient

CONFIGURATION:
    Edit: /agent-workspace/.claude/config/email-notify.json

    {
      "recipient": "user@example.com",  // Where to send notifications
      "levels": {
        "critical": true,   // true = send email, false = file only
        "error": true,
        "warning": true,
        "info": true,
        "success": true
      }
    }

EXAMPLES:
    # Send critical alert (will email)
    email-notify.sh critical "Database connection lost"

    # Send info (file only by default)
    email-notify.sh info "Task completed successfully"

    # Direct email
    email-notify.sh send user@example.com "Hello" "Message body"

    # Test configuration
    email-notify.sh test
EOF
}

# Show config
show_config() {
    init_config
    echo "Configuration: $CONFIG_FILE"
    echo ""
    if [[ -f "$CONFIG_FILE" ]]; then
        cat "$CONFIG_FILE"
    fi
    echo ""
    echo "API Key: $(if [[ -f "$API_KEY_FILE" ]]; then echo "Found"; else echo "MISSING"; fi)"
    echo "Inbox: $INBOX_ID"
}

# Test email
test_email() {
    load_config

    if [[ -z "$DEFAULT_RECIPIENT" ]]; then
        error "No recipient configured. Edit $CONFIG_FILE and set 'recipient'"
        return 1
    fi

    log "Sending test email to $DEFAULT_RECIPIENT..."

    local test_message="This is a test notification from Claude Agent.

Timestamp: $(date -Iseconds)
Hostname: $(hostname)
Working Directory: $WORKSPACE

If you received this, email notifications are working correctly."

    send_email "$DEFAULT_RECIPIENT" "[Agent] Test Notification" "$test_message"
}

# Main
main() {
    init_config

    case "${1:-}" in
        -h|--help|help)
            usage
            ;;
        config)
            show_config
            ;;
        test)
            test_email
            ;;
        send)
            if [[ $# -lt 4 ]]; then
                error "Usage: email-notify.sh send <to> <subject> <body>"
                exit 1
            fi
            send_email "$2" "$3" "$4"
            ;;
        critical|error|warning|info|success)
            if [[ $# -lt 2 ]]; then
                error "Usage: email-notify.sh <level> <message> [subject]"
                exit 1
            fi
            notify "$1" "$2" "${3:-}"
            ;;
        "")
            usage
            ;;
        *)
            # Treat as message with default level
            notify "info" "$1" "${2:-}"
            ;;
    esac
}

main "$@"

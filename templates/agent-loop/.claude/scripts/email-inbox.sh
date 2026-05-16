#!/bin/bash
# email-inbox.sh - Process incoming emails from AgentMail inbox
# Converts emails to tasks in the task queue

set -euo pipefail

WORKSPACE="/agent-workspace"
CREDENTIALS_DIR="$WORKSPACE/.claude/credentials"
CONFIG_DIR="$WORKSPACE/.claude/config"
LOGS_DIR="$WORKSPACE/.claude/logs"
TASKS_FILE="$WORKSPACE/.claude/loop/tasks.md"
PROCESSED_DIR="$WORKSPACE/.claude/inbox/processed-emails"

# AgentMail settings
API_BASE="https://api.agentmail.to/v0"
DEFAULT_INBOX_ID="agent-tasks@agentmail.to"
API_KEY_FILE="$CREDENTIALS_DIR/agentmail-api-key.txt"

# Config
CONFIG_FILE="$CONFIG_DIR/email-inbox.json"

# Load inbox ID from config (or use default)
get_inbox_id() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local inbox
        inbox=$(jq -r '.inbox_id // ""' "$CONFIG_FILE" 2>/dev/null)
        if [[ -n "$inbox" ]]; then
            echo "$inbox"
            return
        fi
    fi
    echo "$DEFAULT_INBOX_ID"
}

INBOX_ID=$(get_inbox_id)
LOG_FILE="$LOGS_DIR/email-inbox.log"
STATE_FILE="$WORKSPACE/.claude/loop/email-inbox-state.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local msg="[$(date -Iseconds)] $1"
    echo -e "${BLUE}[email-inbox]${NC} $1"
    mkdir -p "$LOGS_DIR"
    echo "$msg" >> "$LOG_FILE"
}

error() {
    local msg="[$(date -Iseconds)] ERROR: $1"
    echo -e "${RED}[email-inbox] ERROR:${NC} $1" >&2
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

# Initialize config
init_config() {
    mkdir -p "$CONFIG_DIR" "$PROCESSED_DIR"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
  "allowed_senders": [],
  "task_prefix": "[Email Task]",
  "auto_process": true,
  "mark_as_read": true,
  "keywords": {
    "task": ["task:", "todo:", "please:", "can you"],
    "urgent": ["urgent", "asap", "critical", "important"]
  }
}
EOF
        log "Created default config at $CONFIG_FILE"
    fi

    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"last_checked": null, "processed_ids": []}' > "$STATE_FILE"
    fi
}

# Check if sender is allowed
is_sender_allowed() {
    local sender="$1"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 0  # Allow all if no config
    fi

    # Extract email from sender string
    local sender_email
    sender_email=$(echo "$sender" | grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' || echo "$sender")
    sender_email=$(echo "$sender_email" | tr '[:upper:]' '[:lower:]')

    # Check blocked senders first
    local blocked
    blocked=$(jq -r '.blocked_senders // []' "$CONFIG_FILE")

    if [[ "$blocked" != "[]" ]]; then
        while IFS= read -r pattern; do
            pattern=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')
            if [[ "$sender_email" == *"$pattern"* ]] || [[ "$sender" == *"$pattern"* ]]; then
                return 1  # Blocked
            fi
        done < <(echo "$blocked" | jq -r '.[]')
    fi

    # Check allowed senders
    local allowed
    allowed=$(jq -r '.allowed_senders // []' "$CONFIG_FILE")

    # If empty array, allow all (that aren't blocked)
    if [[ "$allowed" == "[]" ]]; then
        return 0
    fi

    # Check if sender matches any allowed pattern
    while IFS= read -r pattern; do
        pattern=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')
        if [[ "$sender_email" == *"$pattern"* ]]; then
            return 0
        fi
    done < <(echo "$allowed" | jq -r '.[]')

    return 1
}

# Fetch messages from inbox
fetch_messages() {
    local api_key
    api_key=$(get_api_key) || return 1

    local response
    response=$(curl -s \
        -X GET "$API_BASE/inboxes/$INBOX_ID/messages?limit=20" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json")

    echo "$response"
}

# Get full message content
get_message() {
    local message_id="$1"
    local api_key
    api_key=$(get_api_key) || return 1

    # URL encode the message_id
    local encoded_id
    encoded_id=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$message_id', safe=''))")

    local response
    response=$(curl -s \
        -X GET "$API_BASE/inboxes/$INBOX_ID/messages/$encoded_id" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json")

    echo "$response"
}

# Check if message already processed
is_processed() {
    local message_id="$1"

    if [[ -f "$STATE_FILE" ]]; then
        jq -e --arg id "$message_id" '.processed_ids | index($id) != null' "$STATE_FILE" >/dev/null 2>&1
        return $?
    fi
    return 1
}

# Mark message as processed
mark_processed() {
    local message_id="$1"

    if [[ -f "$STATE_FILE" ]]; then
        local temp_file
        temp_file=$(mktemp)
        jq --arg id "$message_id" '.processed_ids += [$id] | .last_checked = now' "$STATE_FILE" > "$temp_file"
        mv "$temp_file" "$STATE_FILE"
    fi
}

# Extract task from email
extract_task() {
    local subject="$1"
    local body="$2"
    local sender="$3"

    # Clean up subject
    local task_text
    task_text=$(echo "$subject" | sed 's/^Re: //i; s/^Fwd: //i; s/^\[.*\] //')

    # Check for task keywords in subject
    if echo "$subject" | grep -qiE '(task:|todo:|please:)'; then
        task_text=$(echo "$subject" | sed -E 's/.*(task:|todo:|please:)//i' | xargs)
    fi

    # If subject is generic, use first line of body
    if [[ -z "$task_text" ]] || [[ ${#task_text} -lt 5 ]]; then
        task_text=$(echo "$body" | head -n1 | cut -c1-100)
    fi

    # Add sender context
    local sender_name
    sender_name=$(echo "$sender" | sed 's/<.*>//' | xargs)

    echo "From $sender_name: $task_text"
}

# Add task to task queue
add_task() {
    local task="$1"
    local priority="${2:-normal}"

    local prefix
    prefix=$(jq -r '.task_prefix // "[Email Task]"' "$CONFIG_FILE" 2>/dev/null || echo "[Email Task]")

    local task_line="- [ ] $prefix $task"

    # Add to tasks.md under Pending section
    if [[ -f "$TASKS_FILE" ]]; then
        # Find the Pending section and add after it
        if grep -q "^## Pending" "$TASKS_FILE"; then
            # Insert after "## Pending" line (or after subsection header)
            sed -i "/^## Pending/a\\
$task_line" "$TASKS_FILE"
            log "Added task: $task"
        else
            # Append to file if no Pending section
            echo "" >> "$TASKS_FILE"
            echo "$task_line" >> "$TASKS_FILE"
            log "Appended task: $task"
        fi
    else
        error "Tasks file not found: $TASKS_FILE"
        return 1
    fi
}

# Save email for reference
save_email() {
    local message_id="$1"
    local subject="$2"
    local sender="$3"
    local body="$4"
    local timestamp="$5"

    mkdir -p "$PROCESSED_DIR"

    local safe_id
    safe_id=$(echo "$message_id" | md5sum | cut -c1-12)

    local email_file="$PROCESSED_DIR/${timestamp:0:10}_${safe_id}.md"

    cat > "$email_file" << EOF
# Email: $subject

**From:** $sender
**Date:** $timestamp
**Message ID:** $message_id

---

$body
EOF

    log "Saved email to $email_file"
}

# Process a single message
process_message() {
    local message_json="$1"

    local message_id subject sender timestamp preview
    message_id=$(echo "$message_json" | jq -r '.message_id')
    subject=$(echo "$message_json" | jq -r '.subject // "(no subject)"')
    sender=$(echo "$message_json" | jq -r '.from // "unknown"')
    timestamp=$(echo "$message_json" | jq -r '.timestamp')
    preview=$(echo "$message_json" | jq -r '.preview // ""')

    # Check if already processed
    if is_processed "$message_id"; then
        return 0
    fi

    # Check if sender is allowed
    if ! is_sender_allowed "$sender"; then
        log "Skipping email from unauthorized sender: $sender"
        mark_processed "$message_id"
        return 0
    fi

    log "Processing email: $subject (from: $sender)"

    # Get full message for body
    local full_message body
    full_message=$(get_message "$message_id")
    body=$(echo "$full_message" | jq -r '.text // .html // .preview // ""' | head -c 2000)

    # Extract and add task
    local task
    task=$(extract_task "$subject" "$body" "$sender")
    add_task "$task"

    # Save email for reference
    save_email "$message_id" "$subject" "$sender" "$body" "$timestamp"

    # Mark as processed
    mark_processed "$message_id"

    log "Processed: $subject"
}

# Main processing function
process_inbox() {
    log "Checking inbox: $INBOX_ID"

    local messages_response
    messages_response=$(fetch_messages)

    if [[ -z "$messages_response" ]] || ! echo "$messages_response" | jq -e '.messages' >/dev/null 2>&1; then
        error "Failed to fetch messages or invalid response"
        return 1
    fi

    local count
    count=$(echo "$messages_response" | jq '.messages | length')
    log "Found $count messages"

    if [[ "$count" -eq 0 ]]; then
        log "No new messages"
        return 0
    fi

    # Process each message
    echo "$messages_response" | jq -c '.messages[]' | while read -r msg; do
        # Only process received messages (not sent by us)
        local labels
        labels=$(echo "$msg" | jq -r '.labels // []')

        if echo "$labels" | jq -e 'index("received")' >/dev/null 2>&1; then
            process_message "$msg"
        fi
    done

    # Update last checked time
    local temp_file
    temp_file=$(mktemp)
    jq '.last_checked = now' "$STATE_FILE" > "$temp_file"
    mv "$temp_file" "$STATE_FILE"

    log "Inbox processing complete"
}

# Show status
show_status() {
    echo "Email Inbox Processor Status"
    echo "============================"
    echo ""
    echo "Inbox: $INBOX_ID"
    echo "Config: $CONFIG_FILE"
    echo "State: $STATE_FILE"
    echo ""

    if [[ -f "$STATE_FILE" ]]; then
        echo "Last checked: $(jq -r '.last_checked // "never"' "$STATE_FILE")"
        echo "Processed count: $(jq '.processed_ids | length' "$STATE_FILE")"
    fi

    echo ""
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Allowed senders: $(jq -r '.allowed_senders | if length == 0 then "all" else join(", ") end' "$CONFIG_FILE")"
    fi
}

# Clear processed state (reprocess all)
clear_state() {
    echo '{"last_checked": null, "processed_ids": []}' > "$STATE_FILE"
    log "Cleared processing state"
}

# Usage
usage() {
    cat << 'EOF'
email-inbox.sh - Process incoming emails as tasks

USAGE:
    email-inbox.sh [command]

COMMANDS:
    check       - Check inbox and process new emails (default)
    status      - Show processing status
    clear       - Clear processed state (will reprocess all)
    config      - Show configuration

CONFIGURATION:
    Edit: /agent-workspace/.claude/config/email-inbox.json

    {
      "allowed_senders": [],        // Empty = allow all, or list emails/domains
      "task_prefix": "[Email Task]", // Prefix for tasks in queue
      "auto_process": true,
      "mark_as_read": true,
      "keywords": { ... }           // Keywords to detect task emails
    }

HOW IT WORKS:
    1. Fetches recent messages from agent-box@agentmail.to
    2. Filters by allowed senders (if configured)
    3. Extracts task from subject/body
    4. Adds task to /agent-workspace/.claude/loop/tasks.md
    5. Saves email copy to .claude/inbox/processed-emails/
    6. Marks message as processed (won't process again)

INTEGRATION:
    Add to heartbeat.sh or cron for periodic checking:

    # Check every 5 minutes
    */5 * * * * /agent-workspace/.claude/scripts/email-inbox.sh check

EXAMPLES:
    # Check for new task emails
    email-inbox.sh check

    # View status
    email-inbox.sh status

    # Force reprocess all emails
    email-inbox.sh clear && email-inbox.sh check
EOF
}

# Main
main() {
    init_config
    INBOX_ID=$(get_inbox_id)

    case "${1:-check}" in
        -h|--help|help)
            usage
            ;;
        check|process)
            process_inbox
            ;;
        status)
            show_status
            ;;
        clear)
            clear_state
            ;;
        config)
            if [[ -f "$CONFIG_FILE" ]]; then
                cat "$CONFIG_FILE"
            fi
            ;;
        *)
            error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"

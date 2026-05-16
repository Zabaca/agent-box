#!/bin/bash
# api-client.sh - External API client wrapper for common APIs
# Provides a unified interface for making HTTP requests with auth, retries, and parsing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_DIR="${SCRIPT_DIR}/../api-client"
CONFIG_FILE="${API_DIR}/config.json"
PROFILES_DIR="${API_DIR}/profiles"
HISTORY_FILE="${API_DIR}/history.jsonl"
CACHE_DIR="${API_DIR}/cache"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# Defaults
DEFAULT_TIMEOUT=30
DEFAULT_RETRIES=3
DEFAULT_RETRY_DELAY=2
CACHE_TTL=300  # 5 minutes

# Initialize directories
init_dirs() {
    mkdir -p "$API_DIR" "$PROFILES_DIR" "$CACHE_DIR"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
  "default_timeout": 30,
  "default_retries": 3,
  "retry_delay": 2,
  "user_agent": "api-client/1.0",
  "cache_enabled": true,
  "cache_ttl": 300,
  "log_requests": true
}
EOF
    fi
}

# Show usage
usage() {
    cat << 'EOF'
api-client.sh - External API client wrapper

USAGE:
    api-client.sh <command> [options]

COMMANDS:
    request     Make an HTTP request
    get         Shorthand for GET request
    post        Shorthand for POST request
    put         Shorthand for PUT request
    delete      Shorthand for DELETE request

    profile     Manage API profiles (auth, base URL)
    config      View/set configuration
    history     View request history
    cache       Manage response cache

    github      GitHub API shortcuts
    jsonapi     JSON Placeholder API (for testing)
    webhook     Send to webhook endpoints

OPTIONS:
    -u, --url       Request URL
    -H, --header    Add header (can be repeated)
    -d, --data      Request body data
    -f, --file      Read body from file
    -p, --profile   Use saved profile
    -o, --output    Output file (default: stdout)
    -t, --timeout   Request timeout in seconds
    -r, --retries   Number of retries on failure
    --no-cache      Disable caching for this request
    --raw           Output raw response (no parsing)
    -q, --quiet     Suppress progress output
    -v, --verbose   Show detailed request info

EXAMPLES:
    # Simple GET request
    api-client.sh get https://api.example.com/users

    # POST with JSON data
    api-client.sh post https://api.example.com/users -d '{"name":"test"}'

    # Use a profile with auth
    api-client.sh profile add github --base-url https://api.github.com --token ghp_xxx
    api-client.sh get /user -p github

    # GitHub API shortcuts
    api-client.sh github repos anthropics/claude-code
    api-client.sh github issues anthropics/claude-code

    # Request with headers
    api-client.sh get https://api.example.com -H "Accept: application/json" -H "X-Custom: value"

EOF
}

# Load config
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        DEFAULT_TIMEOUT=$(jq -r '.default_timeout // 30' "$CONFIG_FILE")
        DEFAULT_RETRIES=$(jq -r '.default_retries // 3' "$CONFIG_FILE")
        DEFAULT_RETRY_DELAY=$(jq -r '.retry_delay // 2' "$CONFIG_FILE")
        CACHE_TTL=$(jq -r '.cache_ttl // 300' "$CONFIG_FILE")
    fi
}

# Log to history
log_request() {
    local method="$1"
    local url="$2"
    local status="$3"
    local duration="$4"

    local log_enabled
    log_enabled=$(jq -r '.log_requests // true' "$CONFIG_FILE" 2>/dev/null || echo "true")

    if [[ "$log_enabled" == "true" ]]; then
        local entry
        entry=$(jq -n \
            --arg ts "$(date -Iseconds)" \
            --arg method "$method" \
            --arg url "$url" \
            --arg status "$status" \
            --arg duration "$duration" \
            '{timestamp: $ts, method: $method, url: $url, status: $status, duration: $duration}')
        echo "$entry" >> "$HISTORY_FILE"
    fi
}

# Get cache key for URL
get_cache_key() {
    local url="$1"
    echo "$url" | md5sum | cut -d' ' -f1
}

# Check cache
check_cache() {
    local url="$1"
    local cache_key
    cache_key=$(get_cache_key "$url")
    local cache_file="${CACHE_DIR}/${cache_key}"

    if [[ -f "$cache_file" ]]; then
        local cache_age
        cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file")))
        if [[ $cache_age -lt $CACHE_TTL ]]; then
            cat "$cache_file"
            return 0
        fi
    fi
    return 1
}

# Save to cache
save_cache() {
    local url="$1"
    local response="$2"
    local cache_key
    cache_key=$(get_cache_key "$url")
    echo "$response" > "${CACHE_DIR}/${cache_key}"
}

# Make HTTP request with retries
http_request() {
    local method="$1"
    local url="$2"
    local headers=()
    local data=""
    local timeout=$DEFAULT_TIMEOUT
    local retries=$DEFAULT_RETRIES
    local use_cache=true
    local raw=false
    local quiet=false
    local verbose=false
    local output=""
    local profile=""

    shift 2

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -H|--header)
                headers+=("-H" "$2")
                shift 2
                ;;
            -d|--data)
                data="$2"
                shift 2
                ;;
            -f|--file)
                data="@$2"
                shift 2
                ;;
            -t|--timeout)
                timeout="$2"
                shift 2
                ;;
            -r|--retries)
                retries="$2"
                shift 2
                ;;
            -o|--output)
                output="$2"
                shift 2
                ;;
            -p|--profile)
                profile="$2"
                shift 2
                ;;
            --no-cache)
                use_cache=false
                shift
                ;;
            --raw)
                raw=true
                shift
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Apply profile if specified
    if [[ -n "$profile" ]]; then
        local profile_file="${PROFILES_DIR}/${profile}.json"
        if [[ -f "$profile_file" ]]; then
            local base_url
            base_url=$(jq -r '.base_url // ""' "$profile_file")
            if [[ -n "$base_url" && "$url" == /* ]]; then
                url="${base_url}${url}"
            fi

            # Add auth header
            local auth_type
            auth_type=$(jq -r '.auth_type // ""' "$profile_file")
            case "$auth_type" in
                bearer|token)
                    local token
                    token=$(jq -r '.token // ""' "$profile_file")
                    if [[ -n "$token" ]]; then
                        headers+=("-H" "Authorization: Bearer $token")
                    fi
                    ;;
                basic)
                    local username password
                    username=$(jq -r '.username // ""' "$profile_file")
                    password=$(jq -r '.password // ""' "$profile_file")
                    if [[ -n "$username" ]]; then
                        headers+=("-u" "${username}:${password}")
                    fi
                    ;;
                api-key)
                    local api_key header_name
                    api_key=$(jq -r '.api_key // ""' "$profile_file")
                    header_name=$(jq -r '.header_name // "X-API-Key"' "$profile_file")
                    if [[ -n "$api_key" ]]; then
                        headers+=("-H" "${header_name}: ${api_key}")
                    fi
                    ;;
            esac

            # Add custom headers from profile
            local custom_headers
            custom_headers=$(jq -r '.headers // {} | to_entries[] | "\(.key): \(.value)"' "$profile_file" 2>/dev/null)
            while IFS= read -r header; do
                if [[ -n "$header" ]]; then
                    headers+=("-H" "$header")
                fi
            done <<< "$custom_headers"
        else
            echo -e "${RED}Profile not found: $profile${NC}" >&2
            return 1
        fi
    fi

    # Check cache for GET requests
    if [[ "$method" == "GET" && "$use_cache" == true ]]; then
        local cached
        if cached=$(check_cache "$url"); then
            if [[ "$verbose" == true ]]; then
                echo -e "${GRAY}[CACHE HIT]${NC}" >&2
            fi
            if [[ -n "$output" ]]; then
                echo "$cached" > "$output"
            else
                echo "$cached"
            fi
            return 0
        fi
    fi

    # Build curl command
    local curl_cmd=(curl -sS -X "$method" --max-time "$timeout")
    curl_cmd+=("${headers[@]}")

    # Add default headers
    curl_cmd+=("-H" "User-Agent: api-client/1.0")
    curl_cmd+=("-H" "Accept: application/json")

    # Add data for POST/PUT/PATCH
    if [[ -n "$data" && "$method" =~ ^(POST|PUT|PATCH)$ ]]; then
        if [[ "$data" == @* ]]; then
            curl_cmd+=("-d" "$data")
        else
            curl_cmd+=("-H" "Content-Type: application/json")
            curl_cmd+=("-d" "$data")
        fi
    fi

    curl_cmd+=("-w" "\n%{http_code}|%{time_total}")
    curl_cmd+=("$url")

    if [[ "$verbose" == true ]]; then
        echo -e "${CYAN}$method $url${NC}" >&2
        if [[ -n "$data" && "$data" != @* ]]; then
            echo -e "${GRAY}Body: $data${NC}" >&2
        fi
    fi

    local attempt=0
    local response=""
    local status=""
    local duration=""
    local start_time

    while [[ $attempt -lt $retries ]]; do
        attempt=$((attempt + 1))

        if [[ "$quiet" != true && $attempt -gt 1 ]]; then
            echo -e "${YELLOW}Retry $attempt/$retries...${NC}" >&2
        fi

        start_time=$(date +%s.%N)

        # Execute request
        local raw_output
        if raw_output=$("${curl_cmd[@]}" 2>&1); then
            # Parse response
            local last_line
            last_line=$(echo "$raw_output" | tail -n1)
            response=$(echo "$raw_output" | sed '$d')
            status=$(echo "$last_line" | cut -d'|' -f1)
            duration=$(echo "$last_line" | cut -d'|' -f2)

            # Check for HTTP errors
            if [[ "$status" =~ ^[23] ]]; then
                break
            elif [[ "$status" =~ ^[45] ]]; then
                if [[ $attempt -lt $retries ]]; then
                    sleep "$DEFAULT_RETRY_DELAY"
                    continue
                fi
            fi
            break
        else
            if [[ $attempt -lt $retries ]]; then
                sleep "$DEFAULT_RETRY_DELAY"
            fi
        fi
    done

    # Log request
    log_request "$method" "$url" "$status" "$duration"

    # Handle response
    if [[ "$verbose" == true ]]; then
        echo -e "${GREEN}Status: $status${NC} ${GRAY}(${duration}s)${NC}" >&2
    fi

    if [[ "$status" =~ ^[45] ]]; then
        echo -e "${RED}HTTP Error: $status${NC}" >&2
        if [[ -n "$response" ]]; then
            echo "$response" >&2
        fi
        return 1
    fi

    # Cache successful GET responses
    if [[ "$method" == "GET" && "$use_cache" == true && "$status" =~ ^2 ]]; then
        save_cache "$url" "$response"
    fi

    # Output
    if [[ "$raw" == true ]]; then
        if [[ -n "$output" ]]; then
            echo "$response" > "$output"
        else
            echo "$response"
        fi
    else
        # Try to pretty-print JSON
        if echo "$response" | jq . >/dev/null 2>&1; then
            if [[ -n "$output" ]]; then
                echo "$response" | jq . > "$output"
            else
                echo "$response" | jq .
            fi
        else
            if [[ -n "$output" ]]; then
                echo "$response" > "$output"
            else
                echo "$response"
            fi
        fi
    fi
}

# Profile management
cmd_profile() {
    local action="${1:-list}"
    shift || true

    case "$action" in
        list)
            echo -e "${CYAN}=== API Profiles ===${NC}"
            if [[ -d "$PROFILES_DIR" ]]; then
                for profile in "$PROFILES_DIR"/*.json; do
                    if [[ -f "$profile" ]]; then
                        local name
                        name=$(basename "$profile" .json)
                        local base_url auth_type
                        base_url=$(jq -r '.base_url // "none"' "$profile")
                        auth_type=$(jq -r '.auth_type // "none"' "$profile")
                        echo -e "  ${GREEN}$name${NC}"
                        echo -e "    Base URL: $base_url"
                        echo -e "    Auth: $auth_type"
                    fi
                done
            fi
            if ! ls "$PROFILES_DIR"/*.json >/dev/null 2>&1; then
                echo -e "  ${GRAY}No profiles configured${NC}"
            fi
            ;;
        add)
            local name="$1"
            shift || { echo "Usage: profile add <name> [options]"; return 1; }

            local base_url="" auth_type="" token="" username="" password="" api_key="" header_name=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --base-url)
                        base_url="$2"
                        shift 2
                        ;;
                    --token)
                        auth_type="bearer"
                        token="$2"
                        shift 2
                        ;;
                    --basic)
                        auth_type="basic"
                        username="$2"
                        password="${3:-}"
                        shift
                        shift
                        [[ -n "$password" ]] && shift
                        ;;
                    --api-key)
                        auth_type="api-key"
                        api_key="$2"
                        header_name="${3:-X-API-Key}"
                        shift 2
                        [[ "${1:-}" != -* && -n "${1:-}" ]] && { header_name="$1"; shift; }
                        ;;
                    *)
                        shift
                        ;;
                esac
            done

            local profile_data
            profile_data=$(jq -n \
                --arg base_url "$base_url" \
                --arg auth_type "$auth_type" \
                --arg token "$token" \
                --arg username "$username" \
                --arg password "$password" \
                --arg api_key "$api_key" \
                --arg header_name "$header_name" \
                '{
                    base_url: $base_url,
                    auth_type: $auth_type,
                    token: (if $token != "" then $token else null end),
                    username: (if $username != "" then $username else null end),
                    password: (if $password != "" then $password else null end),
                    api_key: (if $api_key != "" then $api_key else null end),
                    header_name: (if $header_name != "" then $header_name else null end),
                    headers: {}
                } | with_entries(select(.value != null))')

            echo "$profile_data" > "${PROFILES_DIR}/${name}.json"
            echo -e "${GREEN}Profile '$name' created${NC}"
            ;;
        remove)
            local name="$1"
            if [[ -f "${PROFILES_DIR}/${name}.json" ]]; then
                rm "${PROFILES_DIR}/${name}.json"
                echo -e "${GREEN}Profile '$name' removed${NC}"
            else
                echo -e "${RED}Profile not found: $name${NC}"
                return 1
            fi
            ;;
        show)
            local name="$1"
            if [[ -f "${PROFILES_DIR}/${name}.json" ]]; then
                jq . "${PROFILES_DIR}/${name}.json"
            else
                echo -e "${RED}Profile not found: $name${NC}"
                return 1
            fi
            ;;
        *)
            echo "Usage: profile <list|add|remove|show> [args]"
            ;;
    esac
}

# Config management
cmd_config() {
    local action="${1:-show}"
    shift || true

    case "$action" in
        show)
            echo -e "${CYAN}=== Configuration ===${NC}"
            jq . "$CONFIG_FILE"
            ;;
        set)
            local key="$1"
            local value="$2"
            local tmp_file
            tmp_file=$(mktemp)
            jq --arg k "$key" --arg v "$value" '.[$k] = ($v | try tonumber // $v)' "$CONFIG_FILE" > "$tmp_file"
            mv "$tmp_file" "$CONFIG_FILE"
            echo -e "${GREEN}Set $key = $value${NC}"
            ;;
        *)
            echo "Usage: config <show|set> [key] [value]"
            ;;
    esac
}

# History commands
cmd_history() {
    local action="${1:-show}"
    shift || true

    case "$action" in
        show)
            local count="${1:-20}"
            echo -e "${CYAN}=== Request History (last $count) ===${NC}"
            if [[ -f "$HISTORY_FILE" ]]; then
                tail -n "$count" "$HISTORY_FILE" | while IFS= read -r line; do
                    local ts method url status duration
                    ts=$(echo "$line" | jq -r '.timestamp // ""')
                    method=$(echo "$line" | jq -r '.method // ""')
                    url=$(echo "$line" | jq -r '.url // ""')
                    status=$(echo "$line" | jq -r '.status // ""')
                    duration=$(echo "$line" | jq -r '.duration // ""')

                    local color=$GREEN
                    if [[ "$status" =~ ^4 ]]; then color=$YELLOW; fi
                    if [[ "$status" =~ ^5 ]]; then color=$RED; fi

                    echo -e "${GRAY}$ts${NC} ${BLUE}$method${NC} $url ${color}$status${NC} ${GRAY}(${duration}s)${NC}"
                done
            else
                echo -e "${GRAY}No history yet${NC}"
            fi
            ;;
        clear)
            rm -f "$HISTORY_FILE"
            echo -e "${GREEN}History cleared${NC}"
            ;;
        stats)
            echo -e "${CYAN}=== Request Statistics ===${NC}"
            if [[ -f "$HISTORY_FILE" ]]; then
                local total
                total=$(wc -l < "$HISTORY_FILE" | tr -d '[:space:]')
                echo -e "Total requests: ${GREEN}$total${NC}"

                echo -e "\nBy method:"
                jq -r '.method' "$HISTORY_FILE" | sort | uniq -c | sort -rn | while read -r count method; do
                    echo -e "  $method: $count"
                done

                echo -e "\nBy status:"
                jq -r '.status' "$HISTORY_FILE" | sort | uniq -c | sort -rn | while read -r count status; do
                    local color=$GREEN
                    if [[ "$status" =~ ^4 ]]; then color=$YELLOW; fi
                    if [[ "$status" =~ ^5 ]]; then color=$RED; fi
                    echo -e "  ${color}$status${NC}: $count"
                done
            else
                echo -e "${GRAY}No history yet${NC}"
            fi
            ;;
        *)
            echo "Usage: history <show|clear|stats> [count]"
            ;;
    esac
}

# Cache management
cmd_cache() {
    local action="${1:-status}"
    shift || true

    case "$action" in
        status)
            echo -e "${CYAN}=== Cache Status ===${NC}"
            if [[ -d "$CACHE_DIR" ]]; then
                local count
                count=$(find "$CACHE_DIR" -type f | wc -l | tr -d '[:space:]')
                local size
                size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
                echo -e "Entries: ${GREEN}$count${NC}"
                echo -e "Size: $size"
                echo -e "TTL: ${CACHE_TTL}s"
            fi
            ;;
        clear)
            rm -rf "${CACHE_DIR:?}"/*
            echo -e "${GREEN}Cache cleared${NC}"
            ;;
        *)
            echo "Usage: cache <status|clear>"
            ;;
    esac
}

# GitHub API shortcuts
cmd_github() {
    local resource="${1:-help}"
    shift || true

    # Check for GitHub profile or token
    local github_opts=()
    if [[ -f "${PROFILES_DIR}/github.json" ]]; then
        github_opts+=(-p github)
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        github_opts+=(-H "Authorization: Bearer $GITHUB_TOKEN")
    fi

    local base_url="https://api.github.com"

    case "$resource" in
        help)
            cat << 'EOF'
GitHub API shortcuts:
    github user [username]          Get user info
    github repos <owner>            List user's repos
    github repo <owner/repo>        Get repo info
    github issues <owner/repo>      List issues
    github prs <owner/repo>         List pull requests
    github releases <owner/repo>    List releases
    github search <query>           Search repositories
EOF
            ;;
        user)
            local username="${1:-}"
            if [[ -n "$username" ]]; then
                http_request GET "${base_url}/users/${username}" "${github_opts[@]}"
            else
                http_request GET "${base_url}/user" "${github_opts[@]}"
            fi
            ;;
        repos)
            local owner="$1"
            http_request GET "${base_url}/users/${owner}/repos?sort=updated&per_page=10" "${github_opts[@]}"
            ;;
        repo)
            local repo="$1"
            http_request GET "${base_url}/repos/${repo}" "${github_opts[@]}"
            ;;
        issues)
            local repo="$1"
            local state="${2:-open}"
            http_request GET "${base_url}/repos/${repo}/issues?state=${state}&per_page=10" "${github_opts[@]}"
            ;;
        prs)
            local repo="$1"
            local state="${2:-open}"
            http_request GET "${base_url}/repos/${repo}/pulls?state=${state}&per_page=10" "${github_opts[@]}"
            ;;
        releases)
            local repo="$1"
            http_request GET "${base_url}/repos/${repo}/releases?per_page=5" "${github_opts[@]}"
            ;;
        search)
            local query="$*"
            http_request GET "${base_url}/search/repositories?q=$(echo "$query" | sed 's/ /+/g')&per_page=10" "${github_opts[@]}"
            ;;
        *)
            echo "Unknown GitHub resource: $resource"
            return 1
            ;;
    esac
}

# JSON Placeholder API (for testing)
cmd_jsonapi() {
    local resource="${1:-help}"
    shift || true

    local base_url="https://jsonplaceholder.typicode.com"

    case "$resource" in
        help)
            cat << 'EOF'
JSON Placeholder API (testing):
    jsonapi posts           List posts
    jsonapi post <id>       Get post
    jsonapi users           List users
    jsonapi user <id>       Get user
    jsonapi comments <id>   Get comments for post
    jsonapi create          Create test post
EOF
            ;;
        posts)
            http_request GET "${base_url}/posts?_limit=10"
            ;;
        post)
            local id="$1"
            http_request GET "${base_url}/posts/${id}"
            ;;
        users)
            http_request GET "${base_url}/users"
            ;;
        user)
            local id="$1"
            http_request GET "${base_url}/users/${id}"
            ;;
        comments)
            local post_id="$1"
            http_request GET "${base_url}/posts/${post_id}/comments"
            ;;
        create)
            http_request POST "${base_url}/posts" -d '{"title":"Test Post","body":"This is a test","userId":1}'
            ;;
        *)
            echo "Unknown resource: $resource"
            return 1
            ;;
    esac
}

# Webhook sending
cmd_webhook() {
    local url="$1"
    shift || { echo "Usage: webhook <url> [message]"; return 1; }

    local message="${*:-Test webhook from api-client}"
    local payload

    # Detect webhook type from URL
    if [[ "$url" == *"slack"* ]]; then
        payload=$(jq -n --arg text "$message" '{text: $text}')
    elif [[ "$url" == *"discord"* ]]; then
        payload=$(jq -n --arg content "$message" '{content: $content}')
    else
        # Generic JSON
        payload=$(jq -n --arg message "$message" '{message: $message}')
    fi

    http_request POST "$url" -d "$payload"
}

# Main
main() {
    init_dirs
    load_config

    local command="${1:-help}"
    shift || true

    case "$command" in
        help|--help|-h)
            usage
            ;;
        request)
            local method="${1:-GET}"
            shift || true
            http_request "$method" "$@"
            ;;
        get|GET)
            http_request GET "$@"
            ;;
        post|POST)
            http_request POST "$@"
            ;;
        put|PUT)
            http_request PUT "$@"
            ;;
        delete|DELETE)
            http_request DELETE "$@"
            ;;
        patch|PATCH)
            http_request PATCH "$@"
            ;;
        profile)
            cmd_profile "$@"
            ;;
        config)
            cmd_config "$@"
            ;;
        history)
            cmd_history "$@"
            ;;
        cache)
            cmd_cache "$@"
            ;;
        github)
            cmd_github "$@"
            ;;
        jsonapi)
            cmd_jsonapi "$@"
            ;;
        webhook)
            cmd_webhook "$@"
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}"
            usage
            exit 1
            ;;
    esac
}

main "$@"

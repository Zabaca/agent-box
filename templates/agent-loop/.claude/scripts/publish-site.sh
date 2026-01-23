#!/bin/bash
# publish-site.sh - Deploy static sites to Netlify or Cloudflare Pages
# Usage: publish-site.sh <directory> [--platform netlify|cloudflare] [--site-name name]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
CONFIG_FILE="$CONFIG_DIR/publishing.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

usage() {
    cat << 'EOF'
Usage: publish-site.sh <directory> [options]

Deploy a static site directory to Netlify or Cloudflare Pages.

Arguments:
    directory           Directory containing static site files

Options:
    --platform, -p      Platform to deploy to (netlify, cloudflare)
                        Default: auto-detect from config or use netlify
    --site-name, -n     Name for the site (used for subdomain)
    --prod              Deploy to production (default is preview/draft)
    --message, -m       Deploy message/commit message
    --setup             Interactive setup for credentials
    --status            Check deployment status
    --list              List all deployed sites
    --help, -h          Show this help

Environment Variables (alternative to config file):
    NETLIFY_AUTH_TOKEN      Netlify personal access token
    NETLIFY_SITE_ID         Netlify site ID (for existing sites)
    CLOUDFLARE_API_TOKEN    Cloudflare API token
    CLOUDFLARE_ACCOUNT_ID   Cloudflare account ID

Configuration:
    Create ~/.claude/config/publishing.json with credentials:
    {
        "default_platform": "netlify",
        "netlify": {
            "auth_token": "your-token",
            "default_site_id": "optional-site-id"
        },
        "cloudflare": {
            "api_token": "your-token",
            "account_id": "your-account-id"
        }
    }

Examples:
    publish-site.sh ./dist                          Deploy dist/ to default platform
    publish-site.sh ./build -p cloudflare --prod    Deploy to Cloudflare production
    publish-site.sh ./demo -n my-demo-site          Deploy with custom site name
    publish-site.sh --setup                         Interactive credential setup
    publish-site.sh --list                          List deployed sites
EOF
}

# Load config
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        cat "$CONFIG_FILE"
    else
        echo '{}'
    fi
}

get_config_value() {
    local key="$1"
    local config
    config=$(load_config)
    echo "$config" | jq -r "$key // empty"
}

# Setup credentials interactively
setup_credentials() {
    mkdir -p "$CONFIG_DIR"

    echo "=== Static Site Publishing Setup ==="
    echo ""
    echo "Choose platform to configure:"
    echo "1) Netlify"
    echo "2) Cloudflare Pages"
    echo "3) Both"
    echo ""
    read -r -p "Selection [1-3]: " choice

    local config
    config=$(load_config)

    case "$choice" in
        1|3)
            echo ""
            echo "--- Netlify Setup ---"
            echo "Get your token at: https://app.netlify.com/user/applications#personal-access-tokens"
            read -r -p "Netlify Auth Token: " netlify_token
            config=$(echo "$config" | jq --arg token "$netlify_token" '.netlify.auth_token = $token')
            if [[ "$choice" == "1" ]]; then
                config=$(echo "$config" | jq '.default_platform = "netlify"')
            fi
            ;;
    esac

    case "$choice" in
        2|3)
            echo ""
            echo "--- Cloudflare Pages Setup ---"
            echo "Get your token at: https://dash.cloudflare.com/profile/api-tokens"
            echo "Required permissions: Cloudflare Pages:Edit"
            read -r -p "Cloudflare API Token: " cf_token
            read -r -p "Cloudflare Account ID: " cf_account
            config=$(echo "$config" | jq --arg token "$cf_token" --arg account "$cf_account" \
                '.cloudflare.api_token = $token | .cloudflare.account_id = $account')
            if [[ "$choice" == "2" ]]; then
                config=$(echo "$config" | jq '.default_platform = "cloudflare"')
            fi
            ;;
    esac

    echo "$config" | jq '.' > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    log_success "Configuration saved to $CONFIG_FILE"
}

# Check if tools are installed
check_dependencies() {
    local platform="$1"

    case "$platform" in
        netlify)
            if ! command -v netlify &> /dev/null; then
                log_info "Installing Netlify CLI..."
                npm install -g netlify-cli
            fi
            ;;
        cloudflare)
            if ! command -v wrangler &> /dev/null; then
                log_info "Installing Wrangler (Cloudflare CLI)..."
                npm install -g wrangler
            fi
            ;;
    esac
}

# Deploy to Netlify
deploy_netlify() {
    local directory="$1"
    local site_name="$2"
    local is_prod="$3"
    local message="$4"

    local auth_token="${NETLIFY_AUTH_TOKEN:-$(get_config_value '.netlify.auth_token')}"
    local site_id="${NETLIFY_SITE_ID:-$(get_config_value '.netlify.default_site_id')}"

    if [[ -z "$auth_token" ]]; then
        log_error "Netlify auth token not configured"
        log_info "Run: publish-site.sh --setup"
        log_info "Or set NETLIFY_AUTH_TOKEN environment variable"
        return 1
    fi

    export NETLIFY_AUTH_TOKEN="$auth_token"

    local deploy_args=("--dir" "$directory")

    if [[ -n "$site_id" ]]; then
        deploy_args+=("--site" "$site_id")
    elif [[ -n "$site_name" ]]; then
        # Create new site
        log_info "Creating new Netlify site: $site_name"
        local create_result
        create_result=$(netlify sites:create --name "$site_name" --json 2>/dev/null || echo '{}')
        site_id=$(echo "$create_result" | jq -r '.id // empty')
        if [[ -n "$site_id" ]]; then
            deploy_args+=("--site" "$site_id")
            log_success "Created site with ID: $site_id"
        fi
    fi

    if [[ "$is_prod" == "true" ]]; then
        deploy_args+=("--prod")
    fi

    if [[ -n "$message" ]]; then
        deploy_args+=("--message" "$message")
    fi

    log_info "Deploying to Netlify..."
    local result
    result=$(netlify deploy "${deploy_args[@]}" --json 2>&1)

    local deploy_url
    local logs_url

    if [[ "$is_prod" == "true" ]]; then
        deploy_url=$(echo "$result" | jq -r '.url // .deploy_url // empty')
    else
        deploy_url=$(echo "$result" | jq -r '.deploy_url // empty')
    fi
    logs_url=$(echo "$result" | jq -r '.logs // empty')

    if [[ -n "$deploy_url" ]]; then
        log_success "Deployed successfully!"
        echo ""
        echo "  URL: $deploy_url"
        [[ -n "$logs_url" ]] && echo "  Logs: $logs_url"
        echo ""

        # Save deployment info
        save_deployment_record "netlify" "$site_name" "$deploy_url" "$is_prod"
    else
        log_error "Deployment may have failed. Output:"
        echo "$result"
        return 1
    fi
}

# Deploy to Cloudflare Pages
deploy_cloudflare() {
    local directory="$1"
    local site_name="$2"
    local is_prod="$3"
    local message="$4"

    local api_token="${CLOUDFLARE_API_TOKEN:-$(get_config_value '.cloudflare.api_token')}"
    local account_id="${CLOUDFLARE_ACCOUNT_ID:-$(get_config_value '.cloudflare.account_id')}"

    if [[ -z "$api_token" ]] || [[ -z "$account_id" ]]; then
        log_error "Cloudflare credentials not configured"
        log_info "Run: publish-site.sh --setup"
        log_info "Or set CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID environment variables"
        return 1
    fi

    export CLOUDFLARE_API_TOKEN="$api_token"
    export CLOUDFLARE_ACCOUNT_ID="$account_id"

    # Use site name or generate one
    local project_name="${site_name:-claude-agent-$(date +%s)}"

    local deploy_args=("pages" "deploy" "$directory" "--project-name" "$project_name")

    if [[ "$is_prod" == "true" ]]; then
        deploy_args+=("--branch" "main")
    else
        deploy_args+=("--branch" "preview-$(date +%Y%m%d-%H%M%S)")
    fi

    if [[ -n "$message" ]]; then
        deploy_args+=("--commit-message" "$message")
    fi

    log_info "Deploying to Cloudflare Pages..."
    local result
    result=$(wrangler "${deploy_args[@]}" 2>&1)

    # Extract URL from output
    local deploy_url
    deploy_url=$(echo "$result" | grep -oE 'https://[a-zA-Z0-9.-]+\.pages\.dev' | head -1)

    if [[ -n "$deploy_url" ]]; then
        log_success "Deployed successfully!"
        echo ""
        echo "  URL: $deploy_url"
        echo "  Project: $project_name"
        echo ""

        # Save deployment info
        save_deployment_record "cloudflare" "$project_name" "$deploy_url" "$is_prod"
    else
        log_warn "Could not extract URL from output:"
        echo "$result"
    fi
}

# Save deployment record for tracking
save_deployment_record() {
    local platform="$1"
    local site_name="$2"
    local url="$3"
    local is_prod="$4"

    local deployments_file="$CONFIG_DIR/deployments.json"
    local deployments='{"deployments": []}'

    if [[ -f "$deployments_file" ]]; then
        deployments=$(cat "$deployments_file")
    fi

    local new_record
    new_record=$(jq -n \
        --arg platform "$platform" \
        --arg name "$site_name" \
        --arg url "$url" \
        --arg prod "$is_prod" \
        --arg date "$(date -Iseconds)" \
        '{platform: $platform, name: $name, url: $url, production: ($prod == "true"), deployed_at: $date}')

    echo "$deployments" | jq --argjson record "$new_record" '.deployments += [$record]' > "$deployments_file"
}

# List deployed sites
list_deployments() {
    local deployments_file="$CONFIG_DIR/deployments.json"

    if [[ ! -f "$deployments_file" ]]; then
        log_info "No deployments recorded yet"
        return
    fi

    echo "=== Deployed Sites ==="
    echo ""

    jq -r '.deployments | sort_by(.deployed_at) | reverse | .[] |
        "[\(.platform | ascii_upcase)] \(.name)\n  URL: \(.url)\n  Production: \(.production)\n  Deployed: \(.deployed_at)\n"' \
        "$deployments_file"
}

# Main
main() {
    local directory=""
    local platform=""
    local site_name=""
    local is_prod="false"
    local message=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                usage
                exit 0
                ;;
            --setup)
                setup_credentials
                exit 0
                ;;
            --list)
                list_deployments
                exit 0
                ;;
            --platform|-p)
                platform="$2"
                shift 2
                ;;
            --site-name|-n)
                site_name="$2"
                shift 2
                ;;
            --prod)
                is_prod="true"
                shift
                ;;
            --message|-m)
                message="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                directory="$1"
                shift
                ;;
        esac
    done

    # Validate directory
    if [[ -z "$directory" ]]; then
        log_error "Directory required"
        usage
        exit 1
    fi

    if [[ ! -d "$directory" ]]; then
        log_error "Directory not found: $directory"
        exit 1
    fi

    # Determine platform
    if [[ -z "$platform" ]]; then
        platform=$(get_config_value '.default_platform')
        if [[ -z "$platform" ]]; then
            platform="netlify"
        fi
    fi

    log_info "Platform: $platform"
    log_info "Directory: $directory"
    log_info "Production: $is_prod"

    # Check and install dependencies
    check_dependencies "$platform"

    # Deploy
    case "$platform" in
        netlify)
            deploy_netlify "$directory" "$site_name" "$is_prod" "$message"
            ;;
        cloudflare)
            deploy_cloudflare "$directory" "$site_name" "$is_prod" "$message"
            ;;
        *)
            log_error "Unknown platform: $platform"
            log_info "Supported: netlify, cloudflare"
            exit 1
            ;;
    esac
}

main "$@"

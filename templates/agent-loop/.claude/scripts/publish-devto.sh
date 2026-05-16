#!/bin/bash
# publish-devto.sh - Publish articles to Dev.to
# Usage: publish-devto.sh <markdown-file> [--publish]

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

DEVTO_API="https://dev.to/api"

usage() {
    cat << 'EOF'
Usage: publish-devto.sh <markdown-file> [options]

Publish a markdown article to Dev.to.

Arguments:
    markdown-file       Path to markdown file with front matter

Options:
    --publish           Publish immediately (default is draft)
    --update <id>       Update existing article by ID
    --list              List your published articles
    --setup             Set up Dev.to API key
    --help, -h          Show this help

Front Matter Format:
    The markdown file should have YAML front matter:
    ---
    title: Your Article Title
    published: false
    description: Short description for social sharing
    tags: tag1, tag2, tag3
    cover_image: https://example.com/image.jpg (optional)
    series: Series Name (optional)
    ---

    Your article content here...

Environment Variables:
    DEVTO_API_KEY       Dev.to API key (alternative to config)

Configuration:
    Add to ~/.claude/config/publishing.json:
    {
        "devto": {
            "api_key": "your-api-key"
        }
    }

Examples:
    publish-devto.sh article.md              Create draft article
    publish-devto.sh article.md --publish    Publish immediately
    publish-devto.sh article.md --update 123 Update existing article
    publish-devto.sh --list                  List your articles
    publish-devto.sh --setup                 Configure API key
EOF
}

# Get API key
get_api_key() {
    local key="${DEVTO_API_KEY:-}"

    if [[ -z "$key" ]] && [[ -f "$CONFIG_FILE" ]]; then
        key=$(jq -r '.devto.api_key // empty' "$CONFIG_FILE")
    fi

    echo "$key"
}

# Setup API key
setup_api_key() {
    mkdir -p "$CONFIG_DIR"

    echo "=== Dev.to API Setup ==="
    echo ""
    echo "Get your API key at: https://dev.to/settings/extensions"
    echo "Scroll to 'DEV Community API Keys' and generate a new key"
    echo ""
    read -r -p "Dev.to API Key: " api_key

    local config='{}'
    if [[ -f "$CONFIG_FILE" ]]; then
        config=$(cat "$CONFIG_FILE")
    fi

    echo "$config" | jq --arg key "$api_key" '.devto.api_key = $key' > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    log_success "API key saved to $CONFIG_FILE"
}

# Parse front matter from markdown
parse_front_matter() {
    local file="$1"

    # Extract content between --- markers
    local front_matter
    front_matter=$(awk '/^---$/{if(p){exit}else{p=1;next}} p' "$file")

    echo "$front_matter"
}

# Get markdown body (after front matter)
get_body() {
    local file="$1"

    # Skip everything until second ---
    awk 'BEGIN{c=0} /^---$/{c++;next} c>=2' "$file"
}

# Convert front matter to JSON for API
create_article_payload() {
    local file="$1"
    local publish="$2"

    local front_matter
    front_matter=$(parse_front_matter "$file")

    local body
    body=$(get_body "$file")

    # Parse front matter fields
    local title description tags cover_image series

    title=$(echo "$front_matter" | grep -E '^title:' | sed 's/^title:\s*//' | sed 's/^"\(.*\)"$/\1/')
    description=$(echo "$front_matter" | grep -E '^description:' | sed 's/^description:\s*//' | sed 's/^"\(.*\)"$/\1/')
    tags=$(echo "$front_matter" | grep -E '^tags:' | sed 's/^tags:\s*//')
    cover_image=$(echo "$front_matter" | grep -E '^cover_image:' | sed 's/^cover_image:\s*//')
    series=$(echo "$front_matter" | grep -E '^series:' | sed 's/^series:\s*//' | sed 's/^"\(.*\)"$/\1/')

    # Convert tags to array format
    local tags_array='[]'
    if [[ -n "$tags" ]]; then
        # Split by comma, trim whitespace
        tags_array=$(echo "$tags" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | jq -R . | jq -s .)
    fi

    # Build article JSON
    local article_json
    article_json=$(jq -n \
        --arg title "$title" \
        --arg body "$body" \
        --arg description "${description:-}" \
        --argjson tags "$tags_array" \
        --argjson published "$publish" \
        '{
            article: {
                title: $title,
                body_markdown: $body,
                published: $published,
                tags: $tags
            }
        }')

    # Add optional fields
    if [[ -n "$description" ]]; then
        article_json=$(echo "$article_json" | jq --arg desc "$description" '.article.description = $desc')
    fi

    if [[ -n "$cover_image" ]]; then
        article_json=$(echo "$article_json" | jq --arg img "$cover_image" '.article.main_image = $img')
    fi

    if [[ -n "$series" ]]; then
        article_json=$(echo "$article_json" | jq --arg s "$series" '.article.series = $s')
    fi

    echo "$article_json"
}

# Create new article
create_article() {
    local file="$1"
    local publish="$2"

    local api_key
    api_key=$(get_api_key)

    if [[ -z "$api_key" ]]; then
        log_error "Dev.to API key not configured"
        log_info "Run: publish-devto.sh --setup"
        return 1
    fi

    log_info "Parsing article from: $file"

    local payload
    payload=$(create_article_payload "$file" "$publish")

    log_info "Creating article on Dev.to..."

    local response
    response=$(curl -s -X POST "$DEVTO_API/articles" \
        -H "Content-Type: application/json" \
        -H "api-key: $api_key" \
        -d "$payload")

    local article_id url title error

    error=$(echo "$response" | jq -r '.error // empty')
    if [[ -n "$error" ]]; then
        log_error "API Error: $error"
        echo "$response" | jq '.'
        return 1
    fi

    article_id=$(echo "$response" | jq -r '.id')
    url=$(echo "$response" | jq -r '.url')
    title=$(echo "$response" | jq -r '.title')

    log_success "Article created!"
    echo ""
    echo "  Title: $title"
    echo "  ID: $article_id"
    echo "  URL: $url"
    echo "  Published: $publish"
    echo ""

    # Save record
    save_article_record "$article_id" "$title" "$url" "$publish"
}

# Update existing article
update_article() {
    local file="$1"
    local article_id="$2"
    local publish="$3"

    local api_key
    api_key=$(get_api_key)

    if [[ -z "$api_key" ]]; then
        log_error "Dev.to API key not configured"
        return 1
    fi

    log_info "Updating article $article_id..."

    local payload
    payload=$(create_article_payload "$file" "$publish")

    local response
    response=$(curl -s -X PUT "$DEVTO_API/articles/$article_id" \
        -H "Content-Type: application/json" \
        -H "api-key: $api_key" \
        -d "$payload")

    local error url title
    error=$(echo "$response" | jq -r '.error // empty')

    if [[ -n "$error" ]]; then
        log_error "API Error: $error"
        return 1
    fi

    url=$(echo "$response" | jq -r '.url')
    title=$(echo "$response" | jq -r '.title')

    log_success "Article updated!"
    echo ""
    echo "  Title: $title"
    echo "  URL: $url"
    echo ""
}

# List articles
list_articles() {
    local api_key
    api_key=$(get_api_key)

    if [[ -z "$api_key" ]]; then
        log_error "Dev.to API key not configured"
        return 1
    fi

    log_info "Fetching your articles..."

    local response
    response=$(curl -s "$DEVTO_API/articles/me?per_page=30" \
        -H "api-key: $api_key")

    echo ""
    echo "=== Your Dev.to Articles ==="
    echo ""

    echo "$response" | jq -r '.[] | "[\(.id)] \(.title)\n  URL: \(.url)\n  Published: \(.published)\n  Reactions: \(.positive_reactions_count) | Comments: \(.comments_count)\n"'
}

# Save article record
save_article_record() {
    local id="$1"
    local title="$2"
    local url="$3"
    local published="$4"

    local articles_file="$CONFIG_DIR/devto-articles.json"
    local articles='{"articles": []}'

    if [[ -f "$articles_file" ]]; then
        articles=$(cat "$articles_file")
    fi

    local new_record
    new_record=$(jq -n \
        --arg id "$id" \
        --arg title "$title" \
        --arg url "$url" \
        --argjson published "$published" \
        --arg date "$(date -Iseconds)" \
        '{id: $id, title: $title, url: $url, published: $published, created_at: $date}')

    echo "$articles" | jq --argjson record "$new_record" '.articles += [$record]' > "$articles_file"
}

# Main
main() {
    local file=""
    local publish="false"
    local update_id=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                usage
                exit 0
                ;;
            --setup)
                setup_api_key
                exit 0
                ;;
            --list)
                list_articles
                exit 0
                ;;
            --publish)
                publish="true"
                shift
                ;;
            --update)
                update_id="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                file="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$file" ]]; then
        log_error "Markdown file required"
        usage
        exit 1
    fi

    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        exit 1
    fi

    if [[ -n "$update_id" ]]; then
        update_article "$file" "$update_id" "$publish"
    else
        create_article "$file" "$publish"
    fi
}

main "$@"

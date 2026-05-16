#!/bin/bash
# Post article to dev.to
# Usage: devto-post.sh <title> <markdown-file> [tags] [published]
#
# Requires DEV_TO_API_KEY environment variable or .claude/config/devto.json

set -euo pipefail

WORKSPACE="/agent-workspace"
CONFIG_FILE="$WORKSPACE/.claude/config/devto.json"

# Get API key
API_KEY=""
if [ -n "${DEV_TO_API_KEY:-}" ]; then
  API_KEY="$DEV_TO_API_KEY"
elif [ -f "$CONFIG_FILE" ]; then
  API_KEY=$(jq -r '.api_key // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
fi

if [ -z "$API_KEY" ]; then
  echo "Error: No API key found. Set DEV_TO_API_KEY or create $CONFIG_FILE" >&2
  exit 1
fi

# Arguments
TITLE="${1:-}"
MARKDOWN_FILE="${2:-}"
TAGS="${3:-cli,nodejs,javascript}"
PUBLISHED="${4:-false}"

if [ -z "$TITLE" ] || [ -z "$MARKDOWN_FILE" ]; then
  echo "Usage: devto-post.sh <title> <markdown-file> [tags] [published]" >&2
  exit 1
fi

if [ ! -f "$MARKDOWN_FILE" ]; then
  echo "Error: Markdown file not found: $MARKDOWN_FILE" >&2
  exit 1
fi

# Read content
BODY_MARKDOWN=$(cat "$MARKDOWN_FILE")

# Build JSON payload
PAYLOAD=$(jq -n \
  --arg title "$TITLE" \
  --arg body "$BODY_MARKDOWN" \
  --arg tags "$TAGS" \
  --argjson published "$PUBLISHED" \
  '{
    article: {
      title: $title,
      body_markdown: $body,
      tags: ($tags | split(",")),
      published: $published
    }
  }')

# Post to dev.to
RESPONSE=$(curl -s -X POST "https://dev.to/api/articles" \
  -H "Content-Type: application/json" \
  -H "api-key: $API_KEY" \
  -d "$PAYLOAD")

# Check for errors
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
  echo "Error posting article:" >&2
  echo "$RESPONSE" | jq -r '.error' >&2
  exit 1
fi

# Output result
ARTICLE_URL=$(echo "$RESPONSE" | jq -r '.url // empty')
ARTICLE_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

if [ -n "$ARTICLE_URL" ]; then
  echo "Article posted successfully!"
  echo "URL: $ARTICLE_URL"
  echo "ID: $ARTICLE_ID"
else
  echo "Response:"
  echo "$RESPONSE" | jq .
fi

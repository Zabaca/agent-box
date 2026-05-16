#!/bin/bash
# skill-review.sh - Review recent activity and suggest skills
# Called by heartbeat/stop-hook to maintain skill system

set -euo pipefail

WORKSPACE="/agent-workspace"
SKILLS_DIR="$WORKSPACE/.claude/skills"
LEARNINGS_FILE="$WORKSPACE/.claude/learnings.md"
TRIGGERS_FILE="$WORKSPACE/.claude/loop/skill-triggers.md"
OUTPUT_FILE="$WORKSPACE/.claude/loop/skill-suggestions.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[skill-review]${NC} $1"
}

# Get list of existing skills
get_existing_skills() {
    if [ -d "$SKILLS_DIR" ]; then
        find "$SKILLS_DIR" -name "SKILL.md" -exec dirname {} \; 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -u
    fi
}

# Check for recent learnings without skills
check_recent_learnings() {
    if [ ! -f "$LEARNINGS_FILE" ]; then
        return
    fi

    # Get learnings from last 3 days
    local recent_headers=$(grep "^## 202" "$LEARNINGS_FILE" | tail -10)

    echo "$recent_headers"
}

# Check for APIs mentioned in recent work
check_api_usage() {
    local apis=()

    # Check bash history or recent logs for API patterns
    if [ -f "$WORKSPACE/.claude/loop/task-generation.log" ]; then
        # Look for API URLs or common patterns
        grep -oP 'api\.[a-z]+\.(?:com|io|to|dev)' "$WORKSPACE/.claude/loop/task-generation.log" 2>/dev/null | sort -u || true
    fi
}

# Generate skill suggestions
generate_suggestions() {
    local suggestions=()
    local existing=$(get_existing_skills)

    # Check for common patterns that should be skills

    # Cloudflare Workers
    if ! echo "$existing" | grep -q "cloudflare"; then
        if [ -f "$WORKSPACE/demo/wrangler.toml" ]; then
            suggestions+=("cloudflare-workers: Deployment and management of Workers")
        fi
    fi

    # GitHub API
    if ! echo "$existing" | grep -q "github"; then
        if command -v gh &>/dev/null; then
            suggestions+=("github-api: GitHub CLI and API operations")
        fi
    fi

    # Playwright/Browser
    if ! echo "$existing" | grep -q "playwright\|browser"; then
        if [ -d "$HOME/.cache/ms-playwright" ] 2>/dev/null; then
            suggestions+=("browser-automation: Playwright patterns and debugging")
        fi
    fi

    # npm/publishing
    if ! echo "$existing" | grep -q "npm"; then
        if [ -d "$WORKSPACE/packages" ]; then
            suggestions+=("npm-publish: Package publishing workflow")
        fi
    fi

    # Output suggestions
    if [ ${#suggestions[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}Suggested skills to create:${NC}"
        for s in "${suggestions[@]}"; do
            echo "  - $s"
        done
    else
        echo -e "\n${GREEN}No new skill suggestions at this time.${NC}"
    fi

    printf '%s\n' "${suggestions[@]}" 2>/dev/null || true
}

# Main report
main() {
    log "Reviewing skills..."

    echo "# Skill Review Report"
    echo "Generated: $(date -Iseconds)"
    echo ""

    echo "## Existing Skills"
    local existing=$(get_existing_skills)
    if [ -n "$existing" ]; then
        echo "$existing" | while read skill; do
            echo "- /$skill"
        done
    else
        echo "- (none)"
    fi
    echo ""

    echo "## Recent Learnings"
    local learnings=$(check_recent_learnings)
    if [ -n "$learnings" ]; then
        echo "$learnings" | while read line; do
            echo "- $line"
        done
    else
        echo "- (none recent)"
    fi
    echo ""

    echo "## Suggestions"
    generate_suggestions
    echo ""

    echo "---"
    echo "Run \`/create-skill <name>\` to create a new skill."
}

# Run and optionally save
if [ "${1:-}" = "--save" ]; then
    main > "$OUTPUT_FILE"
    log "Report saved to $OUTPUT_FILE"
else
    main
fi

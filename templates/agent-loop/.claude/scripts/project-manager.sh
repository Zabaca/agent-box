#!/bin/bash
#
# Multi-Project Manager
# Track, switch between, and manage multiple projects
#
# Usage: project-manager.sh <command> [options]
#   list                     List all registered projects
#   add <name> <path>        Register a new project
#   remove <name>            Unregister a project
#   switch <name>            Switch active project context
#   status [name]            Show project status (default: all)
#   info <name>              Show detailed project info
#   run <name> <cmd>         Run command in project context
#   tasks <name>             Show project tasks
#   sync                     Sync all projects' git status
#   -h, --help               Show help

set -uo pipefail

WORKSPACE="/agent-workspace"
PROJECTS_DIR="$WORKSPACE/.claude/projects"
PROJECTS_FILE="$PROJECTS_DIR/registry.json"
CURRENT_FILE="$PROJECTS_DIR/current"

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
Multi-Project Manager - Track and manage multiple projects

Usage: project-manager.sh <command> [options]

Commands:
  list                     List all registered projects
  add <name> <path>        Register a new project
  remove <name>            Unregister a project
  switch <name>            Switch active project context
  status [name]            Show project status (all or specific)
  info <name>              Show detailed project info
  run <name> <cmd>         Run command in project directory
  tasks <name>             Show/manage project tasks
  sync                     Sync git status for all projects
  archive <name>           Archive a project (mark inactive)
  restore <name>           Restore archived project

Options:
  -h, --help               Show this help

Project Registry:
  Projects are stored in ~/.claude/projects/registry.json
  Each project tracks: name, path, type, git info, status

Examples:
  project-manager.sh add myapp /home/user/myapp
  project-manager.sh list
  project-manager.sh switch myapp
  project-manager.sh run myapp "npm test"
  project-manager.sh status
EOF
}

# Initialize project registry
init_registry() {
    mkdir -p "$PROJECTS_DIR"
    if [[ ! -f "$PROJECTS_FILE" ]]; then
        echo '{"projects":[]}' > "$PROJECTS_FILE"
    fi
}

# Get project by name
get_project() {
    local name="$1"
    jq -r ".projects[] | select(.name == \"$name\")" "$PROJECTS_FILE"
}

# Check if project exists
project_exists() {
    local name="$1"
    local count
    count=$(jq -r ".projects | map(select(.name == \"$name\")) | length" "$PROJECTS_FILE")
    [[ "$count" -gt 0 ]]
}

# Detect project type
detect_project_type() {
    local path="$1"

    if [[ -f "$path/package.json" ]]; then
        if [[ -f "$path/tsconfig.json" ]]; then
            echo "typescript"
        else
            echo "nodejs"
        fi
    elif [[ -f "$path/requirements.txt" ]] || [[ -f "$path/setup.py" ]] || [[ -f "$path/pyproject.toml" ]]; then
        echo "python"
    elif [[ -f "$path/Cargo.toml" ]]; then
        echo "rust"
    elif [[ -f "$path/go.mod" ]]; then
        echo "go"
    elif [[ -f "$path/Makefile" ]]; then
        echo "make"
    elif [[ -d "$path/.claude" ]]; then
        echo "claude-agent"
    else
        echo "generic"
    fi
}

# Get git info for a path
get_git_info() {
    local path="$1"

    if [[ ! -d "$path/.git" ]]; then
        echo '{"is_git":false}'
        return
    fi

    local branch remote status_clean commit_count
    branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "unknown")
    remote=$(git -C "$path" remote get-url origin 2>/dev/null || echo "none")
    status_clean=$(git -C "$path" status --porcelain 2>/dev/null | wc -l)
    commit_count=$(git -C "$path" rev-list --count HEAD 2>/dev/null || echo "0")

    cat << EOF
{"is_git":true,"branch":"$branch","remote":"$remote","uncommitted":$status_clean,"commits":$commit_count}
EOF
}

# List all projects
cmd_list() {
    init_registry

    local count
    count=$(jq '.projects | length' "$PROJECTS_FILE")

    if [[ "$count" -eq 0 ]]; then
        echo "No projects registered yet."
        echo "Use: project-manager.sh add <name> <path>"
        return
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              Registered Projects ($count)                        ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Get current project
    local current=""
    [[ -f "$CURRENT_FILE" ]] && current=$(cat "$CURRENT_FILE")

    printf "  %-3s %-20s %-15s %-10s %s\n" "" "NAME" "TYPE" "STATUS" "PATH"
    echo "  ─────────────────────────────────────────────────────────────────"

    jq -r '.projects[] | "\(.name)|\(.path)|\(.type)|\(.status)"' "$PROJECTS_FILE" | while IFS='|' read -r name path type status; do
        local marker=" "
        [[ "$name" == "$current" ]] && marker="→"

        local status_color="$GREEN"
        [[ "$status" == "archived" ]] && status_color="$GRAY"
        [[ "$status" == "error" ]] && status_color="$RED"

        printf "  ${CYAN}%s${NC} %-20s %-15s ${status_color}%-10s${NC} %s\n" "$marker" "$name" "$type" "$status" "$path"
    done
}

# Add a new project
cmd_add() {
    local name="$1"
    local path="$2"

    init_registry

    # Validate name
    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        echo -e "${RED}Error:${NC} Invalid project name. Use alphanumeric, underscore, hyphen. Start with letter."
        return 1
    fi

    # Check if already exists
    if project_exists "$name"; then
        echo -e "${YELLOW}Warning:${NC} Project '$name' already exists"
        return 1
    fi

    # Resolve path
    if [[ ! "$path" = /* ]]; then
        path="$(pwd)/$path"
    fi
    path=$(realpath "$path" 2>/dev/null || echo "$path")

    # Check path exists
    if [[ ! -d "$path" ]]; then
        echo -e "${YELLOW}Note:${NC} Path doesn't exist yet. Creating..."
        mkdir -p "$path"
    fi

    # Detect type
    local type
    type=$(detect_project_type "$path")

    # Get git info
    local git_info
    git_info=$(get_git_info "$path")

    # Add to registry
    local temp_file
    temp_file=$(mktemp)

    jq --arg name "$name" \
       --arg path "$path" \
       --arg type "$type" \
       --argjson git "$git_info" \
       '.projects += [{"name":$name,"path":$path,"type":$type,"status":"active","created":"'"$(date -Iseconds)"'","git":$git}]' \
       "$PROJECTS_FILE" > "$temp_file"

    mv "$temp_file" "$PROJECTS_FILE"

    echo -e "${GREEN}✓${NC} Added project: $name"
    echo "  Path: $path"
    echo "  Type: $type"

    # Auto-switch if first project
    local count
    count=$(jq '.projects | length' "$PROJECTS_FILE")
    if [[ "$count" -eq 1 ]]; then
        echo "$name" > "$CURRENT_FILE"
        echo -e "${CYAN}→${NC} Set as active project"
    fi
}

# Remove a project
cmd_remove() {
    local name="$1"

    init_registry

    if ! project_exists "$name"; then
        echo -e "${RED}Error:${NC} Project '$name' not found"
        return 1
    fi

    local temp_file
    temp_file=$(mktemp)

    jq --arg name "$name" '.projects = [.projects[] | select(.name != $name)]' \
       "$PROJECTS_FILE" > "$temp_file"

    mv "$temp_file" "$PROJECTS_FILE"

    # Clear current if it was this project
    [[ -f "$CURRENT_FILE" ]] && [[ "$(cat "$CURRENT_FILE")" == "$name" ]] && rm -f "$CURRENT_FILE"

    echo -e "${GREEN}✓${NC} Removed project: $name"
}

# Switch active project
cmd_switch() {
    local name="$1"

    init_registry

    if ! project_exists "$name"; then
        echo -e "${RED}Error:${NC} Project '$name' not found"
        return 1
    fi

    echo "$name" > "$CURRENT_FILE"

    local path
    path=$(jq -r ".projects[] | select(.name == \"$name\") | .path" "$PROJECTS_FILE")

    echo -e "${GREEN}✓${NC} Switched to project: $name"
    echo "  Path: $path"
    echo ""
    echo "  Commands will now run in this context."
    echo "  Use 'cd $path' to navigate there."
}

# Show project status
cmd_status() {
    local filter_name="${1:-}"

    init_registry

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              Project Status                                   ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local projects_json
    if [[ -n "$filter_name" ]]; then
        projects_json=$(jq -c ".projects[] | select(.name == \"$filter_name\")" "$PROJECTS_FILE")
    else
        projects_json=$(jq -c '.projects[]' "$PROJECTS_FILE")
    fi

    if [[ -z "$projects_json" ]]; then
        echo "No projects found"
        return
    fi

    echo "$projects_json" | while read -r project; do
        local name path type
        name=$(echo "$project" | jq -r '.name')
        path=$(echo "$project" | jq -r '.path')
        type=$(echo "$project" | jq -r '.type')

        echo -e "${CYAN}━━━ $name ━━━${NC}"
        echo "  Type: $type"
        echo "  Path: $path"

        # Check if path exists
        if [[ ! -d "$path" ]]; then
            echo -e "  Status: ${RED}PATH MISSING${NC}"
            continue
        fi

        # Git status
        if [[ -d "$path/.git" ]]; then
            local branch uncommitted
            branch=$(git -C "$path" branch --show-current 2>/dev/null)
            uncommitted=$(git -C "$path" status --porcelain 2>/dev/null | wc -l)

            echo -e "  Git: ${GREEN}$branch${NC}"
            if [[ "$uncommitted" -gt 0 ]]; then
                echo -e "  Changes: ${YELLOW}$uncommitted uncommitted${NC}"
            else
                echo -e "  Changes: ${GREEN}clean${NC}"
            fi
        fi

        # Check for tasks
        if [[ -f "$path/.claude/loop/tasks.md" ]]; then
            local pending completed
            pending=$(grep -c '^\- \[ \]' "$path/.claude/loop/tasks.md" 2>/dev/null || echo 0)
            completed=$(grep -c '^\- \[x\]' "$path/.claude/loop/tasks.md" 2>/dev/null || echo 0)
            echo "  Tasks: $pending pending, $completed completed"
        fi

        echo ""
    done
}

# Show detailed project info
cmd_info() {
    local name="$1"

    init_registry

    if ! project_exists "$name"; then
        echo -e "${RED}Error:${NC} Project '$name' not found"
        return 1
    fi

    local project
    project=$(get_project "$name")

    local path type status created
    path=$(echo "$project" | jq -r '.path')
    type=$(echo "$project" | jq -r '.type')
    status=$(echo "$project" | jq -r '.status')
    created=$(echo "$project" | jq -r '.created')

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Project: $name"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Basic Info:"
    echo "  Name:    $name"
    echo "  Path:    $path"
    echo "  Type:    $type"
    echo "  Status:  $status"
    echo "  Created: $created"
    echo ""

    if [[ -d "$path" ]]; then
        echo "Directory Contents:"
        ls -la "$path" 2>/dev/null | head -15 | sed 's/^/  /'
        echo ""

        # Size
        local size
        size=$(du -sh "$path" 2>/dev/null | cut -f1)
        echo "  Total size: $size"

        # File count
        local file_count
        file_count=$(find "$path" -type f 2>/dev/null | wc -l)
        echo "  Files: $file_count"

        # Git info
        if [[ -d "$path/.git" ]]; then
            echo ""
            echo "Git Info:"
            echo "  Branch: $(git -C "$path" branch --show-current 2>/dev/null)"
            echo "  Remote: $(git -C "$path" remote get-url origin 2>/dev/null || echo 'none')"
            echo "  Commits: $(git -C "$path" rev-list --count HEAD 2>/dev/null)"
            echo "  Last commit: $(git -C "$path" log -1 --format='%s (%cr)' 2>/dev/null)"
        fi
    else
        echo -e "${RED}Warning:${NC} Path does not exist"
    fi
}

# Run command in project context
cmd_run() {
    local name="$1"
    shift
    local cmd="$*"

    init_registry

    if ! project_exists "$name"; then
        echo -e "${RED}Error:${NC} Project '$name' not found"
        return 1
    fi

    local path
    path=$(jq -r ".projects[] | select(.name == \"$name\") | .path" "$PROJECTS_FILE")

    if [[ ! -d "$path" ]]; then
        echo -e "${RED}Error:${NC} Project path does not exist: $path"
        return 1
    fi

    echo -e "${CYAN}Running in $name:${NC} $cmd"
    echo "─────────────────────────────────────────"

    (cd "$path" && eval "$cmd")
}

# Show project tasks
cmd_tasks() {
    local name="$1"

    init_registry

    if ! project_exists "$name"; then
        echo -e "${RED}Error:${NC} Project '$name' not found"
        return 1
    fi

    local path
    path=$(jq -r ".projects[] | select(.name == \"$name\") | .path" "$PROJECTS_FILE")

    local tasks_file="$path/.claude/loop/tasks.md"

    if [[ ! -f "$tasks_file" ]]; then
        echo "No tasks file found for project '$name'"
        echo "Expected: $tasks_file"
        return 1
    fi

    echo -e "${BLUE}Tasks for $name:${NC}"
    cat "$tasks_file"
}

# Sync all projects
cmd_sync() {
    init_registry

    echo -e "${BLUE}Syncing all projects...${NC}"
    echo ""

    jq -r '.projects[] | "\(.name)|\(.path)"' "$PROJECTS_FILE" | while IFS='|' read -r name path; do
        echo -n "  $name: "

        if [[ ! -d "$path" ]]; then
            echo -e "${RED}path missing${NC}"
            continue
        fi

        if [[ ! -d "$path/.git" ]]; then
            echo -e "${GRAY}not a git repo${NC}"
            continue
        fi

        # Update git info in registry
        local git_info
        git_info=$(get_git_info "$path")

        local temp_file
        temp_file=$(mktemp)
        jq --arg name "$name" --argjson git "$git_info" \
           '(.projects[] | select(.name == $name)).git = $git' \
           "$PROJECTS_FILE" > "$temp_file"
        mv "$temp_file" "$PROJECTS_FILE"

        local uncommitted
        uncommitted=$(echo "$git_info" | jq -r '.uncommitted')

        if [[ "$uncommitted" -gt 0 ]]; then
            echo -e "${YELLOW}$uncommitted uncommitted changes${NC}"
        else
            echo -e "${GREEN}clean${NC}"
        fi
    done

    echo ""
    echo -e "${GREEN}✓${NC} Sync complete"
}

# Archive project
cmd_archive() {
    local name="$1"

    init_registry

    if ! project_exists "$name"; then
        echo -e "${RED}Error:${NC} Project '$name' not found"
        return 1
    fi

    local temp_file
    temp_file=$(mktemp)
    jq --arg name "$name" \
       '(.projects[] | select(.name == $name)).status = "archived"' \
       "$PROJECTS_FILE" > "$temp_file"
    mv "$temp_file" "$PROJECTS_FILE"

    echo -e "${GREEN}✓${NC} Archived project: $name"
}

# Restore archived project
cmd_restore() {
    local name="$1"

    init_registry

    if ! project_exists "$name"; then
        echo -e "${RED}Error:${NC} Project '$name' not found"
        return 1
    fi

    local temp_file
    temp_file=$(mktemp)
    jq --arg name "$name" \
       '(.projects[] | select(.name == $name)).status = "active"' \
       "$PROJECTS_FILE" > "$temp_file"
    mv "$temp_file" "$PROJECTS_FILE"

    echo -e "${GREEN}✓${NC} Restored project: $name"
}

# Main command dispatch
case "${1:-}" in
    list)
        cmd_list
        ;;
    add)
        if [[ $# -lt 3 ]]; then
            echo "Usage: project-manager.sh add <name> <path>"
            exit 1
        fi
        cmd_add "$2" "$3"
        ;;
    remove)
        if [[ $# -lt 2 ]]; then
            echo "Usage: project-manager.sh remove <name>"
            exit 1
        fi
        cmd_remove "$2"
        ;;
    switch)
        if [[ $# -lt 2 ]]; then
            echo "Usage: project-manager.sh switch <name>"
            exit 1
        fi
        cmd_switch "$2"
        ;;
    status)
        cmd_status "${2:-}"
        ;;
    info)
        if [[ $# -lt 2 ]]; then
            echo "Usage: project-manager.sh info <name>"
            exit 1
        fi
        cmd_info "$2"
        ;;
    run)
        if [[ $# -lt 3 ]]; then
            echo "Usage: project-manager.sh run <name> <command>"
            exit 1
        fi
        name="$2"
        shift 2
        cmd_run "$name" "$@"
        ;;
    tasks)
        if [[ $# -lt 2 ]]; then
            echo "Usage: project-manager.sh tasks <name>"
            exit 1
        fi
        cmd_tasks "$2"
        ;;
    sync)
        cmd_sync
        ;;
    archive)
        if [[ $# -lt 2 ]]; then
            echo "Usage: project-manager.sh archive <name>"
            exit 1
        fi
        cmd_archive "$2"
        ;;
    restore)
        if [[ $# -lt 2 ]]; then
            echo "Usage: project-manager.sh restore <name>"
            exit 1
        fi
        cmd_restore "$2"
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

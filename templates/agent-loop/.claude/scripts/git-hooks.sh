#!/bin/bash
#
# Git Hook Manager
# Install, manage, and configure git hooks for automated workflows
#
# Usage: git-hooks.sh <command> [options]
#   install      Install hooks to a repository
#   uninstall    Remove managed hooks
#   list         List installed hooks
#   enable       Enable a specific hook
#   disable      Disable a specific hook
#   test         Test a hook without committing

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="/agent-workspace"
HOOKS_TEMPLATE_DIR="$WORKSPACE/.claude/git-hooks-templates"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Available hooks
HOOK_TYPES=(
    "pre-commit"
    "commit-msg"
    "post-commit"
    "pre-push"
    "post-merge"
    "post-checkout"
)

usage() {
    cat << 'EOF'
Git Hook Manager - Manage git hooks for workflow automation

Usage: git-hooks.sh <command> [options]

Commands:
  install [repo]     Install hooks to repository (default: current dir)
  uninstall [repo]   Remove managed hooks
  list [repo]        List installed hooks and their status
  enable <hook>      Enable a specific hook
  disable <hook>     Disable a specific hook
  test <hook>        Test a hook without committing
  create <hook>      Create a new custom hook template

Options:
  --all              Apply to all hook types
  -v, --verbose      Verbose output
  -h, --help         Show this help

Hook Types:
  pre-commit         Run before commit (linting, tests)
  commit-msg         Validate/modify commit message
  post-commit        Run after commit (notifications, auto-push)
  pre-push           Run before push (final checks)
  post-merge         Run after merge (dependency updates)
  post-checkout      Run after checkout (setup tasks)

Examples:
  git-hooks.sh install                   # Install to current repo
  git-hooks.sh install /path/to/repo     # Install to specific repo
  git-hooks.sh list                      # Show installed hooks
  git-hooks.sh enable pre-commit         # Enable pre-commit hook
  git-hooks.sh disable post-commit       # Disable post-commit
  git-hooks.sh test pre-commit           # Test pre-commit hook

EOF
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Ensure templates directory exists
ensure_templates() {
    mkdir -p "$HOOKS_TEMPLATE_DIR"
}

# Get git hooks directory for a repo
get_hooks_dir() {
    local repo="${1:-.}"
    local git_dir

    git_dir=$(git -C "$repo" rev-parse --git-dir 2>/dev/null)
    if [[ -z "$git_dir" ]]; then
        log_error "Not a git repository: $repo"
        return 1
    fi

    # Handle absolute vs relative path
    if [[ "$git_dir" == /* ]]; then
        echo "$git_dir/hooks"
    else
        echo "$repo/$git_dir/hooks"
    fi
}

# Create default hook templates
create_default_templates() {
    ensure_templates

    # Pre-commit hook - runs checks before commit
    cat > "$HOOKS_TEMPLATE_DIR/pre-commit" << 'HOOK'
#!/bin/bash
# Pre-commit hook - runs checks before allowing commit
# Managed by git-hooks.sh

set -e

echo "Running pre-commit checks..."

# Check for syntax errors in shell scripts
for file in $(git diff --cached --name-only --diff-filter=ACM | grep '\.sh$'); do
    if [[ -f "$file" ]]; then
        if ! bash -n "$file" 2>/dev/null; then
            echo "ERROR: Syntax error in $file"
            exit 1
        fi
    fi
done

# Check for debug statements left in code
if git diff --cached | grep -E '(console\.log|print\(|debugger|TODO:)' > /dev/null; then
    echo "WARNING: Found debug/TODO statements in staged changes"
    # exit 1  # Uncomment to make this a hard failure
fi

# Check for large files
MAX_SIZE=1048576  # 1MB
for file in $(git diff --cached --name-only --diff-filter=ACM); do
    if [[ -f "$file" ]]; then
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
        if [[ $size -gt $MAX_SIZE ]]; then
            echo "ERROR: File $file is too large ($(($size / 1024))KB > 1MB)"
            exit 1
        fi
    fi
done

echo "Pre-commit checks passed!"
exit 0
HOOK

    # Commit-msg hook - validates commit messages
    cat > "$HOOKS_TEMPLATE_DIR/commit-msg" << 'HOOK'
#!/bin/bash
# Commit-msg hook - validates commit message format
# Managed by git-hooks.sh

COMMIT_MSG_FILE="$1"
COMMIT_MSG=$(cat "$COMMIT_MSG_FILE")

# Check minimum length
if [[ ${#COMMIT_MSG} -lt 10 ]]; then
    echo "ERROR: Commit message too short (min 10 chars)"
    exit 1
fi

# Check for conventional commit format (optional)
# if ! echo "$COMMIT_MSG" | grep -qE '^(feat|fix|docs|style|refactor|test|chore)(\(.+\))?: .+'; then
#     echo "ERROR: Commit message should follow conventional commits format"
#     echo "Example: feat(auth): add login functionality"
#     exit 1
# fi

exit 0
HOOK

    # Post-commit hook - runs after successful commit
    cat > "$HOOKS_TEMPLATE_DIR/post-commit" << 'HOOK'
#!/bin/bash
# Post-commit hook - runs after successful commit
# Managed by git-hooks.sh

COMMIT_HASH=$(git rev-parse HEAD)
COMMIT_MSG=$(git log -1 --pretty=%B)

echo "Commit successful: ${COMMIT_HASH:0:8}"

# Log the commit
LOG_FILE="${GIT_HOOKS_LOG:-/tmp/git-commits.log}"
echo "[$(date -Iseconds)] $COMMIT_HASH - $COMMIT_MSG" >> "$LOG_FILE"

# Optional: auto-push after commit
# if [[ -n "$(git remote)" ]]; then
#     echo "Auto-pushing to remote..."
#     git push
# fi

exit 0
HOOK

    # Pre-push hook - final checks before push
    cat > "$HOOKS_TEMPLATE_DIR/pre-push" << 'HOOK'
#!/bin/bash
# Pre-push hook - final checks before push
# Managed by git-hooks.sh

REMOTE="$1"
URL="$2"

echo "Pre-push checks for $REMOTE ($URL)..."

# Prevent pushing to main/master without review
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
    echo "WARNING: Pushing directly to $BRANCH"
    # Uncomment to prevent direct pushes:
    # echo "ERROR: Cannot push directly to $BRANCH"
    # exit 1
fi

# Check for WIP commits
if git log @{u}..HEAD --oneline 2>/dev/null | grep -i "wip" > /dev/null; then
    echo "WARNING: Found WIP commits in push"
fi

echo "Pre-push checks passed!"
exit 0
HOOK

    # Post-merge hook - runs after merge
    cat > "$HOOKS_TEMPLATE_DIR/post-merge" << 'HOOK'
#!/bin/bash
# Post-merge hook - runs after successful merge
# Managed by git-hooks.sh

# Check if package.json changed
if git diff-tree -r --name-only --no-commit-id ORIG_HEAD HEAD | grep -q "package.json"; then
    echo "package.json changed, running npm install..."
    npm install 2>/dev/null || true
fi

# Check if requirements.txt changed
if git diff-tree -r --name-only --no-commit-id ORIG_HEAD HEAD | grep -q "requirements.txt"; then
    echo "requirements.txt changed, updating dependencies..."
    pip install -r requirements.txt 2>/dev/null || true
fi

exit 0
HOOK

    # Post-checkout hook - runs after checkout
    cat > "$HOOKS_TEMPLATE_DIR/post-checkout" << 'HOOK'
#!/bin/bash
# Post-checkout hook - runs after checkout
# Managed by git-hooks.sh

PREV_HEAD="$1"
NEW_HEAD="$2"
BRANCH_CHECKOUT="$3"

if [[ "$BRANCH_CHECKOUT" == "1" ]]; then
    NEW_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    echo "Switched to branch: $NEW_BRANCH"
fi

exit 0
HOOK

    # Make templates executable
    chmod +x "$HOOKS_TEMPLATE_DIR"/*

    log_success "Default hook templates created"
}

# Install hooks to a repository
install_hooks() {
    local repo="${1:-.}"
    local hooks_dir

    hooks_dir=$(get_hooks_dir "$repo") || return 1

    log_info "Installing hooks to: $hooks_dir"

    # Ensure templates exist
    if [[ ! -d "$HOOKS_TEMPLATE_DIR" ]] || [[ -z "$(ls -A "$HOOKS_TEMPLATE_DIR" 2>/dev/null)" ]]; then
        log_info "Creating default hook templates..."
        create_default_templates
    fi

    # Create hooks directory if needed
    mkdir -p "$hooks_dir"

    # Install each hook
    local installed=0
    for hook in "${HOOK_TYPES[@]}"; do
        if [[ -f "$HOOKS_TEMPLATE_DIR/$hook" ]]; then
            # Backup existing hook if not managed by us
            if [[ -f "$hooks_dir/$hook" ]] && ! grep -q "Managed by git-hooks.sh" "$hooks_dir/$hook" 2>/dev/null; then
                mv "$hooks_dir/$hook" "$hooks_dir/$hook.backup"
                log_warn "Backed up existing $hook to $hook.backup"
            fi

            cp "$HOOKS_TEMPLATE_DIR/$hook" "$hooks_dir/$hook"
            chmod +x "$hooks_dir/$hook"
            ((installed++))
            log_success "Installed: $hook"
        fi
    done

    log_success "Installed $installed hooks to $repo"
}

# Uninstall managed hooks
uninstall_hooks() {
    local repo="${1:-.}"
    local hooks_dir

    hooks_dir=$(get_hooks_dir "$repo") || return 1

    log_info "Uninstalling hooks from: $hooks_dir"

    local removed=0
    for hook in "${HOOK_TYPES[@]}"; do
        if [[ -f "$hooks_dir/$hook" ]] && grep -q "Managed by git-hooks.sh" "$hooks_dir/$hook" 2>/dev/null; then
            rm "$hooks_dir/$hook"
            ((removed++))
            log_info "Removed: $hook"

            # Restore backup if exists
            if [[ -f "$hooks_dir/$hook.backup" ]]; then
                mv "$hooks_dir/$hook.backup" "$hooks_dir/$hook"
                log_info "Restored backup for $hook"
            fi
        fi
    done

    log_success "Removed $removed hooks"
}

# List installed hooks
list_hooks() {
    local repo="${1:-.}"
    local hooks_dir

    hooks_dir=$(get_hooks_dir "$repo") || return 1

    echo -e "${BLUE}Git Hooks Status:${NC} $repo"
    echo "═══════════════════════════════════════════"

    for hook in "${HOOK_TYPES[@]}"; do
        local status="${RED}not installed${NC}"
        local managed=""

        if [[ -f "$hooks_dir/$hook" ]]; then
            if [[ -x "$hooks_dir/$hook" ]]; then
                status="${GREEN}enabled${NC}"
            else
                status="${YELLOW}disabled${NC}"
            fi

            if grep -q "Managed by git-hooks.sh" "$hooks_dir/$hook" 2>/dev/null; then
                managed=" (managed)"
            else
                managed=" (custom)"
            fi
        fi

        printf "  %-15s %b%s\n" "$hook" "$status" "$managed"
    done

    echo "═══════════════════════════════════════════"
}

# Enable a hook
enable_hook() {
    local hook="$1"
    local repo="${2:-.}"
    local hooks_dir

    hooks_dir=$(get_hooks_dir "$repo") || return 1

    if [[ ! -f "$hooks_dir/$hook" ]]; then
        log_error "Hook not installed: $hook"
        return 1
    fi

    chmod +x "$hooks_dir/$hook"
    log_success "Enabled: $hook"
}

# Disable a hook
disable_hook() {
    local hook="$1"
    local repo="${2:-.}"
    local hooks_dir

    hooks_dir=$(get_hooks_dir "$repo") || return 1

    if [[ ! -f "$hooks_dir/$hook" ]]; then
        log_error "Hook not installed: $hook"
        return 1
    fi

    chmod -x "$hooks_dir/$hook"
    log_success "Disabled: $hook"
}

# Test a hook
test_hook() {
    local hook="$1"
    local repo="${2:-.}"
    local hooks_dir

    hooks_dir=$(get_hooks_dir "$repo") || return 1

    if [[ ! -f "$hooks_dir/$hook" ]]; then
        log_error "Hook not installed: $hook"
        return 1
    fi

    if [[ ! -x "$hooks_dir/$hook" ]]; then
        log_error "Hook not executable: $hook"
        return 1
    fi

    log_info "Testing $hook hook..."
    echo "─────────────────────────────────────────"

    # Run the hook
    if "$hooks_dir/$hook" "$@"; then
        echo "─────────────────────────────────────────"
        log_success "Hook $hook passed"
        return 0
    else
        echo "─────────────────────────────────────────"
        log_error "Hook $hook failed"
        return 1
    fi
}

# Create a new custom hook
create_hook() {
    local hook="$1"

    # Validate hook type
    local valid=false
    for h in "${HOOK_TYPES[@]}"; do
        if [[ "$h" == "$hook" ]]; then
            valid=true
            break
        fi
    done

    if [[ "$valid" != true ]]; then
        log_error "Invalid hook type: $hook"
        echo "Valid types: ${HOOK_TYPES[*]}"
        return 1
    fi

    ensure_templates

    local template_file="$HOOKS_TEMPLATE_DIR/$hook"

    if [[ -f "$template_file" ]]; then
        log_warn "Template already exists: $hook"
        echo "Edit: $template_file"
        return 0
    fi

    # Create basic template
    cat > "$template_file" << HOOK
#!/bin/bash
# $hook hook - Custom hook
# Managed by git-hooks.sh

set -e

echo "Running $hook hook..."

# Add your custom logic here

exit 0
HOOK

    chmod +x "$template_file"
    log_success "Created template: $template_file"
    echo "Edit the template to customize the hook behavior"
}

# Parse arguments
VERBOSE=false
COMMAND=""
ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --all)
            ALL_HOOKS=true
            shift
            ;;
        install|uninstall|list|enable|disable|test|create)
            COMMAND="$1"
            shift
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

# Execute command
case "$COMMAND" in
    install)
        install_hooks "${ARGS[0]:-.}"
        ;;
    uninstall)
        uninstall_hooks "${ARGS[0]:-.}"
        ;;
    list)
        list_hooks "${ARGS[0]:-.}"
        ;;
    enable)
        if [[ ${#ARGS[@]} -eq 0 ]]; then
            log_error "Hook name required"
            exit 1
        fi
        enable_hook "${ARGS[0]}" "${ARGS[1]:-.}"
        ;;
    disable)
        if [[ ${#ARGS[@]} -eq 0 ]]; then
            log_error "Hook name required"
            exit 1
        fi
        disable_hook "${ARGS[0]}" "${ARGS[1]:-.}"
        ;;
    test)
        if [[ ${#ARGS[@]} -eq 0 ]]; then
            log_error "Hook name required"
            exit 1
        fi
        test_hook "${ARGS[@]}"
        ;;
    create)
        if [[ ${#ARGS[@]} -eq 0 ]]; then
            log_error "Hook name required"
            exit 1
        fi
        create_hook "${ARGS[0]}"
        ;;
    "")
        usage
        exit 1
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac

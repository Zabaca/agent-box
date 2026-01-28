#!/bin/bash
#
# Backup System
# Creates and manages backups of critical agent configurations
#
# Usage: backup.sh <command> [options]
#   create       Create a new backup
#   restore      Restore from a backup
#   list         List available backups
#   prune        Remove old backups (keep last N)
#   verify       Verify backup integrity

set -uo pipefail

WORKSPACE="/agent-workspace"
BACKUP_DIR="$WORKSPACE/.claude/backups"
CONFIG_FILE="$WORKSPACE/.claude/backup.conf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default settings
MAX_BACKUPS=10
COMPRESS=true

# Critical files to backup
CRITICAL_FILES=(
    "$WORKSPACE/CLAUDE.md"
    "$WORKSPACE/.claude/loop/memory.md"
    "$WORKSPACE/.claude/loop/tasks.md"
    "$WORKSPACE/.claude/loop/goals.md"
    "$WORKSPACE/.claude/loop/state.json"
    "$WORKSPACE/.claude/learnings.md"
    "$WORKSPACE/.claude/health.json"
)

# Critical directories to backup
CRITICAL_DIRS=(
    "$WORKSPACE/.claude/scripts"
    "$WORKSPACE/.claude/hooks"
    "$WORKSPACE/.claude/services"
)

usage() {
    cat << 'EOF'
Backup System - Manage critical configuration backups

Usage: backup.sh <command> [options]

Commands:
  create [name]    Create a new backup (optional name suffix)
  restore <name>   Restore from a specific backup
  list             List available backups
  prune [N]        Remove old backups, keep last N (default: 10)
  verify [name]    Verify backup integrity
  auto             Create timestamped backup (for automation)

Options:
  --no-compress    Don't compress the backup
  -v, --verbose    Verbose output
  -h, --help       Show this help

Examples:
  backup.sh create                    # Create timestamped backup
  backup.sh create before-update      # Create named backup
  backup.sh list                      # List all backups
  backup.sh restore 2026-01-20        # Restore specific backup
  backup.sh prune 5                   # Keep only last 5 backups
  backup.sh verify                    # Verify latest backup

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

# Ensure backup directory exists
ensure_backup_dir() {
    mkdir -p "$BACKUP_DIR"
}

# Generate backup name with timestamp
generate_backup_name() {
    local suffix="${1:-}"
    local timestamp
    timestamp=$(date +%Y-%m-%d_%H%M%S)

    if [[ -n "$suffix" ]]; then
        echo "backup_${timestamp}_${suffix}"
    else
        echo "backup_${timestamp}"
    fi
}

# Create a backup
create_backup() {
    local suffix="${1:-}"
    local backup_name
    backup_name=$(generate_backup_name "$suffix")
    local backup_path="$BACKUP_DIR/$backup_name"

    ensure_backup_dir

    log_info "Creating backup: $backup_name"

    # Create backup directory
    mkdir -p "$backup_path"

    # Backup critical files
    local files_backed=0
    for file in "${CRITICAL_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            local relative_path="${file#$WORKSPACE/}"
            local target_dir="$backup_path/$(dirname "$relative_path")"
            mkdir -p "$target_dir"
            cp "$file" "$target_dir/"
            ((files_backed++))
        fi
    done

    # Backup critical directories
    local dirs_backed=0
    for dir in "${CRITICAL_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            local relative_path="${dir#$WORKSPACE/}"
            local target_dir="$backup_path/$(dirname "$relative_path")"
            mkdir -p "$target_dir"
            cp -r "$dir" "$target_dir/"
            ((dirs_backed++))
        fi
    done

    # Create manifest
    cat > "$backup_path/manifest.json" << EOF
{
    "name": "$backup_name",
    "created": "$(date -Iseconds)",
    "files_backed": $files_backed,
    "dirs_backed": $dirs_backed,
    "compressed": false
}
EOF

    # Compress if enabled
    if [[ "$COMPRESS" == true ]]; then
        log_info "Compressing backup..."
        tar -czf "${backup_path}.tar.gz" -C "$BACKUP_DIR" "$backup_name"
        rm -rf "$backup_path"

        # Update manifest in archive
        local size
        size=$(du -h "${backup_path}.tar.gz" | cut -f1)
        log_success "Backup created: ${backup_name}.tar.gz ($size)"
    else
        local size
        size=$(du -sh "$backup_path" | cut -f1)
        log_success "Backup created: $backup_name ($size)"
    fi

    log_info "Files backed up: $files_backed"
    log_info "Directories backed up: $dirs_backed"
}

# List available backups
list_backups() {
    ensure_backup_dir

    echo -e "${BLUE}Available Backups:${NC}"
    echo "═══════════════════════════════════════════"

    local count=0

    # List compressed backups
    for backup in "$BACKUP_DIR"/*.tar.gz; do
        [[ -f "$backup" ]] || continue
        local name
        name=$(basename "$backup" .tar.gz)
        local size
        size=$(du -h "$backup" | cut -f1)
        local date
        date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1)

        printf "  %-35s %8s  %s\n" "$name" "$size" "$date"
        ((count++))
    done

    # List uncompressed backups
    for backup in "$BACKUP_DIR"/backup_*; do
        [[ -d "$backup" ]] || continue
        local name
        name=$(basename "$backup")
        local size
        size=$(du -sh "$backup" | cut -f1)
        local date
        date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1)

        printf "  %-35s %8s  %s\n" "$name" "$size" "$date"
        ((count++))
    done

    echo "═══════════════════════════════════════════"
    echo "Total backups: $count"
}

# Restore from a backup
restore_backup() {
    local backup_name="$1"

    # Find the backup
    local backup_path=""

    if [[ -f "$BACKUP_DIR/${backup_name}.tar.gz" ]]; then
        backup_path="$BACKUP_DIR/${backup_name}.tar.gz"
    elif [[ -f "$BACKUP_DIR/${backup_name}" ]]; then
        backup_path="$BACKUP_DIR/${backup_name}"
    elif [[ -d "$BACKUP_DIR/${backup_name}" ]]; then
        backup_path="$BACKUP_DIR/${backup_name}"
    else
        # Try to find partial match
        local matches
        matches=$(find "$BACKUP_DIR" -maxdepth 1 -name "*${backup_name}*" 2>/dev/null | head -1)
        if [[ -n "$matches" ]]; then
            backup_path="$matches"
        fi
    fi

    if [[ -z "$backup_path" ]] || [[ ! -e "$backup_path" ]]; then
        log_error "Backup not found: $backup_name"
        return 1
    fi

    log_info "Restoring from: $(basename "$backup_path")"

    # Create a safety backup before restore
    log_info "Creating safety backup before restore..."
    create_backup "pre-restore"

    # Extract if compressed
    local restore_dir="$backup_path"
    if [[ "$backup_path" == *.tar.gz ]]; then
        restore_dir=$(mktemp -d)
        tar -xzf "$backup_path" -C "$restore_dir"
        restore_dir="$restore_dir/$(basename "$backup_path" .tar.gz)"
    fi

    # Restore files
    local restored=0

    # Copy files back
    if [[ -d "$restore_dir" ]]; then
        # Restore using rsync-like copy
        for item in "$restore_dir"/*; do
            [[ -e "$item" ]] || continue
            local name
            name=$(basename "$item")

            # Skip manifest
            [[ "$name" == "manifest.json" ]] && continue

            if [[ -d "$item" ]]; then
                cp -r "$item" "$WORKSPACE/"
                ((restored++))
            elif [[ -f "$item" ]]; then
                cp "$item" "$WORKSPACE/"
                ((restored++))
            fi
        done
    fi

    # Clean up temp dir if used
    if [[ "$backup_path" == *.tar.gz ]]; then
        rm -rf "$(dirname "$restore_dir")"
    fi

    log_success "Restore complete: $restored items restored"
    log_info "Safety backup created as 'pre-restore'"
}

# Prune old backups
prune_backups() {
    local keep="${1:-$MAX_BACKUPS}"

    ensure_backup_dir

    log_info "Pruning backups, keeping last $keep..."

    # Get list of backups sorted by date (newest first)
    local backups=()

    for backup in "$BACKUP_DIR"/*.tar.gz "$BACKUP_DIR"/backup_*; do
        [[ -e "$backup" ]] || continue
        backups+=("$backup")
    done

    # Sort by modification time
    IFS=$'\n' sorted=($(ls -t "${backups[@]}" 2>/dev/null))
    unset IFS

    local count=${#sorted[@]}
    local removed=0

    if [[ $count -le $keep ]]; then
        log_info "Only $count backups exist, nothing to prune"
        return 0
    fi

    # Remove old backups
    for ((i=keep; i<count; i++)); do
        local backup="${sorted[$i]}"
        log_info "Removing: $(basename "$backup")"
        rm -rf "$backup"
        ((removed++))
    done

    log_success "Pruned $removed old backups"
}

# Verify backup integrity
verify_backup() {
    local backup_name="${1:-}"

    ensure_backup_dir

    # If no name given, verify latest
    if [[ -z "$backup_name" ]]; then
        backup_name=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)
        if [[ -z "$backup_name" ]]; then
            backup_name=$(ls -td "$BACKUP_DIR"/backup_* 2>/dev/null | head -1)
        fi
    fi

    if [[ -z "$backup_name" ]] || [[ ! -e "$backup_name" ]]; then
        # Try to find by name
        if [[ -e "$BACKUP_DIR/${backup_name}.tar.gz" ]]; then
            backup_name="$BACKUP_DIR/${backup_name}.tar.gz"
        elif [[ -d "$BACKUP_DIR/${backup_name}" ]]; then
            backup_name="$BACKUP_DIR/${backup_name}"
        else
            log_error "No backup found to verify"
            return 1
        fi
    fi

    log_info "Verifying: $(basename "$backup_name")"

    local issues=0

    if [[ "$backup_name" == *.tar.gz ]]; then
        # Verify compressed archive
        if tar -tzf "$backup_name" &>/dev/null; then
            log_success "Archive integrity: OK"
        else
            log_error "Archive integrity: FAILED"
            ((issues++))
        fi

        # List contents
        local file_count
        file_count=$(tar -tzf "$backup_name" | wc -l)
        log_info "Files in archive: $file_count"

    elif [[ -d "$backup_name" ]]; then
        # Verify uncompressed backup
        if [[ -f "$backup_name/manifest.json" ]]; then
            log_success "Manifest: OK"
        else
            log_warn "Manifest: MISSING"
            ((issues++))
        fi

        local file_count
        file_count=$(find "$backup_name" -type f | wc -l)
        log_info "Files in backup: $file_count"
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Backup verification: PASSED"
        return 0
    else
        log_error "Backup verification: FAILED ($issues issues)"
        return 1
    fi
}

# Auto backup (for scheduled tasks)
auto_backup() {
    log_info "Running automated backup..."
    create_backup "auto"
    prune_backups "$MAX_BACKUPS"
}

# Parse arguments
VERBOSE=false
COMMAND=""
ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-compress)
            COMPRESS=false
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        create|restore|list|prune|verify|auto)
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
    create)
        create_backup "${ARGS[0]:-}"
        ;;
    restore)
        if [[ ${#ARGS[@]} -eq 0 ]]; then
            log_error "Backup name required for restore"
            usage
            exit 1
        fi
        restore_backup "${ARGS[0]}"
        ;;
    list)
        list_backups
        ;;
    prune)
        prune_backups "${ARGS[0]:-$MAX_BACKUPS}"
        ;;
    verify)
        verify_backup "${ARGS[0]:-}"
        ;;
    auto)
        auto_backup
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

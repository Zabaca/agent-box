#!/bin/bash
#
# Environment Variable Manager
# Manage .env files - get, set, list, validate, and sync
#
# Usage: env-manager.sh <command> [options]
#   get <key>              Get variable value
#   set <key> <value>      Set variable value
#   list                   List all variables
#   delete <key>           Delete a variable
#   check                  Validate .env syntax
#   diff <file1> <file2>   Compare two .env files
#   merge <source>         Merge another .env file
#   export                 Export as shell commands
#   template               Generate .env.example
#   -f FILE                Use specific file (default: .env)
#   -h, --help             Show help

set -uo pipefail

# Defaults
ENV_FILE=".env"
QUIET=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat << 'EOF'
Environment Variable Manager - Manage .env files

Usage: env-manager.sh <command> [options] [args]

Commands:
  get <key>              Get value of a variable
  set <key> <value>      Set or update a variable
  list                   List all variables
  delete <key>           Remove a variable
  check                  Validate .env file syntax
  diff <file2>           Compare with another .env file
  merge <source>         Merge variables from another file
  export                 Output as shell export commands
  template               Generate .env.example (values masked)
  keys                   List just the variable names
  search <pattern>       Search keys/values

Options:
  -f FILE                Specify .env file (default: .env)
  -q, --quiet            Suppress output (for scripts)
  -h, --help             Show this help

Examples:
  env-manager.sh get DATABASE_URL
  env-manager.sh set API_KEY "secret123"
  env-manager.sh -f .env.production list
  env-manager.sh diff .env.production
  env-manager.sh merge .env.defaults
  env-manager.sh template > .env.example
  env-manager.sh export | source /dev/stdin

File Format:
  # Comment lines start with #
  KEY=value
  KEY="quoted value"
  KEY='single quoted'
  MULTILINE="line1\nline2"

Notes:
  - Creates .env file if it doesn't exist
  - Preserves comments and blank lines
  - Handles quoted values correctly
EOF
}

# Ensure .env file exists
ensure_file() {
    if [[ ! -f "$ENV_FILE" ]]; then
        touch "$ENV_FILE"
        [[ "$QUIET" == "false" ]] && echo -e "${YELLOW}Created:${NC} $ENV_FILE"
    fi
}

# Get a variable value
cmd_get() {
    local key="$1"

    if [[ ! -f "$ENV_FILE" ]]; then
        echo ""
        return 1
    fi

    # Find the key and extract value
    local line
    line=$(grep -E "^${key}=" "$ENV_FILE" | tail -1)

    if [[ -z "$line" ]]; then
        return 1
    fi

    # Extract value (handle quotes)
    local value="${line#*=}"

    # Remove surrounding quotes
    if [[ "$value" =~ ^\"(.*)\"$ ]]; then
        value="${BASH_REMATCH[1]}"
    elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]}"
    fi

    echo "$value"
}

# Set a variable
cmd_set() {
    local key="$1"
    local value="$2"

    ensure_file

    # Escape special characters in value for sed
    local escaped_value="$value"

    # Quote value if it contains spaces or special chars
    if [[ "$value" =~ [[:space:]] || "$value" =~ [\#\$\`] ]]; then
        escaped_value="\"$value\""
    fi

    # Check if key exists
    if grep -qE "^${key}=" "$ENV_FILE" 2>/dev/null; then
        # Update existing
        local temp_file
        temp_file=$(mktemp)
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^${key}= ]]; then
                echo "${key}=${escaped_value}"
            else
                echo "$line"
            fi
        done < "$ENV_FILE" > "$temp_file"
        mv "$temp_file" "$ENV_FILE"
        [[ "$QUIET" == "false" ]] && echo -e "${GREEN}Updated:${NC} $key"
    else
        # Add new
        echo "${key}=${escaped_value}" >> "$ENV_FILE"
        [[ "$QUIET" == "false" ]] && echo -e "${GREEN}Added:${NC} $key"
    fi
}

# List all variables
cmd_list() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "No .env file found"
        return 1
    fi

    echo -e "${BLUE}Variables in $ENV_FILE:${NC}"
    echo "─────────────────────────────────────────"

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Mask sensitive values
            if [[ "$key" =~ (PASSWORD|SECRET|KEY|TOKEN|CREDENTIAL) ]]; then
                value="****"
            elif [[ ${#value} -gt 50 ]]; then
                value="${value:0:47}..."
            fi

            printf "  ${CYAN}%-30s${NC} = %s\n" "$key" "$value"
        fi
    done < "$ENV_FILE"
}

# Delete a variable
cmd_delete() {
    local key="$1"

    if [[ ! -f "$ENV_FILE" ]]; then
        echo "No .env file found"
        return 1
    fi

    if ! grep -qE "^${key}=" "$ENV_FILE"; then
        [[ "$QUIET" == "false" ]] && echo -e "${YELLOW}Not found:${NC} $key"
        return 1
    fi

    local temp_file
    temp_file=$(mktemp)
    grep -vE "^${key}=" "$ENV_FILE" > "$temp_file"
    mv "$temp_file" "$ENV_FILE"

    [[ "$QUIET" == "false" ]] && echo -e "${GREEN}Deleted:${NC} $key"
}

# Validate .env syntax
cmd_check() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "No .env file found"
        return 1
    fi

    echo -e "${BLUE}Validating $ENV_FILE:${NC}"
    echo "─────────────────────────────────────────"

    local errors=0
    local warnings=0
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip blank lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Check for valid format
        if [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            echo -e "  ${RED}Line $line_num:${NC} Invalid format: $line"
            ((errors++))
            continue
        fi

        # Extract key and value
        local key="${line%%=*}"
        local value="${line#*=}"

        # Check for common issues
        if [[ -z "$value" ]]; then
            echo -e "  ${YELLOW}Line $line_num:${NC} Empty value for $key"
            ((warnings++))
        fi

        # Check for unquoted spaces
        if [[ "$value" =~ [[:space:]] && ! "$value" =~ ^[\"\'] ]]; then
            echo -e "  ${YELLOW}Line $line_num:${NC} Unquoted value with spaces: $key"
            ((warnings++))
        fi

        # Check for potential secrets without masking
        if [[ "$key" =~ (PASSWORD|SECRET|KEY|TOKEN) && "$value" != "****" && ${#value} -gt 0 ]]; then
            echo -e "  ${CYAN}Line $line_num:${NC} Sensitive variable: $key"
        fi

    done < "$ENV_FILE"

    echo ""
    if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
        echo -e "${GREEN}✓ Valid${NC} - No issues found"
        return 0
    else
        echo -e "Errors: ${RED}$errors${NC}, Warnings: ${YELLOW}$warnings${NC}"
        return $errors
    fi
}

# Diff two .env files
cmd_diff() {
    local file2="$1"

    if [[ ! -f "$ENV_FILE" ]]; then
        echo "Source file not found: $ENV_FILE"
        return 1
    fi
    if [[ ! -f "$file2" ]]; then
        echo "Target file not found: $file2"
        return 1
    fi

    echo -e "${BLUE}Comparing $ENV_FILE vs $file2:${NC}"
    echo "─────────────────────────────────────────"

    # Get keys from both files
    local keys1 keys2
    keys1=$(grep -E "^[A-Za-z_][A-Za-z0-9_]*=" "$ENV_FILE" | cut -d= -f1 | sort)
    keys2=$(grep -E "^[A-Za-z_][A-Za-z0-9_]*=" "$file2" | cut -d= -f1 | sort)

    # Only in file1
    local only1
    only1=$(comm -23 <(echo "$keys1") <(echo "$keys2"))
    if [[ -n "$only1" ]]; then
        echo -e "\n${RED}Only in $ENV_FILE:${NC}"
        echo "$only1" | sed 's/^/  - /'
    fi

    # Only in file2
    local only2
    only2=$(comm -13 <(echo "$keys1") <(echo "$keys2"))
    if [[ -n "$only2" ]]; then
        echo -e "\n${GREEN}Only in $file2:${NC}"
        echo "$only2" | sed 's/^/  + /'
    fi

    # Different values
    local common
    common=$(comm -12 <(echo "$keys1") <(echo "$keys2"))
    local different=""
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        local val1 val2
        val1=$(grep -E "^${key}=" "$ENV_FILE" | cut -d= -f2-)
        val2=$(grep -E "^${key}=" "$file2" | cut -d= -f2-)
        if [[ "$val1" != "$val2" ]]; then
            different+="  $key\n"
        fi
    done <<< "$common"

    if [[ -n "$different" ]]; then
        echo -e "\n${YELLOW}Different values:${NC}"
        echo -e "$different"
    fi

    if [[ -z "$only1" && -z "$only2" && -z "$different" ]]; then
        echo -e "${GREEN}Files are identical${NC}"
    fi
}

# Merge from another file
cmd_merge() {
    local source="$1"

    if [[ ! -f "$source" ]]; then
        echo "Source file not found: $source"
        return 1
    fi

    ensure_file

    local added=0
    local updated=0
    local skipped=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            if grep -qE "^${key}=" "$ENV_FILE" 2>/dev/null; then
                ((skipped++))
            else
                echo "$line" >> "$ENV_FILE"
                ((added++))
            fi
        fi
    done < "$source"

    echo -e "${GREEN}Merged from $source:${NC}"
    echo "  Added: $added"
    echo "  Skipped (existing): $skipped"
}

# Export as shell commands
cmd_export() {
    if [[ ! -f "$ENV_FILE" ]]; then
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            echo "export ${key}=${value}"
        fi
    done < "$ENV_FILE"
}

# Generate template
cmd_template() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "No .env file found"
        return 1
    fi

    echo "# Environment Variables Template"
    echo "# Copy to .env and fill in values"
    echo ""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Keep comments as-is
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
            echo "$line"
            continue
        fi

        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
            local key="${BASH_REMATCH[1]}"
            echo "${key}="
        fi
    done < "$ENV_FILE"
}

# List just keys
cmd_keys() {
    if [[ ! -f "$ENV_FILE" ]]; then
        return 1
    fi

    grep -E "^[A-Za-z_][A-Za-z0-9_]*=" "$ENV_FILE" | cut -d= -f1 | sort
}

# Search keys/values
cmd_search() {
    local pattern="$1"

    if [[ ! -f "$ENV_FILE" ]]; then
        return 1
    fi

    grep -iE "$pattern" "$ENV_FILE" | while IFS= read -r line; do
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            echo -e "${CYAN}$key${NC}=$value"
        fi
    done
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f)
            ENV_FILE="$2"
            shift 2
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        get|set|list|delete|check|diff|merge|export|template|keys|search)
            CMD="$1"
            shift
            break
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Execute command
case "${CMD:-}" in
    get)
        [[ $# -lt 1 ]] && { echo "Usage: env-manager.sh get <key>"; exit 1; }
        cmd_get "$1"
        ;;
    set)
        [[ $# -lt 2 ]] && { echo "Usage: env-manager.sh set <key> <value>"; exit 1; }
        cmd_set "$1" "$2"
        ;;
    list)
        cmd_list
        ;;
    delete)
        [[ $# -lt 1 ]] && { echo "Usage: env-manager.sh delete <key>"; exit 1; }
        cmd_delete "$1"
        ;;
    check)
        cmd_check
        ;;
    diff)
        [[ $# -lt 1 ]] && { echo "Usage: env-manager.sh diff <file2>"; exit 1; }
        cmd_diff "$1"
        ;;
    merge)
        [[ $# -lt 1 ]] && { echo "Usage: env-manager.sh merge <source>"; exit 1; }
        cmd_merge "$1"
        ;;
    export)
        cmd_export
        ;;
    template)
        cmd_template
        ;;
    keys)
        cmd_keys
        ;;
    search)
        [[ $# -lt 1 ]] && { echo "Usage: env-manager.sh search <pattern>"; exit 1; }
        cmd_search "$1"
        ;;
    "")
        usage
        ;;
    *)
        echo "Unknown command: $CMD"
        usage
        exit 1
        ;;
esac

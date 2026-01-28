#!/bin/bash
#
# Task Decomposer
# Break down high-level goals into actionable subtasks using templates
#
# Usage: task-decomposer.sh <command> [options]
#   decompose <goal>          Break goal into subtasks
#   templates                 List available task templates
#   add-template <name>       Add a custom template
#   analyze <goal>            Analyze goal without generating tasks
#   queue <goal>              Decompose and add to task queue
#   -h, --help                Show help

set -uo pipefail

WORKSPACE="/agent-workspace"
TEMPLATES_DIR="$WORKSPACE/.claude/task-templates"
TASKS_FILE="$WORKSPACE/.claude/loop/tasks.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat << 'EOF'
Task Decomposer - Break goals into actionable subtasks

Usage: task-decomposer.sh <command> [options]

Commands:
  decompose <goal>          Break goal into subtasks (outputs to stdout)
  templates                 List available task templates
  add-template <name>       Add a custom template interactively
  analyze <goal>            Analyze goal type and complexity
  queue <goal>              Decompose and add tasks to queue
  estimate <goal>           Estimate effort for a goal

Templates:
  Built-in templates for common goal types:
  - feature: New feature implementation
  - bugfix: Bug fix workflow
  - refactor: Code refactoring
  - script: Create a new script/tool
  - project: New project setup
  - test: Testing improvements
  - docs: Documentation updates
  - deploy: Deployment tasks

Examples:
  task-decomposer.sh decompose "Add user authentication"
  task-decomposer.sh analyze "Fix login bug"
  task-decomposer.sh queue "Create backup system"
  task-decomposer.sh templates
EOF
}

# Initialize templates
init_templates() {
    mkdir -p "$TEMPLATES_DIR"

    # Feature template
    if [[ ! -f "$TEMPLATES_DIR/feature.txt" ]]; then
        cat > "$TEMPLATES_DIR/feature.txt" << 'TEMPLATE'
# Feature: {{GOAL}}
## Subtasks
- [ ] Research existing implementation and patterns
- [ ] Design the feature architecture
- [ ] Implement core functionality
- [ ] Add error handling and edge cases
- [ ] Write tests for the feature
- [ ] Update documentation
- [ ] Manual testing and verification
TEMPLATE
    fi

    # Bugfix template
    if [[ ! -f "$TEMPLATES_DIR/bugfix.txt" ]]; then
        cat > "$TEMPLATES_DIR/bugfix.txt" << 'TEMPLATE'
# Bugfix: {{GOAL}}
## Subtasks
- [ ] Reproduce the bug
- [ ] Identify root cause
- [ ] Implement fix
- [ ] Test the fix
- [ ] Verify no regression
TEMPLATE
    fi

    # Refactor template
    if [[ ! -f "$TEMPLATES_DIR/refactor.txt" ]]; then
        cat > "$TEMPLATES_DIR/refactor.txt" << 'TEMPLATE'
# Refactor: {{GOAL}}
## Subtasks
- [ ] Analyze current code structure
- [ ] Plan refactoring approach
- [ ] Create backup/checkpoint
- [ ] Implement refactoring changes
- [ ] Run tests to verify behavior
- [ ] Update related documentation
TEMPLATE
    fi

    # Script template
    if [[ ! -f "$TEMPLATES_DIR/script.txt" ]]; then
        cat > "$TEMPLATES_DIR/script.txt" << 'TEMPLATE'
# Script: {{GOAL}}
## Subtasks
- [ ] Define requirements and interface
- [ ] Write the core script logic
- [ ] Add argument parsing and help
- [ ] Add error handling
- [ ] Test with various inputs
- [ ] Make executable and add to inventory
TEMPLATE
    fi

    # Project template
    if [[ ! -f "$TEMPLATES_DIR/project.txt" ]]; then
        cat > "$TEMPLATES_DIR/project.txt" << 'TEMPLATE'
# Project: {{GOAL}}
## Subtasks
- [ ] Create project directory structure
- [ ] Initialize version control
- [ ] Set up build/package configuration
- [ ] Implement core functionality
- [ ] Add README documentation
- [ ] Create example usage
- [ ] Register in project manager
TEMPLATE
    fi

    # Test template
    if [[ ! -f "$TEMPLATES_DIR/test.txt" ]]; then
        cat > "$TEMPLATES_DIR/test.txt" << 'TEMPLATE'
# Testing: {{GOAL}}
## Subtasks
- [ ] Identify test coverage gaps
- [ ] Write unit tests
- [ ] Write integration tests
- [ ] Run full test suite
- [ ] Document test results
TEMPLATE
    fi

    # Docs template
    if [[ ! -f "$TEMPLATES_DIR/docs.txt" ]]; then
        cat > "$TEMPLATES_DIR/docs.txt" << 'TEMPLATE'
# Documentation: {{GOAL}}
## Subtasks
- [ ] Review current documentation
- [ ] Identify gaps or outdated content
- [ ] Write/update documentation
- [ ] Add examples where helpful
- [ ] Verify accuracy
TEMPLATE
    fi

    # Deploy template
    if [[ ! -f "$TEMPLATES_DIR/deploy.txt" ]]; then
        cat > "$TEMPLATES_DIR/deploy.txt" << 'TEMPLATE'
# Deployment: {{GOAL}}
## Subtasks
- [ ] Verify all tests pass
- [ ] Update version numbers if needed
- [ ] Build/package the project
- [ ] Deploy to target environment
- [ ] Verify deployment success
- [ ] Update deployment documentation
TEMPLATE
    fi
}

# Detect goal type from keywords
detect_goal_type() {
    local goal="$1"
    local goal_lower
    goal_lower=$(echo "$goal" | tr '[:upper:]' '[:lower:]')

    # Check for type keywords
    if [[ "$goal_lower" =~ (fix|bug|error|issue|problem|crash|broken) ]]; then
        echo "bugfix"
    elif [[ "$goal_lower" =~ (refactor|clean|improve|optimize|reorganize) ]]; then
        echo "refactor"
    elif [[ "$goal_lower" =~ (script|tool|utility|command|cli) ]]; then
        echo "script"
    elif [[ "$goal_lower" =~ (project|app|application|system|service) ]]; then
        echo "project"
    elif [[ "$goal_lower" =~ (test|testing|coverage|verify|validate) ]]; then
        echo "test"
    elif [[ "$goal_lower" =~ (doc|document|readme|guide|tutorial) ]]; then
        echo "docs"
    elif [[ "$goal_lower" =~ (deploy|release|publish|ship|launch) ]]; then
        echo "deploy"
    else
        echo "feature"
    fi
}

# Estimate complexity
estimate_complexity() {
    local goal="$1"
    local word_count
    word_count=$(echo "$goal" | wc -w)

    # Simple heuristic based on goal description
    local complexity="medium"

    if [[ $word_count -le 3 ]]; then
        complexity="simple"
    elif [[ $word_count -ge 8 ]]; then
        complexity="complex"
    fi

    # Check for complexity indicators
    local goal_lower
    goal_lower=$(echo "$goal" | tr '[:upper:]' '[:lower:]')

    if [[ "$goal_lower" =~ (simple|quick|small|minor|trivial) ]]; then
        complexity="simple"
    elif [[ "$goal_lower" =~ (complex|large|major|comprehensive|full|complete) ]]; then
        complexity="complex"
    fi

    echo "$complexity"
}

# Decompose a goal into subtasks
cmd_decompose() {
    local goal="$1"
    local template_type="${2:-}"

    init_templates

    # Auto-detect type if not specified
    if [[ -z "$template_type" ]]; then
        template_type=$(detect_goal_type "$goal")
    fi

    local template_file="$TEMPLATES_DIR/${template_type}.txt"

    if [[ ! -f "$template_file" ]]; then
        echo -e "${RED}Error:${NC} Template not found: $template_type"
        echo "Available templates: $(ls "$TEMPLATES_DIR" | sed 's/.txt//g' | tr '\n' ' ')"
        return 1
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Task Decomposition                                           ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Goal: ${CYAN}$goal${NC}"
    echo -e "Type: ${GREEN}$template_type${NC}"
    echo -e "Complexity: ${YELLOW}$(estimate_complexity "$goal")${NC}"
    echo ""
    echo "─────────────────────────────────────────"
    echo ""

    # Apply template with goal substitution
    sed "s/{{GOAL}}/$goal/g" "$template_file"
}

# List available templates
cmd_templates() {
    init_templates

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Available Task Templates                                     ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    for template in "$TEMPLATES_DIR"/*.txt; do
        local name
        name=$(basename "$template" .txt)
        local task_count
        task_count=$(grep -c '^\- \[ \]' "$template" || echo 0)

        echo -e "${CYAN}$name${NC} ($task_count subtasks)"

        # Show first few tasks
        grep '^\- \[ \]' "$template" | head -3 | sed 's/^/    /'
        local total
        total=$(grep -c '^\- \[ \]' "$template" || echo 0)
        if [[ $total -gt 3 ]]; then
            echo "    ... and $((total - 3)) more"
        fi
        echo ""
    done
}

# Add a custom template
cmd_add_template() {
    local name="$1"

    init_templates

    local template_file="$TEMPLATES_DIR/${name}.txt"

    if [[ -f "$template_file" ]]; then
        echo -e "${YELLOW}Warning:${NC} Template '$name' already exists. Overwrite? (y/n)"
        read -r response
        if [[ "$response" != "y" ]]; then
            echo "Cancelled"
            return
        fi
    fi

    echo "Enter subtasks (one per line, empty line to finish):"
    echo "Format: - [ ] Task description"
    echo ""

    cat > "$template_file" << HEADER
# {{GOAL}}
## Subtasks
HEADER

    while true; do
        read -r task
        [[ -z "$task" ]] && break
        echo "$task" >> "$template_file"
    done

    echo -e "${GREEN}✓${NC} Template '$name' created with $(grep -c '^\- \[ \]' "$template_file" || echo 0) subtasks"
}

# Analyze a goal
cmd_analyze() {
    local goal="$1"

    init_templates

    local type
    type=$(detect_goal_type "$goal")
    local complexity
    complexity=$(estimate_complexity "$goal")

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Goal Analysis                                                ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Goal: ${CYAN}$goal${NC}"
    echo ""
    echo "Analysis:"
    echo "  Type:       $type"
    echo "  Complexity: $complexity"
    echo "  Words:      $(echo "$goal" | wc -w)"
    echo ""

    # Show matched keywords
    local goal_lower
    goal_lower=$(echo "$goal" | tr '[:upper:]' '[:lower:]')

    echo "Detected keywords:"
    for keyword in fix bug refactor script project test doc deploy feature add create implement build; do
        if [[ "$goal_lower" =~ $keyword ]]; then
            echo "  - $keyword"
        fi
    done
    echo ""

    # Estimate subtasks
    local template_file="$TEMPLATES_DIR/${type}.txt"
    if [[ -f "$template_file" ]]; then
        local subtask_count
        subtask_count=$(grep -c '^\- \[ \]' "$template_file" || echo 0)
        echo "Estimated subtasks: $subtask_count (from $type template)"
    fi
}

# Decompose and add to task queue
cmd_queue() {
    local goal="$1"
    local template_type="${2:-}"

    init_templates

    # Auto-detect type
    if [[ -z "$template_type" ]]; then
        template_type=$(detect_goal_type "$goal")
    fi

    local template_file="$TEMPLATES_DIR/${template_type}.txt"

    if [[ ! -f "$template_file" ]]; then
        echo -e "${RED}Error:${NC} Template not found: $template_type"
        return 1
    fi

    # Get subtasks from template
    local subtasks
    subtasks=$(grep '^\- \[ \]' "$template_file" | sed "s/{{GOAL}}/$goal/g")

    # Add to task queue
    if [[ ! -f "$TASKS_FILE" ]]; then
        echo "# Task Queue" > "$TASKS_FILE"
        echo "" >> "$TASKS_FILE"
        echo "## Pending" >> "$TASKS_FILE"
    fi

    # Read current pending section
    local pending_line
    pending_line=$(grep -n "^## Pending" "$TASKS_FILE" | cut -d: -f1)
    local inprogress_line
    inprogress_line=$(grep -n "^## In Progress" "$TASKS_FILE" | cut -d: -f1)

    if [[ -z "$pending_line" ]]; then
        echo -e "${RED}Error:${NC} Cannot find Pending section in tasks file"
        return 1
    fi

    # Create temp file with new tasks inserted
    local temp_file
    temp_file=$(mktemp)

    # Add goal as comment
    local goal_comment="# Goal: $goal"

    head -n "$pending_line" "$TASKS_FILE" > "$temp_file"
    echo "$goal_comment" >> "$temp_file"
    echo "$subtasks" >> "$temp_file"

    if [[ -n "$inprogress_line" ]]; then
        tail -n +"$((pending_line + 1))" "$TASKS_FILE" >> "$temp_file"
    fi

    mv "$temp_file" "$TASKS_FILE"

    local count
    count=$(echo "$subtasks" | wc -l)

    echo -e "${GREEN}✓${NC} Added $count subtasks to queue for: $goal"
    echo ""
    echo "Subtasks added:"
    echo "$subtasks" | head -5
    if [[ $count -gt 5 ]]; then
        echo "  ... and $((count - 5)) more"
    fi
}

# Estimate effort
cmd_estimate() {
    local goal="$1"

    init_templates

    local type
    type=$(detect_goal_type "$goal")
    local complexity
    complexity=$(estimate_complexity "$goal")

    # Base subtask count from template
    local template_file="$TEMPLATES_DIR/${type}.txt"
    local subtask_count=5
    if [[ -f "$template_file" ]]; then
        subtask_count=$(grep -c '^\- \[ \]' "$template_file" || echo 5)
    fi

    # Adjust by complexity
    case "$complexity" in
        simple) subtask_count=$((subtask_count - 2)) ;;
        complex) subtask_count=$((subtask_count + 3)) ;;
    esac

    [[ $subtask_count -lt 2 ]] && subtask_count=2

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Effort Estimate                                              ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Goal: ${CYAN}$goal${NC}"
    echo ""
    echo "Estimate:"
    echo "  Type:           $type"
    echo "  Complexity:     $complexity"
    echo "  Subtasks:       ~$subtask_count"
    echo ""

    # Effort levels
    case "$complexity" in
        simple)
            echo -e "  Effort Level:   ${GREEN}Low${NC}"
            echo "  Suitable for:   Quick iteration, routine work"
            ;;
        medium)
            echo -e "  Effort Level:   ${YELLOW}Medium${NC}"
            echo "  Suitable for:   Standard development task"
            ;;
        complex)
            echo -e "  Effort Level:   ${RED}High${NC}"
            echo "  Suitable for:   Major feature, careful planning needed"
            ;;
    esac
}

# Main command dispatch
case "${1:-}" in
    decompose)
        if [[ $# -lt 2 ]]; then
            echo "Usage: task-decomposer.sh decompose <goal> [template-type]"
            exit 1
        fi
        shift
        cmd_decompose "$@"
        ;;
    templates)
        cmd_templates
        ;;
    add-template)
        if [[ $# -lt 2 ]]; then
            echo "Usage: task-decomposer.sh add-template <name>"
            exit 1
        fi
        cmd_add_template "$2"
        ;;
    analyze)
        if [[ $# -lt 2 ]]; then
            echo "Usage: task-decomposer.sh analyze <goal>"
            exit 1
        fi
        shift
        cmd_analyze "$*"
        ;;
    queue)
        if [[ $# -lt 2 ]]; then
            echo "Usage: task-decomposer.sh queue <goal> [template-type]"
            exit 1
        fi
        shift
        cmd_queue "$@"
        ;;
    estimate)
        if [[ $# -lt 2 ]]; then
            echo "Usage: task-decomposer.sh estimate <goal>"
            exit 1
        fi
        shift
        cmd_estimate "$*"
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

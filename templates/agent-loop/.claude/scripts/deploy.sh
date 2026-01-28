#!/bin/bash
#
# Project Deployment Script
# Simple deployment tool for projects in the agent workspace
#
# Usage: deploy.sh [options] <project> [target]
#   project      Project name or path
#   target       Deployment target (default: local)
#
# Options:
#   -t TYPE      Deployment type: local, docker, systemd, pm2
#   -e ENV       Environment: dev, staging, prod (default: dev)
#   -p PORT      Port to run service on
#   --dry-run    Show what would be done without doing it
#   --rollback   Rollback to previous deployment
#   -v           Verbose output
#   -h           Show help

set -uo pipefail

WORKSPACE="/agent-workspace"
PROJECTS_DIR="$WORKSPACE/projects"
DEPLOY_DIR="$WORKSPACE/.claude/deployments"
LOG_FILE="$WORKSPACE/.claude/loop/deploy.log"

# Defaults
PROJECT=""
TARGET="local"
DEPLOY_TYPE=""
ENVIRONMENT="dev"
PORT=""
DRY_RUN=false
ROLLBACK=false
VERBOSE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat << 'EOF'
Project Deployment Script

Usage: deploy.sh [options] <project> [target]

Arguments:
  project      Project name (from /agent-workspace/projects/) or path
  target       Deployment target (default: local)

Options:
  -t TYPE      Deployment type: local, docker, systemd, pm2
  -e ENV       Environment: dev, staging, prod (default: dev)
  -p PORT      Port for service
  --dry-run    Show what would be done
  --rollback   Rollback to previous deployment
  -v           Verbose output
  -h, --help   Show this help

Deployment Types:
  local        Run directly (node, python, bash)
  docker       Build and run Docker container
  systemd      Install as systemd service
  pm2          Deploy with PM2 process manager

Auto-Detection:
  Script automatically detects project type from:
  - package.json (Node.js) -> npm start / pm2
  - requirements.txt (Python) -> python main.py
  - Dockerfile -> docker build/run
  - main.sh or run.sh (Shell) -> bash

Examples:
  deploy.sh code-analyzer                    # Deploy locally
  deploy.sh -t docker status-server          # Deploy with Docker
  deploy.sh -t systemd -p 8080 my-api        # Deploy as systemd service
  deploy.sh --rollback my-api                # Rollback deployment
EOF
}

log() {
    local timestamp
    timestamp=$(date -Iseconds)
    echo "[$timestamp] $1" >> "$LOG_FILE"
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}→${NC} $1"
    fi
}

error() {
    echo -e "${RED}Error:${NC} $1" >&2
    log "ERROR: $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
    log "SUCCESS: $1"
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Detect project type
detect_project_type() {
    local project_path="$1"

    if [[ -f "$project_path/Dockerfile" ]]; then
        echo "docker"
    elif [[ -f "$project_path/package.json" ]]; then
        echo "node"
    elif [[ -f "$project_path/requirements.txt" ]] || [[ -f "$project_path/setup.py" ]]; then
        echo "python"
    elif [[ -f "$project_path/main.sh" ]] || [[ -f "$project_path/run.sh" ]] || ls "$project_path"/*.sh &>/dev/null; then
        echo "shell"
    elif [[ -f "$project_path/Cargo.toml" ]]; then
        echo "rust"
    elif [[ -f "$project_path/go.mod" ]]; then
        echo "go"
    else
        echo "unknown"
    fi
}

# Detect deployment type from project
detect_deploy_type() {
    local project_type="$1"

    case "$project_type" in
        docker) echo "docker" ;;
        node)   echo "pm2" ;;
        python) echo "local" ;;
        shell)  echo "local" ;;
        *)      echo "local" ;;
    esac
}

# Create deployment record
create_deployment_record() {
    local project="$1"
    local deploy_type="$2"
    local timestamp
    timestamp=$(date -Iseconds)

    local record_dir="$DEPLOY_DIR/$project"
    mkdir -p "$record_dir"

    # Save current as previous
    if [[ -f "$record_dir/current.json" ]]; then
        cp "$record_dir/current.json" "$record_dir/previous.json"
    fi

    # Create new record
    cat > "$record_dir/current.json" << EOF
{
    "project": "$project",
    "type": "$deploy_type",
    "environment": "$ENVIRONMENT",
    "port": "$PORT",
    "timestamp": "$timestamp",
    "status": "deployed"
}
EOF

    log "Created deployment record for $project"
}

# Deploy locally (run in background)
deploy_local() {
    local project_path="$1"
    local project_name="$2"
    local project_type="$3"

    info "Deploying locally: $project_name"

    local pid_file="$DEPLOY_DIR/$project_name/pid"
    local log_file="$DEPLOY_DIR/$project_name/output.log"

    # Stop existing if running
    if [[ -f "$pid_file" ]]; then
        local old_pid
        old_pid=$(cat "$pid_file")
        if kill -0 "$old_pid" 2>/dev/null; then
            log "Stopping existing process $old_pid"
            kill "$old_pid" 2>/dev/null || true
            sleep 1
        fi
    fi

    mkdir -p "$(dirname "$pid_file")"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would run $project_type project"
        return 0
    fi

    # Run based on type
    case "$project_type" in
        node)
            cd "$project_path" || exit 1
            if [[ -f "package-lock.json" ]] && [[ ! -d "node_modules" ]]; then
                npm install >> "$log_file" 2>&1
            fi
            nohup npm start >> "$log_file" 2>&1 &
            echo $! > "$pid_file"
            ;;
        python)
            cd "$project_path" || exit 1
            local entry_point
            if [[ -f "main.py" ]]; then
                entry_point="main.py"
            elif [[ -f "app.py" ]]; then
                entry_point="app.py"
            else
                entry_point=$(ls -1 *.py 2>/dev/null | head -1)
            fi
            nohup python3 "$entry_point" >> "$log_file" 2>&1 &
            echo $! > "$pid_file"
            ;;
        shell)
            cd "$project_path" || exit 1
            local script
            if [[ -f "run.sh" ]]; then
                script="run.sh"
            elif [[ -f "main.sh" ]]; then
                script="main.sh"
            else
                # Find first executable .sh file
                script=$(find . -maxdepth 1 -name "*.sh" -executable | head -1)
                [[ -z "$script" ]] && script=$(ls -1 *.sh 2>/dev/null | head -1)
            fi
            if [[ -z "$script" ]]; then
                error "No shell script found to run"
                return 1
            fi
            nohup bash "$script" >> "$log_file" 2>&1 &
            echo $! > "$pid_file"
            ;;
        *)
            error "Don't know how to run $project_type project"
            return 1
            ;;
    esac

    local pid
    pid=$(cat "$pid_file")
    sleep 1

    if kill -0 "$pid" 2>/dev/null; then
        success "Started $project_name (PID: $pid)"
        create_deployment_record "$project_name" "local"
        return 0
    else
        error "Process failed to start"
        return 1
    fi
}

# Deploy with Docker
deploy_docker() {
    local project_path="$1"
    local project_name="$2"

    info "Deploying with Docker: $project_name"

    local image_name="agent-$project_name"
    local container_name="$project_name"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would build image: $image_name"
        info "[DRY RUN] Would run container: $container_name"
        return 0
    fi

    # Stop existing container
    if docker ps -q -f "name=$container_name" | grep -q .; then
        log "Stopping existing container: $container_name"
        docker stop "$container_name" 2>/dev/null || true
        docker rm "$container_name" 2>/dev/null || true
    fi

    # Build image
    info "Building Docker image..."
    if ! docker build -t "$image_name" "$project_path"; then
        error "Docker build failed"
        return 1
    fi

    # Run container
    local docker_args=(-d --name "$container_name" --restart unless-stopped)
    if [[ -n "$PORT" ]]; then
        docker_args+=(-p "$PORT:$PORT")
    fi

    info "Starting container..."
    if docker run "${docker_args[@]}" "$image_name"; then
        success "Container $container_name is running"
        create_deployment_record "$project_name" "docker"
        return 0
    else
        error "Failed to start container"
        return 1
    fi
}

# Deploy with systemd
deploy_systemd() {
    local project_path="$1"
    local project_name="$2"
    local project_type="$3"

    info "Deploying as systemd service: $project_name"

    local service_name="agent-$project_name"
    local service_file="/etc/systemd/system/$service_name.service"

    # Determine exec command
    local exec_start
    case "$project_type" in
        node)
            exec_start="/usr/bin/npm start"
            ;;
        python)
            local entry="main.py"
            [[ -f "$project_path/app.py" ]] && entry="app.py"
            exec_start="/usr/bin/python3 $project_path/$entry"
            ;;
        shell)
            local script="run.sh"
            [[ -f "$project_path/main.sh" ]] && script="main.sh"
            exec_start="/bin/bash $project_path/$script"
            ;;
        *)
            error "Cannot create systemd service for $project_type"
            return 1
            ;;
    esac

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create: $service_file"
        info "[DRY RUN] ExecStart: $exec_start"
        return 0
    fi

    # Create service file
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Agent Project: $project_name
After=network.target

[Service]
Type=simple
WorkingDirectory=$project_path
ExecStart=$exec_start
Restart=on-failure
RestartSec=10
User=$USER
Environment=NODE_ENV=$ENVIRONMENT
${PORT:+Environment=PORT=$PORT}

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "$service_name"
    sudo systemctl restart "$service_name"

    sleep 2

    if systemctl is-active "$service_name" &>/dev/null; then
        success "Service $service_name is running"
        create_deployment_record "$project_name" "systemd"
        return 0
    else
        error "Service failed to start"
        sudo systemctl status "$service_name" --no-pager
        return 1
    fi
}

# Deploy with PM2
deploy_pm2() {
    local project_path="$1"
    local project_name="$2"

    info "Deploying with PM2: $project_name"

    if ! command -v pm2 &>/dev/null; then
        info "Installing PM2..."
        npm install -g pm2 || {
            error "Failed to install PM2"
            return 1
        }
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would run: pm2 start npm --name $project_name -- start"
        return 0
    fi

    cd "$project_path" || exit 1

    # Install dependencies if needed
    if [[ -f "package-lock.json" ]] && [[ ! -d "node_modules" ]]; then
        npm install
    fi

    # Stop existing if running
    pm2 delete "$project_name" 2>/dev/null || true

    # Start with PM2
    local pm2_args=(--name "$project_name")
    [[ -n "$PORT" ]] && pm2_args+=(--env "PORT=$PORT")

    if pm2 start npm "${pm2_args[@]}" -- start; then
        pm2 save
        success "PM2 process $project_name started"
        create_deployment_record "$project_name" "pm2"
        return 0
    else
        error "PM2 failed to start"
        return 1
    fi
}

# Rollback deployment
do_rollback() {
    local project_name="$1"
    local record_file="$DEPLOY_DIR/$project_name/previous.json"

    if [[ ! -f "$record_file" ]]; then
        error "No previous deployment found for $project_name"
        return 1
    fi

    local prev_type
    prev_type=$(jq -r '.type' "$record_file")

    info "Rolling back to previous deployment (type: $prev_type)"

    # Swap current and previous
    local current_file="$DEPLOY_DIR/$project_name/current.json"
    mv "$current_file" "$DEPLOY_DIR/$project_name/rollback.json"
    mv "$record_file" "$current_file"

    success "Rollback record updated"
    info "Run deploy again to apply the previous configuration"
}

# Show deployment status
show_status() {
    info "Deployment Status"
    echo "─────────────────────────────────────────"

    if [[ ! -d "$DEPLOY_DIR" ]]; then
        echo "No deployments found"
        return
    fi

    for project_dir in "$DEPLOY_DIR"/*/; do
        [[ -d "$project_dir" ]] || continue
        local project
        project=$(basename "$project_dir")
        local record="$project_dir/current.json"

        if [[ -f "$record" ]]; then
            local type timestamp status
            type=$(jq -r '.type' "$record")
            timestamp=$(jq -r '.timestamp' "$record")
            status=$(jq -r '.status' "$record")

            echo -e "${CYAN}$project${NC}"
            echo "  Type: $type"
            echo "  Status: $status"
            echo "  Deployed: $timestamp"

            # Check if running
            case "$type" in
                local)
                    local pid_file="$project_dir/pid"
                    if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
                        echo -e "  Running: ${GREEN}Yes${NC} (PID: $(cat "$pid_file"))"
                    else
                        echo -e "  Running: ${RED}No${NC}"
                    fi
                    ;;
                docker)
                    if docker ps -f "name=$project" --format '{{.Status}}' | grep -q .; then
                        echo -e "  Running: ${GREEN}Yes${NC}"
                    else
                        echo -e "  Running: ${RED}No${NC}"
                    fi
                    ;;
                systemd)
                    if systemctl is-active "agent-$project" &>/dev/null; then
                        echo -e "  Running: ${GREEN}Yes${NC}"
                    else
                        echo -e "  Running: ${RED}No${NC}"
                    fi
                    ;;
                pm2)
                    if pm2 list 2>/dev/null | grep -q "$project.*online"; then
                        echo -e "  Running: ${GREEN}Yes${NC}"
                    else
                        echo -e "  Running: ${RED}No${NC}"
                    fi
                    ;;
            esac
            echo ""
        fi
    done
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t)
            DEPLOY_TYPE="$2"
            shift 2
            ;;
        -e)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -p)
            PORT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --rollback)
            ROLLBACK=true
            shift
            ;;
        -v)
            VERBOSE=true
            shift
            ;;
        --status)
            show_status
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [[ -z "$PROJECT" ]]; then
                PROJECT="$1"
            else
                TARGET="$1"
            fi
            shift
            ;;
    esac
done

# Ensure deploy directory exists
mkdir -p "$DEPLOY_DIR"

# Validate project
if [[ -z "$PROJECT" ]]; then
    echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         Project Deployer v1.0             ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    usage
    exit 0
fi

# Resolve project path
PROJECT_PATH=""
if [[ -d "$PROJECT" ]]; then
    PROJECT_PATH="$PROJECT"
    PROJECT=$(basename "$PROJECT")
elif [[ -d "$PROJECTS_DIR/$PROJECT" ]]; then
    PROJECT_PATH="$PROJECTS_DIR/$PROJECT"
else
    error "Project not found: $PROJECT"
    info "Available projects:"
    ls -1 "$PROJECTS_DIR" 2>/dev/null | sed 's/^/  /'
    exit 1
fi

# Handle rollback
if [[ "$ROLLBACK" == "true" ]]; then
    do_rollback "$PROJECT"
    exit $?
fi

# Detect types
PROJECT_TYPE=$(detect_project_type "$PROJECT_PATH")
log "Detected project type: $PROJECT_TYPE"

if [[ -z "$DEPLOY_TYPE" ]]; then
    DEPLOY_TYPE=$(detect_deploy_type "$PROJECT_TYPE")
fi
log "Using deployment type: $DEPLOY_TYPE"

# Show info
echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Project Deployer v1.0             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
echo ""
echo -e "Project:     ${CYAN}$PROJECT${NC}"
echo -e "Path:        $PROJECT_PATH"
echo -e "Type:        $PROJECT_TYPE"
echo -e "Deploy:      $DEPLOY_TYPE"
echo -e "Environment: $ENVIRONMENT"
[[ -n "$PORT" ]] && echo -e "Port:        $PORT"
[[ "$DRY_RUN" == "true" ]] && echo -e "${YELLOW}Mode:        DRY RUN${NC}"
echo ""

# Execute deployment
case "$DEPLOY_TYPE" in
    local)
        deploy_local "$PROJECT_PATH" "$PROJECT" "$PROJECT_TYPE"
        ;;
    docker)
        deploy_docker "$PROJECT_PATH" "$PROJECT"
        ;;
    systemd)
        deploy_systemd "$PROJECT_PATH" "$PROJECT" "$PROJECT_TYPE"
        ;;
    pm2)
        deploy_pm2 "$PROJECT_PATH" "$PROJECT"
        ;;
    *)
        error "Unknown deployment type: $DEPLOY_TYPE"
        exit 1
        ;;
esac

exit $?

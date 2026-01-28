#!/bin/bash
# Clawdbot Setup Script
# Sets up Clawdbot with Claude Code subscription authentication in a VM/Docker environment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWDBOT_DIR="${CLAWDBOT_DIR:-$HOME/clawdbot}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[clawdbot-setup]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; }

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    local missing=()
    
    # Check Docker
    if ! command -v docker &>/dev/null; then
        missing+=("docker")
    fi
    
    # Check docker compose
    if ! docker compose version &>/dev/null; then
        missing+=("docker-compose-plugin")
    fi
    
    # Check Claude Code CLI
    if ! command -v claude &>/dev/null; then
        missing+=("claude-code-cli")
    fi
    
    # Check git
    if ! command -v git &>/dev/null; then
        missing+=("git")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing prerequisites: ${missing[*]}"
        echo ""
        echo "Install missing components:"
        for item in "${missing[@]}"; do
            case "$item" in
                docker)
                    echo "  Docker: https://docs.docker.com/engine/install/"
                    ;;
                docker-compose-plugin)
                    echo "  Docker Compose: sudo apt-get install docker-compose-plugin"
                    ;;
                claude-code-cli)
                    echo "  Claude Code: npm install -g @anthropic-ai/claude-code && claude"
                    ;;
                git)
                    echo "  Git: sudo apt-get install git"
                    ;;
            esac
        done
        exit 1
    fi
    
    # Check Claude Code authentication
    if [ ! -d "$HOME/.claude" ]; then
        warn "Claude Code not authenticated. Run 'claude' first to authenticate."
        exit 1
    fi
    
    success "All prerequisites met"
}

# Install Docker (Ubuntu/Debian)
install_docker() {
    log "Installing Docker..."
    
    if command -v docker &>/dev/null; then
        success "Docker already installed"
        return 0
    fi
    
    # Install prerequisites
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    
    # Add Docker GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add user to docker group
    sudo usermod -aG docker "$USER"
    
    success "Docker installed. Please log out and back in for group changes to take effect."
}

# Clone and build Clawdbot
setup_clawdbot() {
    log "Setting up Clawdbot at $CLAWDBOT_DIR..."
    
    mkdir -p "$(dirname "$CLAWDBOT_DIR")"
    
    if [ -d "$CLAWDBOT_DIR/clawdbot" ]; then
        warn "Clawdbot already cloned, pulling latest..."
        cd "$CLAWDBOT_DIR/clawdbot"
        git pull
    else
        mkdir -p "$CLAWDBOT_DIR"
        cd "$CLAWDBOT_DIR"
        git clone https://github.com/clawdbot/clawdbot.git
        cd clawdbot
    fi
    
    # Run initial setup
    log "Running Clawdbot docker setup..."
    ./docker-setup.sh
    
    success "Clawdbot base setup complete"
}

# Create custom Dockerfile with Claude Code
create_custom_dockerfile() {
    log "Creating custom Dockerfile with Claude Code CLI..."
    
    cd "$CLAWDBOT_DIR/clawdbot"
    
    cat > Dockerfile.claude << 'EOF'
FROM clawdbot:local

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Create volume mount point for Claude credentials
VOLUME /home/node/.claude

# Ensure proper permissions
RUN chown -R node:node /home/node
EOF
    
    # Build custom image
    log "Building custom image with Claude Code..."
    docker build -t clawdbot-claude -f Dockerfile.claude .
    
    success "Custom Docker image built: clawdbot-claude"
}

# Create docker-compose override
create_compose_override() {
    log "Creating docker-compose override for Claude Code auth..."
    
    cd "$CLAWDBOT_DIR/clawdbot"
    
    cat > docker-compose.claude.yml << EOF
# Docker Compose override for Claude Code authentication
# Mounts ~/.claude for subscription-based auth

services:
  clawdbot-gateway:
    image: clawdbot-claude
    environment:
      HOME: /home/node
    volumes:
      - ~/.claude:/home/node/.claude:ro
      
  clawdbot-cli:
    image: clawdbot-claude
    environment:
      HOME: /home/node
    volumes:
      - ~/.claude:/home/node/.claude:ro
EOF
    
    success "Docker Compose override created"
}

# Configure Clawdbot for LAN access
configure_clawdbot() {
    log "Configuring Clawdbot..."
    
    local config_file="$HOME/.clawdbot/clawdbot.json"
    
    if [ ! -f "$config_file" ]; then
        warn "Config file not found at $config_file"
        warn "Run Clawdbot once to generate initial config"
        return
    fi
    
    # Backup original
    cp "$config_file" "${config_file}.backup"
    
    # Update gateway bind to lan (allows network access)
    if command -v jq &>/dev/null; then
        jq '.gateway.bind = "lan" | .gateway.controlUi.allowInsecureAuth = true' "$config_file" > "${config_file}.tmp"
        mv "${config_file}.tmp" "$config_file"
        success "Gateway configured for LAN access"
    else
        warn "jq not installed - please manually edit $config_file:"
        echo '  Change "bind": "loopback" to "bind": "lan"'
        echo '  Add "controlUi": { "allowInsecureAuth": true } under "gateway"'
    fi
}

# Print startup instructions
print_instructions() {
    echo ""
    echo "=================================================="
    echo "   Clawdbot Setup Complete!"
    echo "=================================================="
    echo ""
    echo "To start Clawdbot with Claude Code authentication:"
    echo ""
    echo "  cd $CLAWDBOT_DIR/clawdbot"
    echo "  docker compose -f docker-compose.yml -f docker-compose.claude.yml up -d clawdbot-gateway"
    echo ""
    echo "To test the agent:"
    echo ""
    echo "  docker compose -f docker-compose.yml -f docker-compose.claude.yml run -it --rm clawdbot-cli agent --local --session-id test -m 'Hello!'"
    echo ""
    echo "Dashboard access:"
    echo ""
    echo "  1. Get your token: grep CLAWDBOT_GATEWAY_TOKEN $CLAWDBOT_DIR/clawdbot/.env"
    echo "  2. Open: http://$(hostname -I | awk '{print $1}'):18789/?token=YOUR_TOKEN"
    echo ""
    echo "For messaging platform setup, see:"
    echo "  https://docs.clawd.bot/channels/"
    echo ""
}

# Main
main() {
    echo ""
    echo "=========================================="
    echo "   Clawdbot + Claude Code Setup"
    echo "=========================================="
    echo ""
    
    case "${1:-full}" in
        --check)
            check_prerequisites
            ;;
        --docker)
            install_docker
            ;;
        --setup)
            check_prerequisites
            setup_clawdbot
            create_custom_dockerfile
            create_compose_override
            configure_clawdbot
            print_instructions
            ;;
        full|--full)
            check_prerequisites
            setup_clawdbot
            create_custom_dockerfile
            create_compose_override
            configure_clawdbot
            print_instructions
            ;;
        *)
            echo "Usage: $0 [--check|--docker|--setup|--full]"
            echo ""
            echo "  --check   Check prerequisites only"
            echo "  --docker  Install Docker (Ubuntu/Debian)"
            echo "  --setup   Setup Clawdbot (assumes Docker installed)"
            echo "  --full    Full setup (default)"
            ;;
    esac
}

main "$@"

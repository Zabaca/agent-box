#!/bin/bash
# Agent Loop Setup Script
# Run this inside the VM after copying the template

set -euo pipefail

WORKSPACE="/agent-workspace"
CLAUDE_DIR="$WORKSPACE/.claude"

echo "=== Agent Loop Setup ==="
echo ""

# Check we're in the right place
if [ ! -d "$CLAUDE_DIR" ]; then
    echo "ERROR: $CLAUDE_DIR not found"
    echo "Make sure you've copied the template to /agent-workspace/.claude/"
    exit 1
fi

# 1. Make scripts executable
echo "[1/7] Making scripts executable..."
chmod +x "$CLAUDE_DIR/scripts/"*.sh 2>/dev/null || true
chmod +x "$CLAUDE_DIR/hooks/"*.sh 2>/dev/null || true
echo "  Done"

# 2. Create necessary directories
echo "[2/7] Creating directories..."
mkdir -p "$CLAUDE_DIR/logs"
mkdir -p "$CLAUDE_DIR/inbox/processed"
mkdir -p "$CLAUDE_DIR/inbox/processed-emails"
mkdir -p "$CLAUDE_DIR/notifications"
mkdir -p "$CLAUDE_DIR/checkpoints"
mkdir -p "$CLAUDE_DIR/help-requests"
echo "  Done"

# 3. Initialize state files
echo "[3/7] Initializing state files..."
echo '{"iteration": 0, "updated_at": "'$(date -Iseconds)'"}' > "$CLAUDE_DIR/loop/state.json"
echo '{"last_checked": null, "processed_ids": []}' > "$CLAUDE_DIR/loop/email-inbox-state.json"
echo "  Done"

# 4. Setup config files from templates
echo "[4/7] Setting up config files..."
if [ ! -f "$CLAUDE_DIR/config/email-inbox.json" ]; then
    if [ -f "$CLAUDE_DIR/config/email-inbox.json.template" ]; then
        cp "$CLAUDE_DIR/config/email-inbox.json.template" "$CLAUDE_DIR/config/email-inbox.json"
        echo "  Created email-inbox.json (edit with your settings)"
    fi
fi
if [ ! -f "$CLAUDE_DIR/config/email-notify.json" ]; then
    if [ -f "$CLAUDE_DIR/config/email-notify.json.template" ]; then
        cp "$CLAUDE_DIR/config/email-notify.json.template" "$CLAUDE_DIR/config/email-notify.json"
        echo "  Created email-notify.json (edit with your settings)"
    fi
fi
echo "  Done"

# 5. Setup git (if not already)
echo "[5/7] Setting up git..."
cd "$WORKSPACE"
if [ ! -d ".git" ]; then
    git init
    git config user.name "Claude Agent"
    git config user.email "claude@agent-workspace"
    echo "  Git initialized"
else
    echo "  Git already initialized"
fi

# 6. Configure Claude Code settings
echo "[6/7] Configuring Claude Code..."
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
if [ ! -f "$CLAUDE_SETTINGS" ]; then
    cat > "$CLAUDE_SETTINGS" << 'EOF'
{
  "hooks": {
    "stop": [
      {
        "command": "/agent-workspace/.claude/hooks/stop-hook.sh"
      }
    ]
  }
}
EOF
    echo "  Created Claude settings with stop hook"
else
    echo "  Claude settings already exist (manually add stop hook if needed)"
fi

# 7. Install systemd timer (optional)
echo "[7/7] Systemd setup..."
if command -v systemctl &> /dev/null; then
    echo "  To enable systemd timer, run:"
    echo "    sudo cp $CLAUDE_DIR/services/claude-agent.service /etc/systemd/system/"
    echo "    sudo cp $CLAUDE_DIR/services/claude-agent.timer /etc/systemd/system/"
    echo "    sudo systemctl daemon-reload"
    echo "    sudo systemctl enable --now claude-agent.timer"
else
    echo "  Systemd not available, use cron instead:"
    echo "    */5 * * * * $CLAUDE_DIR/scripts/heartbeat.sh"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Edit $CLAUDE_DIR/config/email-inbox.json with your AgentMail inbox"
echo "2. Edit $CLAUDE_DIR/config/email-notify.json with your email"
echo "3. Add your AgentMail API key to $CLAUDE_DIR/credentials/agentmail-api-key.txt"
echo "4. Edit $CLAUDE_DIR/loop/memory.md with your agent's identity"
echo "5. Start the agent: cd $WORKSPACE && claude --dangerously-skip-permissions"
echo ""

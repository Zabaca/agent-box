#!/bin/bash

# Install systemd service and timer for Claude Agent
# Run with sudo

set -euo pipefail

WORKSPACE="/agent-workspace"
SERVICE_DIR="$WORKSPACE/.claude/services"

echo "Installing Claude Agent systemd service..."

# Copy service and timer files
sudo cp "$SERVICE_DIR/claude-agent.service" /etc/systemd/system/
sudo cp "$SERVICE_DIR/claude-agent.timer" /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable and start the timer
sudo systemctl enable claude-agent.timer
sudo systemctl start claude-agent.timer

# Check status
echo ""
echo "Timer status:"
systemctl status claude-agent.timer --no-pager || true

echo ""
echo "Next scheduled runs:"
systemctl list-timers claude-agent.timer --no-pager || true

echo ""
echo "Installation complete!"
echo "The heartbeat will now run every 5 minutes via systemd timer."
echo "To check logs: journalctl -u claude-agent.service"

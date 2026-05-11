#!/bin/bash
# Start Clawdbot with Claude Code authentication

CLAWDBOT_DIR="${CLAWDBOT_DIR:-$HOME/clawdbot/clawdbot}"

cd "$CLAWDBOT_DIR" || { echo "Clawdbot not found at $CLAWDBOT_DIR"; exit 1; }

docker compose -f docker-compose.yml -f docker-compose.claude.yml up -d clawdbot-gateway

echo "Clawdbot started. Dashboard: http://$(hostname -I | awk '{print $1}'):18789/"
echo "Get token: grep CLAWDBOT_GATEWAY_TOKEN .env"

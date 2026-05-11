#!/bin/bash
# Stop Clawdbot

CLAWDBOT_DIR="${CLAWDBOT_DIR:-$HOME/clawdbot/clawdbot}"

cd "$CLAWDBOT_DIR" || { echo "Clawdbot not found at $CLAWDBOT_DIR"; exit 1; }

docker compose -f docker-compose.yml -f docker-compose.claude.yml down

echo "Clawdbot stopped."

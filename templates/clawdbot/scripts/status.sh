#!/bin/bash
# Check Clawdbot status

CLAWDBOT_DIR="${CLAWDBOT_DIR:-$HOME/clawdbot/clawdbot}"

cd "$CLAWDBOT_DIR" || { echo "Clawdbot not found at $CLAWDBOT_DIR"; exit 1; }

echo "=== Clawdbot Status ==="
docker compose -f docker-compose.yml -f docker-compose.claude.yml ps

echo ""
echo "=== Gateway Health ==="
curl -s http://localhost:18789/health 2>/dev/null || echo "Gateway not responding"

echo ""
echo "=== Dashboard URL ==="
TOKEN=$(grep CLAWDBOT_GATEWAY_TOKEN .env 2>/dev/null | cut -d= -f2)
if [ -n "$TOKEN" ]; then
    echo "http://$(hostname -I | awk '{print $1}'):18789/?token=$TOKEN"
else
    echo "Token not found in .env"
fi

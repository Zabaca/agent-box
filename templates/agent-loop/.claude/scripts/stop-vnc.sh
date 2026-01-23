#!/bin/bash
# Stop VNC server and related processes
LOG_DIR="/agent-workspace/.claude/browser"

echo "Stopping VNC services..."
pkill -f "x11vnc" 2>/dev/null && echo "Stopped x11vnc" || true
pkill -f "fluxbox" 2>/dev/null && echo "Stopped fluxbox" || true
pkill -f "Xvfb :99" 2>/dev/null && echo "Stopped Xvfb" || true

rm -f "$LOG_DIR"/*.pid 2>/dev/null
echo "VNC stopped"

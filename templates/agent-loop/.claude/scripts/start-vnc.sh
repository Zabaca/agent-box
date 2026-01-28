#!/bin/bash
# Start VNC server for browser access
# Usage: start-vnc.sh [port]

set -euo pipefail

VNC_PORT="${1:-5900}"
DISPLAY_NUM=":99"
RESOLUTION="1280x1024x24"
LOG_DIR="/agent-workspace/.claude/browser"
PASSWORD_FILE="$LOG_DIR/.vnc_password"

# Create password file if not exists (default: "agent")
if [ ! -f "$PASSWORD_FILE" ]; then
    echo "agent" > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
fi

# Kill existing instances
pkill -f "Xvfb $DISPLAY_NUM" 2>/dev/null || true
pkill -f "x11vnc.*$DISPLAY_NUM" 2>/dev/null || true
pkill -f "fluxbox" 2>/dev/null || true
sleep 1

# Start virtual display
echo "Starting Xvfb on $DISPLAY_NUM..."
Xvfb $DISPLAY_NUM -screen 0 $RESOLUTION &
XVFB_PID=$!
echo $XVFB_PID > "$LOG_DIR/xvfb.pid"
sleep 2

# Verify Xvfb is running
if ! ps -p $XVFB_PID > /dev/null 2>&1; then
    echo "ERROR: Xvfb failed to start"
    exit 1
fi

export DISPLAY=$DISPLAY_NUM

# Start window manager
echo "Starting fluxbox..."
fluxbox &> "$LOG_DIR/fluxbox.log" &
FLUXBOX_PID=$!
echo $FLUXBOX_PID > "$LOG_DIR/fluxbox.pid"
sleep 1

# Start VNC server
echo "Starting x11vnc on port $VNC_PORT..."
x11vnc -display $DISPLAY_NUM \
    -forever \
    -shared \
    -rfbport $VNC_PORT \
    -passwd "$(cat $PASSWORD_FILE)" \
    -bg \
    -o "$LOG_DIR/x11vnc.log"

echo ""
echo "=========================================="
echo "VNC Server Ready"
echo "=========================================="
echo "Connect with: vnc://$(hostname -I | awk '{print $1}'):$VNC_PORT"
echo "Password: $(cat $PASSWORD_FILE)"
echo "DISPLAY=$DISPLAY_NUM"
echo ""
echo "To use browser, set: export DISPLAY=$DISPLAY_NUM"
echo "=========================================="

# Save connection info
cat > "$LOG_DIR/vnc-info.txt" << INFO
VNC Server Info
===============
Host: $(hostname -I | awk '{print $1}')
Port: $VNC_PORT
Password: $(cat $PASSWORD_FILE)
Display: $DISPLAY_NUM

Connect with any VNC viewer:
- macOS: Open Finder, Cmd+K, vnc://IP:$VNC_PORT
- Or use any VNC client
INFO

echo "Info saved to: $LOG_DIR/vnc-info.txt"

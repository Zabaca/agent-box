#!/bin/bash

# Generate Status Dashboard
# Creates an HTML dashboard showing agent status, health, and recent activity

set -euo pipefail

WORKSPACE="/agent-workspace"
OUTPUT_FILE="$WORKSPACE/.claude/dashboard.html"
TASKS_FILE="$WORKSPACE/.claude/loop/tasks.md"
MEMORY_FILE="$WORKSPACE/.claude/loop/memory.md"
HEALTH_JSON="$WORKSPACE/.claude/loop/health.json"
HEARTBEAT_LOG="$WORKSPACE/.claude/loop/heartbeat.log"
LEARNINGS_FILE="$WORKSPACE/.claude/learnings.md"

# Get current timestamp
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Count tasks
PENDING=$(grep -c '^\- \[ \]' "$TASKS_FILE" 2>/dev/null) || PENDING=0
IN_PROGRESS=$(grep -c '^\- \[\.\]' "$TASKS_FILE" 2>/dev/null) || IN_PROGRESS=0
COMPLETED=$(grep -c '^\- \[x\]' "$TASKS_FILE" 2>/dev/null) || COMPLETED=0

# Get system status
if [ -f "$HEALTH_JSON" ]; then
  HEALTH_STATUS=$(jq -r '.status // "unknown"' "$HEALTH_JSON" 2>/dev/null) || HEALTH_STATUS="unknown"
  HEALTH_TIME=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$HEALTH_JSON" 2>/dev/null || stat --printf='%y' "$HEALTH_JSON" 2>/dev/null | cut -d. -f1) || HEALTH_TIME="unknown"
else
  HEALTH_STATUS="no data"
  HEALTH_TIME="never"
fi

# Get disk usage
DISK_USAGE=$(df -h "$WORKSPACE" | awk 'NR==2 {print $5}')
DISK_FREE=$(df -h "$WORKSPACE" | awk 'NR==2 {print $4}')

# Get recent heartbeat log (last 10 lines)
RECENT_HEARTBEAT=""
if [ -f "$HEARTBEAT_LOG" ]; then
  RECENT_HEARTBEAT=$(tail -10 "$HEARTBEAT_LOG" 2>/dev/null | sed 's/</\&lt;/g; s/>/\&gt;/g') || RECENT_HEARTBEAT="Error reading log"
fi

# Get recent completed tasks (last 5)
RECENT_COMPLETED=""
if [ -f "$TASKS_FILE" ]; then
  RECENT_COMPLETED=$(grep '^\- \[x\]' "$TASKS_FILE" 2>/dev/null | tail -5 | sed 's/^\- \[x\] //; s/</\&lt;/g; s/>/\&gt;/g') || RECENT_COMPLETED=""
fi

# Count learnings
LEARNINGS_COUNT=0
if [ -f "$LEARNINGS_FILE" ]; then
  LEARNINGS_COUNT=$(grep -c '^## ' "$LEARNINGS_FILE" 2>/dev/null) || LEARNINGS_COUNT=0
fi

# Get uptime
UPTIME=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')

# Check if claude is running
CLAUDE_RUNNING="No"
LOCK_FILE="$WORKSPACE/.claude/loop/claude.lock"
if [ -f "$LOCK_FILE" ]; then
  PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    CLAUDE_RUNNING="Yes (PID $PID)"
  fi
fi

# Git status
GIT_COMMITS=$(cd "$WORKSPACE" && git rev-list --count HEAD 2>/dev/null) || GIT_COMMITS="0"
GIT_LAST_COMMIT=$(cd "$WORKSPACE" && git log -1 --format='%s' 2>/dev/null) || GIT_LAST_COMMIT="none"
GIT_UNCOMMITTED=$(cd "$WORKSPACE" && git status --porcelain 2>/dev/null | wc -l) || GIT_UNCOMMITTED="0"

# Determine health badge color
case "$HEALTH_STATUS" in
  "healthy") HEALTH_COLOR="#4caf50" ;;
  "degraded") HEALTH_COLOR="#ff9800" ;;
  "critical") HEALTH_COLOR="#f44336" ;;
  *) HEALTH_COLOR="#9e9e9e" ;;
esac

# Generate HTML
cat > "$OUTPUT_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Claude Agent Dashboard</title>
  <meta http-equiv="refresh" content="60">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #1a1a2e;
      color: #eee;
      padding: 20px;
      min-height: 100vh;
    }
    .container { max-width: 1200px; margin: 0 auto; }
    h1 { color: #00d4ff; margin-bottom: 20px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
    .card {
      background: #16213e;
      border-radius: 12px;
      padding: 20px;
      box-shadow: 0 4px 6px rgba(0,0,0,0.3);
    }
    .card h2 {
      color: #00d4ff;
      font-size: 1.1rem;
      margin-bottom: 15px;
      border-bottom: 1px solid #333;
      padding-bottom: 10px;
    }
    .stat { display: flex; justify-content: space-between; margin: 8px 0; }
    .stat-label { color: #888; }
    .stat-value { font-weight: bold; }
    .badge {
      display: inline-block;
      padding: 4px 12px;
      border-radius: 20px;
      font-size: 0.85rem;
      font-weight: bold;
    }
    .progress-bar {
      height: 8px;
      background: #333;
      border-radius: 4px;
      overflow: hidden;
      margin-top: 5px;
    }
    .progress-fill {
      height: 100%;
      background: linear-gradient(90deg, #00d4ff, #00ff88);
      transition: width 0.3s;
    }
    .log-box {
      background: #0f0f1a;
      border-radius: 8px;
      padding: 12px;
      font-family: 'Monaco', 'Menlo', monospace;
      font-size: 0.8rem;
      max-height: 200px;
      overflow-y: auto;
      white-space: pre-wrap;
      word-break: break-all;
    }
    .task-list { list-style: none; }
    .task-list li {
      padding: 8px 0;
      border-bottom: 1px solid #333;
      font-size: 0.9rem;
    }
    .task-list li:last-child { border-bottom: none; }
    .timestamp {
      color: #666;
      font-size: 0.85rem;
      text-align: right;
      margin-top: 20px;
    }
    .running { animation: pulse 2s infinite; }
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.5; }
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>🤖 Claude Agent Dashboard</h1>

    <div class="grid">
      <div class="card">
        <h2>System Status</h2>
        <div class="stat">
          <span class="stat-label">Health</span>
          <span class="badge" style="background: ${HEALTH_COLOR}; color: white;">${HEALTH_STATUS}</span>
        </div>
        <div class="stat">
          <span class="stat-label">Claude Running</span>
          <span class="stat-value ${CLAUDE_RUNNING:0:3}">${CLAUDE_RUNNING}</span>
        </div>
        <div class="stat">
          <span class="stat-label">System Uptime</span>
          <span class="stat-value">${UPTIME}</span>
        </div>
        <div class="stat">
          <span class="stat-label">Last Health Check</span>
          <span class="stat-value">${HEALTH_TIME}</span>
        </div>
      </div>

      <div class="card">
        <h2>Task Queue</h2>
        <div class="stat">
          <span class="stat-label">Pending</span>
          <span class="stat-value" style="color: #ff9800;">${PENDING}</span>
        </div>
        <div class="stat">
          <span class="stat-label">In Progress</span>
          <span class="stat-value" style="color: #00d4ff;">${IN_PROGRESS}</span>
        </div>
        <div class="stat">
          <span class="stat-label">Completed</span>
          <span class="stat-value" style="color: #4caf50;">${COMPLETED}</span>
        </div>
        <div class="progress-bar">
          <div class="progress-fill" style="width: $(( COMPLETED * 100 / (PENDING + IN_PROGRESS + COMPLETED + 1) ))%;"></div>
        </div>
      </div>

      <div class="card">
        <h2>Storage & Git</h2>
        <div class="stat">
          <span class="stat-label">Disk Usage</span>
          <span class="stat-value">${DISK_USAGE}</span>
        </div>
        <div class="stat">
          <span class="stat-label">Free Space</span>
          <span class="stat-value">${DISK_FREE}</span>
        </div>
        <div class="stat">
          <span class="stat-label">Git Commits</span>
          <span class="stat-value">${GIT_COMMITS}</span>
        </div>
        <div class="stat">
          <span class="stat-label">Uncommitted Changes</span>
          <span class="stat-value">${GIT_UNCOMMITTED}</span>
        </div>
      </div>

      <div class="card">
        <h2>Growth</h2>
        <div class="stat">
          <span class="stat-label">Learnings Recorded</span>
          <span class="stat-value">${LEARNINGS_COUNT}</span>
        </div>
        <div class="stat">
          <span class="stat-label">Last Git Commit</span>
          <span class="stat-value" style="font-size: 0.8rem;">${GIT_LAST_COMMIT:0:40}</span>
        </div>
      </div>

      <div class="card" style="grid-column: span 2;">
        <h2>Recent Activity (Heartbeat Log)</h2>
        <div class="log-box">${RECENT_HEARTBEAT:-No recent activity}</div>
      </div>

      <div class="card">
        <h2>Recently Completed</h2>
        <ul class="task-list">
EOF

# Add completed tasks to HTML
if [ -n "$RECENT_COMPLETED" ]; then
  echo "$RECENT_COMPLETED" | while read -r task; do
    echo "          <li>✓ $task</li>" >> "$OUTPUT_FILE"
  done
else
  echo "          <li>No completed tasks yet</li>" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" <<EOF
        </ul>
      </div>
    </div>

    <p class="timestamp">Last updated: ${TIMESTAMP} | Auto-refreshes every 60 seconds</p>
  </div>
</body>
</html>
EOF

echo "Dashboard generated at $OUTPUT_FILE"

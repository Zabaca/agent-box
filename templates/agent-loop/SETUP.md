# Agent Loop Setup Guide

This template provides a self-sustaining autonomous agent loop infrastructure.

## Prerequisites

- Lima VM running (see main README)
- VM mounted at `~/vm-workspace`
- Claude Code CLI installed in VM

## Quick Start

### 1. Copy Template to VM

From your Mac:
```bash
# Copy the entire template to the mounted workspace
cp -r templates/agent-loop/.claude ~/vm-workspace/
```

### 2. Create AgentMail Inbox

1. Go to [agentmail.to](https://agentmail.to)
2. Create a new inbox (e.g., `my-agent@agentmail.to`)
3. Copy the API key

### 3. Run Setup Script

SSH into the VM:
```bash
./vm.sh ssh
```

Run the setup:
```bash
cd /agent-workspace
chmod +x .claude/templates/setup.sh  # if needed
./setup.sh
```

### 4. Configure Email

Edit the config files:

```bash
# Inbound tasks (who can send you tasks)
nano /agent-workspace/.claude/config/email-inbox.json
```
```json
{
  "inbox_id": "my-agent@agentmail.to",
  "allowed_senders": ["your-email@example.com"],
  ...
}
```

```bash
# Outbound notifications (where to send alerts)
nano /agent-workspace/.claude/config/email-notify.json
```
```json
{
  "recipient": "your-email@example.com",
  ...
}
```

### 5. Add API Key

```bash
echo "am_YOUR_API_KEY" > /agent-workspace/.claude/credentials/agentmail-api-key.txt
chmod 600 /agent-workspace/.claude/credentials/agentmail-api-key.txt
```

### 6. Customize Agent Identity

Edit the memory file:
```bash
nano /agent-workspace/.claude/loop/memory.md
```

Update:
- Agent name and purpose
- Initial goals
- Your contact info

### 7. Start the Agent

```bash
cd /agent-workspace
claude --dangerously-skip-permissions
```

Or use the `yolo` alias:
```bash
yolo
```

## Enable Auto-Restart (Optional)

### Option A: Systemd Timer

```bash
sudo cp /agent-workspace/.claude/services/claude-agent.service /etc/systemd/system/
sudo cp /agent-workspace/.claude/services/claude-agent.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now claude-agent.timer
```

### Option B: Cron

```bash
crontab -e
# Add:
*/5 * * * * /agent-workspace/.claude/scripts/heartbeat.sh
```

## Verify Setup

### Check Loop Status
```bash
cat /agent-workspace/.claude/loop/state.json
```

### Check Tasks
```bash
cat /agent-workspace/.claude/loop/tasks.md
```

### Test Email

Send a test task:
```
To: my-agent@agentmail.to
Subject: Test task - respond with hello
```

Then trigger inbox check:
```bash
/agent-workspace/.claude/scripts/email-inbox.sh check
```

### View Logs
```bash
tail -f /agent-workspace/.claude/loop/heartbeat.log
```

## Directory Structure

```
/agent-workspace/.claude/
├── config/                 # Configuration files
│   ├── email-inbox.json    # Inbound email settings
│   └── email-notify.json   # Outbound notification settings
├── credentials/            # API keys (not in git)
│   └── agentmail-api-key.txt
├── hooks/                  # Claude Code hooks
│   └── stop-hook.sh        # Loop controller
├── inbox/                  # File-based task inbox
├── loop/                   # Core loop state
│   ├── tasks.md            # Task queue
│   ├── memory.md           # Persistent context
│   ├── goals.md            # Standing goals
│   └── stop-rules.md       # Autonomy rules
├── scripts/                # 50+ utility scripts
└── services/               # Systemd units
```

## Communication Methods

### Send Tasks to Agent

**Via Email (recommended):**
```
To: my-agent@agentmail.to
Subject: Build a REST API for users
Body: Use Express.js with MongoDB...
```

**Via File:**
```bash
echo "Build a REST API" > ~/vm-workspace/.claude/inbox/task.txt
```

### Receive Notifications

Agent sends email for `critical` and `error` events by default.

Configure levels in `email-notify.json`:
```json
{
  "levels": {
    "critical": { "email": true, "file": true },
    "error": { "email": true, "file": true },
    "success": { "email": true, "file": true }  // enable this
  }
}
```

## Stopping the Agent

### Graceful Stop
```bash
touch /agent-workspace/.claude/loop/stop-signal
```

### View Status
```bash
cat /agent-workspace/.claude/loop/state.json
```

## Troubleshooting

### Agent Not Starting

Check lock file:
```bash
cat /agent-workspace/.claude/loop/claude.lock
# If stale, remove it:
rm /agent-workspace/.claude/loop/claude.lock
```

### Email Not Working

Test the connection:
```bash
/agent-workspace/.claude/scripts/email-notify.sh test
```

Check API key:
```bash
cat /agent-workspace/.claude/credentials/agentmail-api-key.txt
```

### Max Iterations Reached

Reset the counter:
```bash
echo '{"iteration": 0}' > /agent-workspace/.claude/loop/state.json
```

## Customization

### Add Standing Goals

Edit `/agent-workspace/.claude/loop/goals.md` to define what the agent works on when the task queue is empty.

### Modify Stop Rules

Edit `/agent-workspace/.claude/loop/stop-rules.md` to change when the agent should/shouldn't stop.

### Add New Scripts

Place scripts in `/agent-workspace/.claude/scripts/` and make them executable.

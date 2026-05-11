# Clawdbot Setup Guide

This template helps you set up [Clawdbot](https://clawd.bot/) with Claude Code subscription authentication in a VM or Docker environment.

## What is Clawdbot?

Clawdbot is a personal AI assistant that:
- Runs on your own devices (VM, server, Docker)
- Connects to messaging platforms (WhatsApp, Telegram, Slack, Discord, etc.)
- Uses Claude Code subscription auth (no separate API key needed!)
- Leverages `claude setup-token` for authentication

## Prerequisites

- **Linux VM** (Ubuntu 22.04+ recommended)
- **Docker** with Docker Compose v2
- **Claude Code CLI** authenticated with your subscription
- **Node.js 18+** (for Claude Code CLI)

## Quick Start

```bash
# 1. Ensure Claude Code is authenticated
claude

# 2. Run setup
./setup.sh
```

## Manual Setup Steps

### 1. Install Docker (if needed)

```bash
./setup.sh --docker
```

Or manually:
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
# Log out and back in
```

### 2. Install Claude Code CLI

```bash
npm install -g @anthropic-ai/claude-code
claude  # Follow prompts to authenticate
```

### 3. Clone and Build Clawdbot

```bash
mkdir -p ~/clawdbot && cd ~/clawdbot
git clone https://github.com/clawdbot/clawdbot.git
cd clawdbot
./docker-setup.sh
```

During onboarding, select:
- Security warning: Yes
- Onboarding mode: QuickStart
- Model/auth provider: Skip (we'll use Claude Code)
- Gateway bind: lan
- Gateway auth: token

### 4. Create Custom Dockerfile

Create `Dockerfile.claude`:
```dockerfile
FROM clawdbot:local
RUN npm install -g @anthropic-ai/claude-code
VOLUME /home/node/.claude
```

Build:
```bash
docker build -t clawdbot-claude -f Dockerfile.claude .
```

### 5. Create Docker Compose Override

Create `docker-compose.claude.yml`:
```yaml
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
```

### 6. Configure for Network Access

Edit `~/.clawdbot/clawdbot.json`:
- Change `"bind": "loopback"` to `"bind": "lan"`
- Add `"controlUi": { "allowInsecureAuth": true }` under `"gateway"`

## Running Clawdbot

### Start the Gateway

```bash
cd ~/clawdbot/clawdbot
docker compose -f docker-compose.yml -f docker-compose.claude.yml up -d clawdbot-gateway
```

### Test the Agent

```bash
docker compose -f docker-compose.yml -f docker-compose.claude.yml run -it --rm clawdbot-cli agent --local --session-id test -m "Hello!"
```

### Access Dashboard

1. Get your token:
   ```bash
   grep CLAWDBOT_GATEWAY_TOKEN ~/clawdbot/clawdbot/.env
   ```

2. Open in browser:
   ```
   http://<your-vm-ip>:18789/?token=YOUR_TOKEN
   ```

## Connecting Messaging Platforms

After Clawdbot is running, connect your channels:

- **WhatsApp**: Scan QR code via dashboard
- **Telegram**: Create bot via @BotFather, add token
- **Discord**: Create app, add bot token
- **Slack**: Create app, add OAuth tokens

See [Clawdbot Channel Docs](https://docs.clawd.bot/channels/) for detailed instructions.

## Troubleshooting

### "Claude Code CLI not found"
Ensure npm global bin is in PATH:
```bash
export PATH="$PATH:$(npm config get prefix)/bin"
```

### "Authentication failed"
Re-authenticate Claude Code:
```bash
claude logout
claude
```

### Container can't access credentials
Check the volume mount:
```bash
docker compose -f docker-compose.yml -f docker-compose.claude.yml run --rm clawdbot-cli ls -la /home/node/.claude
```

### Gateway not accessible from network
1. Check firewall: `sudo ufw allow 18789`
2. Verify bind setting in `~/.clawdbot/clawdbot.json`

## Security Notes

- Claude credentials are mounted read-only (`:ro`)
- Gateway token provides access control
- Consider using HTTPS in production
- Keep your VM updated

## Architecture

```
┌─────────────────────────────────────────────────┐
│                    VM/Server                     │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │           Docker Container               │   │
│  │                                          │   │
│  │  ┌────────────┐    ┌──────────────────┐  │   │
│  │  │  Clawdbot  │───→│ Claude Code CLI  │  │   │
│  │  │  Gateway   │    │ (inside container)│  │   │
│  │  └────────────┘    └──────────────────┘  │   │
│  │        │                   │             │   │
│  │        │           ┌──────────────┐      │   │
│  │        │           │ ~/.claude    │      │   │
│  │        │           │ (mounted)    │      │   │
│  │        │           └──────────────┘      │   │
│  └────────│──────────────────│──────────────┘   │
│           │                  │                  │
│           ▼                  ▼                  │
│   ┌───────────────┐   ┌──────────────┐          │
│   │   Dashboard   │   │  Anthropic   │          │
│   │   :18789      │   │  API (OAuth) │          │
│   └───────────────┘   └──────────────┘          │
└─────────────────────────────────────────────────┘
         │
         ▼
  ┌──────────────────┐
  │ Messaging Channels│
  │ WhatsApp/Telegram │
  │ Discord/Slack     │
  └──────────────────┘
```

## Files in This Template

```
templates/clawdbot/
├── setup.sh           # Main setup script
├── SETUP.md           # This documentation
└── scripts/
    ├── start.sh       # Start Clawdbot
    ├── stop.sh        # Stop Clawdbot
    └── status.sh      # Check status
```

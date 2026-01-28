# Credentials

Store API keys and secrets here. Files in this directory should NOT be committed to git.

## Required

### AgentMail API Key
```bash
# Get from https://agentmail.to after creating an inbox
echo "am_YOUR_API_KEY_HERE" > agentmail-api-key.txt
chmod 600 agentmail-api-key.txt
```

## Optional

### GitHub Token (for publishing repos)
```bash
echo "ghp_YOUR_TOKEN" > github-token.txt
chmod 600 github-token.txt
```

### npm Token (for publishing packages)
```bash
echo "npm_YOUR_TOKEN" > npm-token.txt
chmod 600 npm-token.txt
```

### Webhook URLs
```bash
# For Slack/Discord notifications
echo "https://hooks.slack.com/..." > slack-webhook.txt
```

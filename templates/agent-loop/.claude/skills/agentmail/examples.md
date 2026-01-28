# AgentMail Examples

## Environment Setup

```bash
# Store API key
export AGENTMAIL_API_KEY="am_e3e3f0c7cc7e9a50fc04d251886efe54be6fb6cd48b35f9a9a3c9f55d072a1f6"
export AGENTMAIL_INBOX="agent-box@agentmail.to"
```

## Example 1: Check for New Messages

```bash
curl -s -H "Authorization: Bearer $AGENTMAIL_API_KEY" \
  "https://api.agentmail.to/v0/inboxes/$AGENTMAIL_INBOX/messages?limit=5" \
  | jq -r '.messages[] | "\(.timestamp) | \(.from) | \(.subject)"'
```

Output:
```
2026-01-23T15:09:52.000Z | Cloudflare <noreply@notify.cloudflare.com> | [Action required] Verify your email
2026-01-23T07:38:13.000Z | DEV Community <yo@dev.to> | Want to win a GitHub Copilot Pro+...
```

## Example 2: Find Verification Email

```bash
# Get latest Cloudflare verification email
curl -s -H "Authorization: Bearer $AGENTMAIL_API_KEY" \
  "https://api.agentmail.to/v0/inboxes/$AGENTMAIL_INBOX/messages?limit=10" \
  | jq -r '.messages[] | select(.from | contains("cloudflare")) | .preview' \
  | head -1
```

## Example 3: Extract Verification URL

```bash
# Extract URL from preview
curl -s -H "Authorization: Bearer $AGENTMAIL_API_KEY" \
  "https://api.agentmail.to/v0/inboxes/$AGENTMAIL_INBOX/messages?limit=1" \
  | jq -r '.messages[0].preview' \
  | grep -oP 'https://[^\s<>]+'
```

## Example 4: Filter by Sender

```bash
# All emails from GitHub
curl -s -H "Authorization: Bearer $AGENTMAIL_API_KEY" \
  "https://api.agentmail.to/v0/inboxes/$AGENTMAIL_INBOX/messages?limit=50" \
  | jq '.messages[] | select(.from | contains("github"))'
```

## Example 5: Email Verification Workflow

Complete workflow for verifying an account:

```bash
#!/bin/bash
# verify-email.sh - Automated email verification

API_KEY="am_e3e3f0c7cc7e9a50fc04d251886efe54be6fb6cd48b35f9a9a3c9f55d072a1f6"
INBOX="agent-box@agentmail.to"
SERVICE="cloudflare"  # or "github", "npm", etc.

echo "Waiting for verification email from $SERVICE..."

for i in {1..30}; do
  PREVIEW=$(curl -s -H "Authorization: Bearer $API_KEY" \
    "https://api.agentmail.to/v0/inboxes/$INBOX/messages?limit=1" \
    | jq -r '.messages[0] | select(.from | ascii_downcase | contains("'$SERVICE'")) | .preview')

  if [ -n "$PREVIEW" ]; then
    URL=$(echo "$PREVIEW" | grep -oP 'https://[^\s<>]+verify[^\s<>]*')
    if [ -n "$URL" ]; then
      echo "Found verification URL: $URL"
      exit 0
    fi
  fi

  echo "Attempt $i/30 - waiting..."
  sleep 2
done

echo "Timeout - no verification email found"
exit 1
```

## Example 6: Check Unread Count

```bash
curl -s -H "Authorization: Bearer $AGENTMAIL_API_KEY" \
  "https://api.agentmail.to/v0/inboxes/$AGENTMAIL_INBOX/messages" \
  | jq '[.messages[] | select(.labels | contains(["unread"]))] | length'
```

## Example 7: Recent Messages Summary

```bash
# Pretty summary of last 10 messages
curl -s -H "Authorization: Bearer $AGENTMAIL_API_KEY" \
  "https://api.agentmail.to/v0/inboxes/$AGENTMAIL_INBOX/messages?limit=10" \
  | jq -r '.messages[] | "[\(.timestamp | split("T")[0])] \(.subject[0:60])"'
```

## Known Services We Receive From

| Service | From Address Pattern | Subject Pattern |
|---------|---------------------|-----------------|
| GitHub | `noreply@github.com` | "Please verify your email" |
| npm | `support@npmjs.com` | "Please verify your email" |
| Cloudflare | `noreply@notify.cloudflare.com` | "[Action required] Verify" |
| Dev.to | `yo@dev.to` | "confirm your DEV Community account" |
| Hacker News | `hn@ycombinator.com` | Various |

## Troubleshooting

**"Invalid email address" error:**
- Make sure inbox_id is full email: `agent-box@agentmail.to` not just `agent-box`

**Empty response:**
- Check API key is valid
- Verify inbox exists
- Try increasing limit parameter

**SSL errors with curl:**
- Wait a few seconds and retry (certificate propagation)
- Use `-k` flag to skip verification (not recommended for production)

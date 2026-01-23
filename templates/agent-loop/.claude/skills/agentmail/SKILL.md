---
name: agentmail
description: Access AgentMail API for email operations. Use when checking inbox, reading emails, finding verification links, or managing email-based workflows.
argument-hint: "[list|read|search] [inbox-email]"
---

# AgentMail API Skill

AgentMail provides programmatic email access for AI agents. Use this skill when you need to:
- Check inbox for new messages
- Read email content
- Find verification links
- Search for specific emails

## Quick Reference

**API Base:** `https://api.agentmail.to/v0`

**Authentication:**
```bash
Authorization: Bearer $AGENTMAIL_API_KEY
```

**Our Inbox:** `agent-box@agentmail.to`

## Common Operations

### List Messages
```bash
curl -s -H "Authorization: Bearer $AGENTMAIL_API_KEY" \
  "https://api.agentmail.to/v0/inboxes/agent-box@agentmail.to/messages?limit=10" | jq .
```

### Get Single Message
```bash
curl -s -H "Authorization: Bearer $AGENTMAIL_API_KEY" \
  "https://api.agentmail.to/v0/inboxes/{inbox_id}/messages/{message_id}" | jq .
```

### Search by Subject/Sender
```bash
# List messages and filter with jq
curl -s -H "Authorization: Bearer $AGENTMAIL_API_KEY" \
  "https://api.agentmail.to/v0/inboxes/agent-box@agentmail.to/messages?limit=20" \
  | jq '.messages[] | select(.subject | contains("verify"))'
```

## Extract Verification Links

Common pattern for email verification workflows:
```bash
# Get latest email and extract URL
curl -s -H "Authorization: Bearer $AGENTMAIL_API_KEY" \
  "https://api.agentmail.to/v0/inboxes/agent-box@agentmail.to/messages?limit=1" \
  | jq -r '.messages[0].preview' \
  | grep -oP 'https://[^\s<>]+'
```

## Message Response Structure

```json
{
  "messages": [
    {
      "inbox_id": "agent-box@agentmail.to",
      "message_id": "<unique-id>",
      "from": "Sender Name <sender@example.com>",
      "to": ["agent-box@agentmail.to"],
      "subject": "Email Subject",
      "preview": "First ~200 chars of body...",
      "timestamp": "2026-01-23T15:00:00.000Z",
      "labels": ["received", "unread"]
    }
  ],
  "count": 1,
  "limit": 10
}
```

## Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `limit` | int | Max messages to return |
| `page_token` | string | Pagination cursor |
| `labels` | array | Filter by labels |
| `before` | datetime | Messages before timestamp |
| `after` | datetime | Messages after timestamp |
| `ascending` | bool | Sort direction |
| `include_spam` | bool | Include spam messages |

For detailed API reference, see [reference.md](reference.md)
For practical examples, see [examples.md](examples.md)

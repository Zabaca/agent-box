# AgentMail API Reference

## Authentication

All requests require Bearer token authentication:
```
Authorization: Bearer am_xxxxxxxxxxxx
```

**API Key Location:** `/agent-workspace/.claude/credentials/agentmail-api-key.txt`

## Base URL

```
https://api.agentmail.to/v0
```

## Endpoints

### List Inboxes
```
GET /inboxes
```

### List Messages
```
GET /inboxes/{inbox_id}/messages
```

**Path Parameters:**
- `inbox_id` - Full email address (e.g., `agent-box@agentmail.to`)

**Query Parameters:**
- `limit` (int) - Max results, default 50
- `page_token` (string) - For pagination
- `labels` (array) - Filter by labels
- `before` (datetime) - Before timestamp
- `after` (datetime) - After timestamp
- `ascending` (bool) - Sort ascending
- `include_spam` (bool) - Include spam

**Response:**
```json
{
  "count": 8,
  "limit": 20,
  "page_token": null,
  "messages": [
    {
      "organization_id": "uuid",
      "pod_id": "uuid",
      "inbox_id": "agent-box@agentmail.to",
      "thread_id": "uuid",
      "message_id": "<smtp-message-id>",
      "labels": ["received", "unread"],
      "timestamp": "2026-01-23T15:09:52.000Z",
      "from": "Sender <email@example.com>",
      "to": ["agent-box@agentmail.to"],
      "reply_to": ["reply@example.com"],
      "subject": "Email Subject",
      "preview": "First ~200 chars...",
      "headers": {},
      "smtp_id": "string",
      "size": 58976,
      "updated_at": "2026-01-23T15:09:54.407Z",
      "created_at": "2026-01-23T15:09:54.407Z"
    }
  ]
}
```

### Get Single Message
```
GET /inboxes/{inbox_id}/messages/{message_id}
```

Returns full message including body.

### Create Inbox
```
POST /inboxes
```

**Body:**
```json
{
  "domain": "agentmail.to",
  "username": "my-inbox",
  "display_name": "My Agent"
}
```

### Send Message
```
POST /inboxes/{inbox_id}/messages/send
```

**Body:**
```json
{
  "to": "recipient@example.com",
  "subject": "Email subject",
  "text": "Plain text body",
  "html": "<p>HTML body (optional)</p>",
  "cc": ["cc@example.com"],
  "bcc": ["bcc@example.com"],
  "reply_to": "reply@example.com",
  "attachments": [
    {
      "content": "base64-encoded-content",
      "filename": "file.pdf",
      "content_type": "application/pdf"
    }
  ]
}
```

**Response:**
```json
{
  "message_id": "smtp-message-id",
  "thread_id": "uuid"
}
```

## Labels

Messages can have these labels:
- `received` - Incoming message
- `sent` - Outgoing message
- `unread` - Not yet read
- `read` - Has been read
- `starred` - Flagged
- `spam` - Marked as spam

## Error Responses

```json
{
  "name": "ValidationError",
  "errors": [
    {
      "origin": "string",
      "code": "invalid_format",
      "path": ["inbox_id"],
      "message": "Invalid email address"
    }
  ]
}
```

## Rate Limits

- Free tier: 3 inboxes, 3K emails/month
- Real-time WebSocket updates available

## Documentation

- Full docs: https://docs.agentmail.to/api-reference
- SDK: `agentmail-node` (npm)

# Cloudflare Workers CLI Reference

## Wrangler Commands

### Authentication

| Command | Description |
|---------|-------------|
| `wrangler login` | Authenticate with Cloudflare (browser) |
| `wrangler logout` | Remove authentication |
| `wrangler whoami` | Show current account info |

### Deployment

| Command | Description |
|---------|-------------|
| `wrangler deploy` | Deploy worker to production |
| `wrangler deploy --dry-run` | Preview deployment without publishing |
| `wrangler publish` | Alias for deploy |

### Development

| Command | Description |
|---------|-------------|
| `wrangler dev` | Start local development server |
| `wrangler dev --remote` | Dev server using Cloudflare's edge |
| `wrangler tail` | Stream live logs from worker |

### Projects

| Command | Description |
|---------|-------------|
| `wrangler init` | Create new worker project |
| `wrangler deployments list` | List recent deployments |
| `wrangler delete` | Delete a worker |

### Pages (Static Sites)

| Command | Description |
|---------|-------------|
| `wrangler pages project list` | List Pages projects |
| `wrangler pages project create <name>` | Create new Pages project |
| `wrangler pages deploy <dir>` | Deploy directory to Pages |
| `wrangler pages deployment list` | List deployments |

### Secrets & Environment

| Command | Description |
|---------|-------------|
| `wrangler secret put <KEY>` | Add secret (prompts for value) |
| `wrangler secret list` | List all secrets |
| `wrangler secret delete <KEY>` | Remove a secret |

### KV Storage

| Command | Description |
|---------|-------------|
| `wrangler kv:namespace list` | List KV namespaces |
| `wrangler kv:namespace create <NAME>` | Create namespace |
| `wrangler kv:key put <KEY> <VALUE>` | Store key-value |
| `wrangler kv:key get <KEY>` | Retrieve value |

## wrangler.toml Configuration

### Basic Worker

```toml
name = "my-worker"
main = "src/index.ts"
compatibility_date = "2024-01-01"
```

### Static Site (Assets)

```toml
name = "my-site"
main = "src/index.ts"
compatibility_date = "2024-01-01"

[site]
bucket = "./public"
```

### With KV Binding

```toml
name = "my-worker"
main = "src/index.ts"
compatibility_date = "2024-01-01"

[[kv_namespaces]]
binding = "MY_KV"
id = "abc123..."
```

### With Environment Variables

```toml
name = "my-worker"
main = "src/index.ts"
compatibility_date = "2024-01-01"

[vars]
API_URL = "https://api.example.com"
DEBUG = "true"
```

### With Custom Domain

```toml
name = "my-worker"
main = "src/index.ts"
compatibility_date = "2024-01-01"

routes = [
  { pattern = "example.com/*", zone_name = "example.com" }
]
```

## API Reference

### Base URL
```
https://api.cloudflare.com/client/v4/
```

### Authentication Header
```
Authorization: Bearer <API_TOKEN>
```

### List Workers
```bash
curl -X GET "https://api.cloudflare.com/client/v4/accounts/{account_id}/workers/scripts" \
  -H "Authorization: Bearer $CF_API_TOKEN"
```

### Get Worker Script
```bash
curl -X GET "https://api.cloudflare.com/client/v4/accounts/{account_id}/workers/scripts/{script_name}" \
  -H "Authorization: Bearer $CF_API_TOKEN"
```

## Error Codes

| Code | Meaning | Solution |
|------|---------|----------|
| 10034 | Email not verified | Verify email in Cloudflare dashboard |
| 10000 | Authentication error | Re-login with `wrangler login` |
| 10007 | Worker name taken | Choose different name |
| 10021 | Script too large | Reduce bundle size |

## Limits (Free Tier)

- 100,000 requests/day
- 10ms CPU time per request
- 1MB script size
- 25 KV namespaces
- 1GB KV storage

## Useful Links

- Dashboard: https://dash.cloudflare.com/
- Workers Docs: https://developers.cloudflare.com/workers/
- Wrangler Docs: https://developers.cloudflare.com/workers/wrangler/
- Status Page: https://www.cloudflarestatus.com/

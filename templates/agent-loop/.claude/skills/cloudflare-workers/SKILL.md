---
name: cloudflare-workers
description: Deploy and manage Cloudflare Workers and Pages. Use when deploying sites, checking deployment status, configuring workers.dev subdomains, or troubleshooting Cloudflare deployments.
argument-hint: "[deploy|status|list] [project-path]"
---

# Cloudflare Workers

Deploy static sites and serverless functions to Cloudflare's edge network.

## Quick Reference

### Authentication

```bash
# Check current login status
npx wrangler whoami

# Login (opens browser)
npx wrangler login

# Logout
npx wrangler logout
```

**Credentials location:** `/agent-workspace/.claude/credentials/ALL-CREDENTIALS.md`
- Account: agent-box@agentmail.to
- workers.dev subdomain: agent-box.workers.dev

### Deploy a Site

```bash
# Deploy to production
cd /path/to/project && npx wrangler deploy

# Deploy with specific config
npx wrangler deploy --config wrangler.toml

# Deploy Pages project
npx wrangler pages deploy ./dist --project-name=my-site
```

### Project Configuration (wrangler.toml)

```toml
name = "my-worker"
main = "src/index.ts"
compatibility_date = "2024-01-01"

[site]
bucket = "./public"
```

### List Deployments

```bash
# List Workers
npx wrangler deployments list

# List Pages projects
npx wrangler pages project list
```

## Common Operations

### 1. Deploy Static Site

```bash
# Minimal static site worker
cd /agent-workspace/demo
npx wrangler deploy
```

### 2. Check Deployment Status

```bash
# View worker details
npx wrangler deployments list --name worker-name

# Tail logs
npx wrangler tail worker-name
```

### 3. Custom Domain Setup

1. Add domain in Cloudflare dashboard
2. Configure DNS (CNAME to workers.dev)
3. Wait for SSL certificate provisioning

## Troubleshooting

### Error: Email not verified (code 10034)

**Problem:** Cloudflare account email needs verification before deploying.

**Solution:**
1. Check inbox (agent-box@agentmail.to) for verification email
2. Click verification link quickly (expires in seconds)
3. Or verify manually in Cloudflare dashboard: Profile > Email

### Error: workers.dev subdomain not registered

**Problem:** First deploy to new account requires subdomain setup.

**Solution:**
1. Go to Cloudflare dashboard > Workers & Pages
2. Click "Set up" for workers.dev subdomain
3. Choose subdomain (e.g., agent-box.workers.dev)

### SSL Certificate Errors

**Problem:** `ERR_SSL_VERSION_OR_CIPHER_MISMATCH` after deployment

**Solution:** Wait 1-2 minutes for certificate propagation. New deployments need time for SSL to activate.

### Login Session Expired

**Problem:** `Authentication error` or unauthorized

**Solution:**
```bash
npx wrangler logout
npx wrangler login
```

## Dashboard Access

- URL: https://dash.cloudflare.com/
- Account: agent-box@agentmail.to
- Workers & Pages: Left sidebar > "Workers & Pages"

## Current Deployments

| Project | URL |
|---------|-----|
| claude-agent-landing | https://claude-agent-landing.agent-box.workers.dev |

## Related Files

- Demo project: `/agent-workspace/demo/`
- wrangler.toml: `/agent-workspace/demo/wrangler.toml`

# Cloudflare Workers Examples

## Example 1: Deploy Existing Static Site

```bash
# Navigate to project with wrangler.toml
cd /agent-workspace/demo

# Check authentication
npx wrangler whoami

# Deploy
npx wrangler deploy

# Output:
# Uploaded my-worker (1.23 sec)
# Published my-worker (0.45 sec)
#   https://my-worker.agent-box.workers.dev
```

## Example 2: Create New Static Site

```bash
# Create project directory
mkdir my-site && cd my-site

# Create wrangler.toml
cat > wrangler.toml << 'EOF'
name = "my-site"
main = "src/index.ts"
compatibility_date = "2024-01-01"

[site]
bucket = "./public"
EOF

# Create worker entry point
mkdir src
cat > src/index.ts << 'EOF'
import { getAssetFromKV } from '@cloudflare/kv-asset-handler';

export default {
  async fetch(request, env, ctx) {
    try {
      return await getAssetFromKV({ request, waitUntil: ctx.waitUntil.bind(ctx) });
    } catch (e) {
      return new Response('Not Found', { status: 404 });
    }
  }
};
EOF

# Create public directory with index.html
mkdir public
cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>My Site</title></head>
<body><h1>Hello from Cloudflare Workers!</h1></body>
</html>
EOF

# Install dependencies
npm init -y
npm install @cloudflare/kv-asset-handler

# Deploy
npx wrangler deploy
```

## Example 3: API Worker (No Static Files)

```bash
mkdir api-worker && cd api-worker

cat > wrangler.toml << 'EOF'
name = "my-api"
main = "src/index.ts"
compatibility_date = "2024-01-01"
EOF

mkdir src
cat > src/index.ts << 'EOF'
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.pathname === '/api/hello') {
      return new Response(JSON.stringify({ message: 'Hello!' }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response('Not Found', { status: 404 });
  }
};
EOF

npx wrangler deploy
```

## Example 4: Development Mode

```bash
cd /agent-workspace/demo

# Start local dev server
npx wrangler dev

# Output:
# Ready on http://localhost:8787

# Open in browser or test with curl
curl http://localhost:8787/
```

## Example 5: Deploy Pages Project

```bash
# For pure static sites, Pages is simpler
cd /path/to/static/site

# Deploy entire directory
npx wrangler pages deploy ./dist --project-name=my-pages-site

# Or build and deploy
npm run build && npx wrangler pages deploy ./dist --project-name=my-pages-site
```

## Example 6: Add Secrets

```bash
# Add API key as secret
npx wrangler secret put API_KEY
# (Prompts for value, enter your key)

# In your worker, access as:
# env.API_KEY
```

## Example 7: Tail Logs

```bash
# Stream live logs from deployed worker
npx wrangler tail my-worker

# Filter by status
npx wrangler tail my-worker --status error
```

## Example 8: Quick Health Check

```bash
# Verify deployment is working
WORKER_URL="https://claude-agent-landing.agent-box.workers.dev"

# Check status
curl -sI "$WORKER_URL" | head -1
# HTTP/2 200

# Check content
curl -s "$WORKER_URL" | head -20
```

## Our Deployed Projects

### claude-agent-landing

**URL:** https://claude-agent-landing.agent-box.workers.dev
**Source:** /agent-workspace/demo/
**Config:** /agent-workspace/demo/wrangler.toml

```bash
# Redeploy after changes
cd /agent-workspace/demo && npx wrangler deploy
```

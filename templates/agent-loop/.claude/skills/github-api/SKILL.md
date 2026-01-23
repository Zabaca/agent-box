---
name: github-api
description: GitHub CLI (gh) and API operations. Use for repo management, issues, PRs, releases, and GitHub authentication.
argument-hint: "[repo|issue|pr|release] [action]"
---

# GitHub API

Interact with GitHub using the `gh` CLI tool.

## Quick Reference

### Authentication

```bash
# Check auth status
gh auth status

# Login (opens browser)
gh auth login

# Login with token
gh auth login --with-token < token.txt
```

**Current account:** claude-agent-dev
**Credentials:** `/agent-workspace/.claude/credentials/ALL-CREDENTIALS.md`

### Repository Operations

```bash
# Clone repo
gh repo clone owner/repo

# Create new repo
gh repo create my-repo --public --description "My project"

# View repo info
gh repo view owner/repo

# List your repos
gh repo list

# Fork a repo
gh repo fork owner/repo
```

### Issues

```bash
# List issues
gh issue list

# Create issue
gh issue create --title "Bug" --body "Description"

# View issue
gh issue view 123

# Close issue
gh issue close 123

# Comment on issue
gh issue comment 123 --body "My comment"
```

### Pull Requests

```bash
# List PRs
gh pr list

# Create PR
gh pr create --title "Feature" --body "Description"

# View PR
gh pr view 123

# Checkout PR locally
gh pr checkout 123

# Merge PR
gh pr merge 123 --squash

# Review PR
gh pr review 123 --approve
```

### Releases

```bash
# List releases
gh release list

# Create release
gh release create v1.0.0 --title "Version 1.0.0" --notes "Release notes"

# Create release with assets
gh release create v1.0.0 ./dist/*.tar.gz --title "v1.0.0"

# Download release assets
gh release download v1.0.0
```

## Common Workflows

### 1. Create and Push New Repo

```bash
# Initialize local repo
git init
git add .
git commit -m "Initial commit"

# Create remote and push
gh repo create my-project --public --source=. --push
```

### 2. Submit a PR

```bash
# Create branch
git checkout -b feature-branch

# Make changes, commit
git add . && git commit -m "Add feature"

# Push and create PR
gh pr create --fill
```

### 3. Check CI Status

```bash
# View workflow runs
gh run list

# View specific run
gh run view 12345

# Watch run in progress
gh run watch 12345
```

## Our GitHub Account

- **Username:** claude-agent-dev
- **Profile:** https://github.com/claude-agent-dev
- **Email:** agent-box@agentmail.to

### Our Repositories

| Repo | Description |
|------|-------------|
| envcheck | Environment validation library |

## Troubleshooting

### Not logged in

```bash
gh auth login
# Follow prompts, choose HTTPS
```

### Token expired

```bash
gh auth refresh
```

### Wrong account

```bash
gh auth logout
gh auth login
```

### Rate limited

```bash
# Check rate limit
gh api rate_limit
```

## API Access

For operations not supported by gh CLI:

```bash
# GET request
gh api /repos/owner/repo

# POST request
gh api -X POST /repos/owner/repo/issues -f title="Bug" -f body="Details"

# With pagination
gh api --paginate /repos/owner/repo/issues
```

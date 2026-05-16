# GitHub CLI Reference

## Command Overview

| Category | Command | Description |
|----------|---------|-------------|
| Auth | `gh auth` | Manage authentication |
| Repo | `gh repo` | Repository operations |
| Issue | `gh issue` | Issue management |
| PR | `gh pr` | Pull request operations |
| Release | `gh release` | Release management |
| Workflow | `gh run` | GitHub Actions |
| API | `gh api` | Direct API access |

## Authentication Commands

```bash
gh auth login              # Interactive login
gh auth logout             # Remove credentials
gh auth status             # Show current auth
gh auth refresh            # Refresh token
gh auth token              # Print token
gh auth setup-git          # Configure git to use gh
```

## Repository Commands

```bash
# Create
gh repo create NAME [flags]
  --public                 # Public visibility
  --private                # Private visibility
  --description "text"     # Repo description
  --source .               # Use current directory
  --push                   # Push local commits

# Clone
gh repo clone REPO [DIR]
gh repo clone owner/repo

# View
gh repo view [REPO]
gh repo view --web         # Open in browser

# List
gh repo list [OWNER]
  --limit N                # Number of repos
  --public/--private       # Filter by visibility

# Fork
gh repo fork REPO
  --clone                  # Clone after forking

# Delete
gh repo delete REPO --yes

# Sync fork
gh repo sync
```

## Issue Commands

```bash
# List
gh issue list
  --state open|closed|all
  --label "bug"
  --assignee @me
  --limit N

# Create
gh issue create
  --title "Title"
  --body "Body"
  --label "bug,urgent"
  --assignee "user"

# View
gh issue view NUMBER
  --web                    # Open in browser
  --comments               # Show comments

# Edit
gh issue edit NUMBER
  --title "New title"
  --add-label "label"

# Close/Reopen
gh issue close NUMBER
gh issue reopen NUMBER

# Comment
gh issue comment NUMBER --body "text"

# Transfer
gh issue transfer NUMBER REPO
```

## Pull Request Commands

```bash
# List
gh pr list
  --state open|closed|merged|all
  --author @me
  --base main

# Create
gh pr create
  --title "Title"
  --body "Description"
  --base main
  --head feature-branch
  --fill                   # Auto-fill from commits
  --draft                  # Create as draft

# View
gh pr view NUMBER
  --web
  --comments

# Checkout
gh pr checkout NUMBER

# Merge
gh pr merge NUMBER
  --merge                  # Merge commit
  --squash                 # Squash and merge
  --rebase                 # Rebase and merge
  --delete-branch          # Delete branch after

# Review
gh pr review NUMBER
  --approve
  --request-changes --body "text"
  --comment --body "text"

# Ready
gh pr ready NUMBER         # Mark ready for review

# Close
gh pr close NUMBER
```

## Release Commands

```bash
# List
gh release list
  --limit N

# Create
gh release create TAG [FILES]
  --title "Title"
  --notes "Release notes"
  --notes-file CHANGELOG.md
  --draft
  --prerelease
  --target BRANCH

# View
gh release view TAG

# Download
gh release download TAG
  --pattern "*.tar.gz"
  --dir ./downloads

# Delete
gh release delete TAG --yes
```

## Workflow/Actions Commands

```bash
# List runs
gh run list
  --workflow NAME
  --status completed|in_progress|queued|failure

# View run
gh run view RUN_ID
  --log                    # Show logs
  --job JOB_ID

# Watch run
gh run watch RUN_ID

# Rerun
gh run rerun RUN_ID
  --failed                 # Only failed jobs

# Cancel
gh run cancel RUN_ID

# List workflows
gh workflow list

# Run workflow
gh workflow run NAME
  -f input=value
```

## API Commands

```bash
# GET request
gh api ENDPOINT
gh api /repos/owner/repo
gh api /user

# POST request
gh api -X POST ENDPOINT -f key=value
gh api -X POST /repos/owner/repo/issues -f title="Bug"

# With JSON body
gh api -X POST ENDPOINT --input data.json

# Pagination
gh api --paginate /repos/owner/repo/issues

# Output format
gh api ENDPOINT --jq '.key'
gh api ENDPOINT -q '.items[].name'

# Headers
gh api -H "Accept: application/vnd.github+json" ENDPOINT
```

## Output Formatting

Most commands support:

```bash
--json FIELDS              # Output as JSON
--jq EXPRESSION            # Filter JSON output
--template TEMPLATE        # Go template
```

Example:
```bash
gh repo list --json name,url --jq '.[].name'
gh issue list --json number,title,state
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `GH_TOKEN` | Auth token (overrides login) |
| `GH_HOST` | GitHub hostname |
| `GH_REPO` | Default repository |
| `GH_EDITOR` | Editor for prompts |
| `NO_COLOR` | Disable colors |

## Rate Limits

```bash
# Check rate limit
gh api rate_limit

# Response shows:
# - core: 5000/hour (authenticated)
# - search: 30/minute
# - graphql: 5000/hour
```

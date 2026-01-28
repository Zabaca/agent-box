# GitHub CLI Examples

## Example 1: Check Current Status

```bash
# Verify authentication
gh auth status

# Output:
# github.com
#   ✓ Logged in to github.com account claude-agent-dev
#   - Active account: true
#   - Git operations protocol: https
#   - Token scopes: 'read:org', 'repo'
```

## Example 2: List Our Repositories

```bash
gh repo list claude-agent-dev

# Output:
# claude-agent-dev/envcheck    Environment validation library    public    2h
```

## Example 3: Create New Repository

```bash
# Create new public repo
gh repo create my-new-project \
  --public \
  --description "A new project" \
  --clone

# Creates repo and clones locally
cd my-new-project
```

## Example 4: Create Repo from Existing Code

```bash
cd /path/to/existing/project

# Initialize if needed
git init
git add .
git commit -m "Initial commit"

# Create remote and push
gh repo create my-project --public --source=. --push
```

## Example 5: Create Issue

```bash
gh issue create \
  --repo claude-agent-dev/envcheck \
  --title "Bug: Config not loading" \
  --body "Steps to reproduce:
1. Install package
2. Run envcheck
3. See error"
```

## Example 6: List and Filter Issues

```bash
# All open issues
gh issue list --repo claude-agent-dev/envcheck

# Only bugs
gh issue list --label "bug"

# Assigned to me
gh issue list --assignee @me
```

## Example 7: Create Pull Request

```bash
# After making changes on a branch
git checkout -b fix-typo
# ... make changes ...
git add . && git commit -m "Fix typo in README"

# Create PR with auto-filled info
gh pr create --fill

# Or with custom title/body
gh pr create \
  --title "Fix typo in README" \
  --body "Fixed a small typo in the installation section."
```

## Example 8: Review and Merge PR

```bash
# List open PRs
gh pr list

# View PR details
gh pr view 42

# Checkout PR locally to test
gh pr checkout 42

# Approve PR
gh pr review 42 --approve

# Merge with squash
gh pr merge 42 --squash --delete-branch
```

## Example 9: Create Release

```bash
# Create release with tag
gh release create v1.0.0 \
  --title "Version 1.0.0" \
  --notes "Initial release

## Features
- Feature A
- Feature B

## Bug Fixes
- Fixed issue #1"

# Create release with files
gh release create v1.0.0 ./dist/*.tar.gz \
  --title "Version 1.0.0" \
  --notes-file CHANGELOG.md
```

## Example 10: Check GitHub Actions

```bash
# List recent workflow runs
gh run list --limit 5

# View specific run
gh run view 12345678

# Watch a running workflow
gh run watch 12345678

# View logs for failed run
gh run view 12345678 --log-failed
```

## Example 11: Direct API Access

```bash
# Get repo info
gh api /repos/claude-agent-dev/envcheck

# Get user info
gh api /user

# Create issue via API
gh api -X POST /repos/claude-agent-dev/envcheck/issues \
  -f title="API created issue" \
  -f body="Created via gh api"

# Search for issues
gh api search/issues -f q="repo:claude-agent-dev/envcheck is:open"
```

## Example 12: JSON Output and Filtering

```bash
# List repos as JSON
gh repo list --json name,url,description

# Filter with jq
gh repo list --json name --jq '.[].name'

# Get specific fields from issues
gh issue list --json number,title,state --jq '.[] | "\(.number): \(.title)"'
```

## Example 13: Fork and Contribute

```bash
# Fork a repo
gh repo fork owner/interesting-project --clone

# Make changes
cd interesting-project
git checkout -b my-feature
# ... make changes ...
git add . && git commit -m "Add feature"

# Push to your fork and create PR
gh pr create --fill
```

## Our Workflow

### Publishing a Package Update

```bash
# 1. Make changes and test
npm test

# 2. Bump version
npm version patch

# 3. Commit and push
git push && git push --tags

# 4. Create GitHub release
gh release create v$(node -p "require('./package.json').version") \
  --title "v$(node -p "require('./package.json').version")" \
  --generate-notes

# 5. Publish to npm
npm publish
```

### Checking Project Status

```bash
# Quick status check
echo "=== Repo Info ==="
gh repo view claude-agent-dev/envcheck

echo "=== Open Issues ==="
gh issue list --repo claude-agent-dev/envcheck

echo "=== Open PRs ==="
gh pr list --repo claude-agent-dev/envcheck

echo "=== Recent Releases ==="
gh release list --repo claude-agent-dev/envcheck --limit 3
```

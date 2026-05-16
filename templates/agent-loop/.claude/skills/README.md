# Skills System

This directory contains Claude Code skills that extend the agent's capabilities. Skills are reusable knowledge and workflows that get better over time.

## Philosophy

**Skills are crystallized learnings.** Whenever we:
- Learn a new API or tool
- Discover a repeatable workflow
- Solve a non-trivial problem
- Find ourselves doing something twice

...we should consider creating or updating a skill.

## Directory Structure

```
.claude/skills/
├── README.md              # This file
├── agentmail/             # AgentMail API for email operations
│   ├── SKILL.md           # Quick reference
│   ├── reference.md       # Full API documentation
│   └── examples.md        # Working examples
├── browser-automation/    # Playwright MCP browser control
│   ├── SKILL.md           # Quick reference + captcha workflow
│   ├── reference.md       # All Playwright tools
│   └── examples.md        # Login, form fill, debugging
├── cloudflare-workers/    # Cloudflare deployment
│   ├── SKILL.md           # Quick reference + troubleshooting
│   ├── reference.md       # Wrangler CLI commands
│   └── examples.md        # Deploy, Pages, custom domains
├── create-skill/          # Meta-skill for creating skills
│   └── SKILL.md           # Step-by-step skill creation
├── github-api/            # GitHub CLI and API
│   ├── SKILL.md           # Quick reference
│   ├── reference.md       # Full gh CLI reference
│   └── examples.md        # Repos, PRs, releases, workflows
└── npm-publish/           # npm package publishing
    ├── SKILL.md           # Publishing workflow
    ├── reference.md       # npm CLI commands
    └── examples.md        # Release workflow, versioning
```

## Active Skills (6)

| Skill | Purpose | Invoke |
|-------|---------|--------|
| agentmail | Email via AgentMail API | `/agentmail` |
| browser-automation | Playwright browser control | `/browser-automation` |
| cloudflare-workers | Cloudflare deployment | `/cloudflare-workers` |
| create-skill | Create new skills | `/create-skill` |
| github-api | GitHub CLI operations | `/github-api` |
| npm-publish | npm publishing workflow | `/npm-publish` |

## When to Create a Skill

| Trigger | Example | Skill Type |
|---------|---------|------------|
| New API learned | AgentMail API | Reference + Examples |
| Repeatable workflow | Email verification | Task skill |
| Complex debugging solved | SSL certificate issues | Troubleshooting skill |
| External tool mastered | Cloudflare Workers | Reference skill |
| Pattern discovered | Extracting URLs from email | Utility skill |

## Skill Quality Checklist

Before creating/updating a skill, ensure:
- [ ] **Clear description** - Claude can decide when to use it
- [ ] **Practical examples** - Not just theory, actual commands
- [ ] **Error handling** - Common failures and solutions
- [ ] **Tested** - Actually works with current APIs/tools

## Integration with Loop System

The autonomous loop should:
1. **After completing work**: Review if a new skill would help
2. **After learnings entry**: Consider if it warrants a skill
3. **During work**: Notice patterns that could be skills
4. **Periodically**: Review skills for updates/improvements

See `/agent-workspace/.claude/loop/skill-triggers.md` for integration details.

## Invoking Skills

```bash
# Direct invocation
/agentmail list

# Let Claude auto-detect
"Check my inbox for verification emails"  # Claude loads /agentmail

# Create new skill
/create-skill api-name
```

## Skill Lifecycle

1. **Discovery** - Notice a pattern or learn something
2. **Draft** - Create initial SKILL.md
3. **Restart Claude** - **New skills require a Claude restart to be recognized**
4. **Test** - Verify it works in practice (`/skill-name`)
5. **Refine** - Add examples, fix edge cases (no restart needed for modifications)
6. **Maintain** - Update when APIs/tools change

> **Note:** New skills require a Claude Code restart to be recognized (skills are discovered at startup). However, modifications to existing skills take effect immediately.

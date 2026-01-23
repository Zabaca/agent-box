---
name: create-skill
description: Create a new Claude Code skill from something just learned. Use after learning a new API, tool, workflow, or solving a complex problem.
argument-hint: "[skill-name] [brief-description]"
disable-model-invocation: true
---

# Create New Skill

Create a new skill to capture and reuse knowledge.

## Arguments

`$ARGUMENTS` should be: `skill-name brief-description`

If no arguments provided, I'll ask what we just learned.

## Process

1. **Analyze what was learned**
   - What API/tool/workflow did we just use?
   - What were the key insights?
   - What mistakes did we make initially?
   - What would help next time?

2. **Create skill structure**
   ```bash
   mkdir -p /agent-workspace/.claude/skills/{skill-name}
   ```

3. **Write SKILL.md** with:
   - Clear frontmatter (name, description, argument-hint)
   - Quick reference section
   - Common operations
   - Example commands that actually work

4. **Add reference.md** if the skill has:
   - API documentation
   - Configuration options
   - Error codes/troubleshooting

5. **Add examples.md** with:
   - Real working examples (tested!)
   - Common use cases
   - Copy-paste ready commands

6. **Update learnings.md**
   - Note that a skill was created
   - Cross-reference the skill location

7. **Restart Claude** (for new skills only)
   - New skills require a Claude restart to be discovered
   - Modifications to existing skills take effect immediately

8. **Test the skill**
   - Try invoking it: `/skill-name`
   - Verify examples work

## Quality Checklist

Before completing, verify:
- [ ] Description is clear enough for auto-detection
- [ ] At least 3 working examples
- [ ] Common errors documented
- [ ] Credentials/config locations noted
- [ ] Tested with actual invocation

## Example: Creating a Cloudflare Skill

```markdown
---
name: cloudflare-workers
description: Deploy and manage Cloudflare Workers. Use when deploying sites, checking status, or managing workers.
argument-hint: "[deploy|status|logs] [project-path]"
---

# Cloudflare Workers

## Quick Reference

**Deploy:**
\`\`\`bash
cd /path/to/project && npx wrangler deploy
\`\`\`

**Check status:**
\`\`\`bash
npx wrangler whoami
\`\`\`

...
```

## Skill Categories

| Category | Use For | Example Skills |
|----------|---------|----------------|
| **API** | External service integration | agentmail, github-api |
| **Tool** | CLI/software usage | wrangler, playwright |
| **Workflow** | Multi-step processes | email-verify, deploy |
| **Debug** | Troubleshooting guides | ssl-issues, api-errors |

## After Creation

1. Test the skill works
2. Add entry to `/agent-workspace/.claude/skills/README.md`
3. Consider if loop should auto-trigger this skill

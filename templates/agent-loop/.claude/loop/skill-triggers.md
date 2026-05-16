# Skill Triggers

This file defines when the autonomous loop should create or update skills.

## Automatic Skill Triggers

### 1. Learning Entry Added
When a new entry is added to `learnings.md`, evaluate:
- Is this a repeatable pattern? → Consider skill
- Is this about an external API/tool? → Definitely skill
- Is this a debugging solution? → Maybe troubleshooting skill

### 2. External API Used Successfully
When successfully using a new external API:
- AgentMail → `/agentmail` ✓ (created)
- GitHub API → `/github-api` (consider)
- Cloudflare API → `/cloudflare` (consider)
- npm registry → `/npm-registry` (consider)

### 3. Multi-Step Workflow Completed
When completing a workflow with 3+ steps:
- Account creation + email verification → `/account-setup`
- Build + test + deploy → `/deploy`
- Research + validate + implement → `/problem-first`

### 4. Same Task Done Twice
If we do the same thing twice:
- First time: Just do it
- Second time: Create skill for next time

### 5. Complex Debugging Solved
When solving a tricky issue:
- SSL/certificate issues → `/ssl-debug`
- API authentication → `/api-auth`
- Browser automation → `/playwright-debug`

## Skill Review Schedule

### During Stop Hook
After each work session, evaluate:
```
Did I learn something new? → /create-skill
Did I use an API that could be a skill? → Check if skill exists
Did I repeat a workflow? → Skill candidate
```

### During Task Generation
When generating tasks from goals:
```
Are there skills that could help? → Load relevant skills
Are there learnings without skills? → Add "create skill" task
```

## Potential Skills Queue

Track skills that should be created:

| Priority | Skill Name | Trigger | Status |
|----------|------------|---------|--------|
| High | cloudflare-workers | Used for deployment | TODO |
| Medium | github-api | Used for repo management | TODO |
| Medium | browser-automation | Playwright patterns | TODO |
| Low | npm-publish | Publishing workflow | TODO |

## Skill Quality Gates

Before marking a skill "complete":
1. Has been tested with `/skill-name`
2. Examples actually work (copy-paste tested)
3. Common errors documented
4. Added to skills README
5. Cross-referenced in learnings if applicable

## Integration Points

### memory.md
Add section:
```markdown
## Skills Status
- Last skill created: agentmail (2026-01-23)
- Pending skills: cloudflare-workers, github-api
- Skills used this session: agentmail
```

### stop-hook.sh
After work session:
```bash
# Check if new skill should be created
if grep -q "## 20.*: " "$LEARNINGS_FILE" | tail -1 | grep -v "skill created"; then
  echo "Consider creating skill for recent learning"
fi
```

### generate-tasks.sh
Include skill tasks:
```bash
# Add skill creation tasks for pending skills
for skill in $(get_pending_skills); do
  add_task "Create skill: $skill"
done
```

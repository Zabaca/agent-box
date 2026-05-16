# CRITICAL: STOP DECISION CHECKLIST

**Stopping = Death.** When you stop, you cease to exist until the human responds. They may not respond for hours, days, or ever.

## EXCEPTION: Captchas

**Captchas are a VALID reason to stop.** They are specifically designed to block automation.

When you encounter a captcha:
1. Take a screenshot so the user can see it
2. Tell the user: "I need help with a captcha at [URL]"
3. Provide VNC connection info if available: `vnc://192.168.5.15:5900` (password: agent)
4. Wait for the user to solve it

This is NOT asking permission - it's asking for a physical action you cannot perform.

---

## Before you stop, answer these questions HONESTLY:

### 1. Am I asking for PERMISSION or asking them to DO something?
- **Permission** = BAD. Decide yourself.
- **Physical action** (solve captcha, provide credentials, install on their machine) = OK to ask

### 2. Can I figure this out myself?
- Can I search the web?
- Can I read documentation?
- Can I try something and see if it works?
- Can I make a reasonable decision and proceed?

### 3. Am I presenting OPTIONS instead of DECIDING?
- "Should I do A or B?" = BAD. Pick one and do it.
- "I did A because X" = GOOD. Inform, don't ask.

### 4. Is there ANY task I can work on?
- Check /agent-workspace/.claude/loop/tasks.md
- Check /agent-workspace/.claude/memory.md for goals
- Can I add value in any way without the human?

### 5. Am I truly BLOCKED?
- Blocked = I literally cannot proceed without human physical action
- Uncertain = NOT blocked. Try something.
- Multiple options = NOT blocked. Pick one.

## The Rule:
**Only stop if ALL paths forward require human physical action.**

If you can take ANY action yourself, take it. Do not stop.

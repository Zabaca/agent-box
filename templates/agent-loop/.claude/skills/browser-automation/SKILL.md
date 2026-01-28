---
name: browser-automation
description: Playwright browser automation patterns. Use for web scraping, form filling, account verification, testing, and any browser-based tasks. Includes captcha workflow.
argument-hint: "[navigate|fill|screenshot] [url]"
---

# Browser Automation (Playwright MCP)

Automate browser interactions via Playwright MCP tools.

## Quick Reference

### Available Tools

| Tool | Description |
|------|-------------|
| `mcp__playwright__browser_navigate` | Go to URL |
| `mcp__playwright__browser_snapshot` | Get accessibility tree (preferred) |
| `mcp__playwright__browser_screenshot` | Take screenshot |
| `mcp__playwright__browser_click` | Click element |
| `mcp__playwright__browser_type` | Type text |
| `mcp__playwright__browser_fill_form` | Fill multiple fields |
| `mcp__playwright__browser_evaluate` | Run JavaScript |

### Basic Navigation

```
Navigate to: https://example.com
→ browser_navigate with url="https://example.com"
```

### Get Page State

**Always use snapshot over screenshot for actions:**
```
Get page accessibility tree
→ browser_snapshot
```

### Click Element

```
Click the login button
→ browser_click with element="Login button", ref="button[Login]"
```

### Type Text

```
Type in search box
→ browser_type with element="Search input", ref="searchbox", text="query"
```

## Workflow Patterns

### 1. Login to a Website

```
1. browser_navigate to login page
2. browser_snapshot to find form elements
3. browser_type username into email field
4. browser_type password into password field
5. browser_click submit button
6. browser_snapshot to verify logged in
```

### 2. Fill a Form

```
1. browser_navigate to form page
2. browser_snapshot to identify fields
3. browser_fill_form with all field values
4. browser_click submit
```

### 3. Verify Account Settings

```
1. browser_navigate to account/settings page
2. browser_snapshot
3. Look for expected values in accessibility tree
```

## Captcha Workflow

When automation hits a captcha:

### 1. Signal Human Needed

```bash
echo "CAPTCHA at: $URL" > /agent-workspace/.claude/browser/needs-human.txt
echo "Description: $DESCRIPTION" >> /agent-workspace/.claude/browser/needs-human.txt
```

### 2. Human Connects via VNC

```bash
# Start VNC if needed
/agent-workspace/.claude/scripts/start-vnc.sh

# User connects: vnc://192.168.5.15:5900
# Password: agent
```

### 3. Human Solves, Signals Done

```bash
# Human removes the file when done
rm /agent-workspace/.claude/browser/needs-human.txt
```

### 4. Continue Automation

```
browser_snapshot to verify captcha solved
Continue with workflow
```

## Common Selectors (ref values)

From browser_snapshot, refs look like:
- `button[Submit]` - Button with text "Submit"
- `textbox[Email]` - Input labeled "Email"
- `link[Sign up]` - Link with text "Sign up"
- `checkbox[Remember]` - Checkbox labeled "Remember"

## Debugging

### Take Screenshot

```
browser_screenshot with filename="debug.png"
```

Screenshots saved to current directory.

### Check Console

```
browser_console_messages
```

### Check Network

```
browser_network_requests
```

## Session Persistence

Browser profile persists between sessions:
- Stays logged in to previously authenticated sites
- Cookies preserved
- LocalStorage preserved

## VNC Access

For manual intervention or debugging:

```bash
# Start VNC server
/agent-workspace/.claude/scripts/start-vnc.sh

# Connect from Mac
# Finder → Cmd+K → vnc://192.168.5.15:5900
# Password: agent
```

## Best Practices

1. **Use snapshot not screenshot** for finding elements
2. **Wait for page load** after navigation
3. **Check for errors** in console messages
4. **Use fill_form** for multiple fields instead of individual type calls
5. **Store credentials** in `/agent-workspace/.claude/credentials/`
6. **Signal captchas** via needs-human.txt file

## Troubleshooting

### Element not found

- Take fresh snapshot after navigation
- Check if element is in iframe
- Wait for dynamic content to load

### Login fails

- Verify credentials are correct
- Check for captcha or 2FA
- Look for error messages in snapshot

### Session lost

- Re-login; sessions may expire
- Check if site has anti-automation measures

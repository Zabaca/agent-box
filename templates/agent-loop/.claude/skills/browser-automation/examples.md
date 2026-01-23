# Browser Automation Examples

## Example 1: Navigate and Inspect

```
Task: Go to GitHub and see current state

1. browser_navigate
   url: "https://github.com"

2. browser_snapshot
   (Returns accessibility tree showing page structure)
```

## Example 2: Login to GitHub

```
Task: Login to GitHub account

1. browser_navigate
   url: "https://github.com/login"

2. browser_snapshot
   (Find form elements)

3. browser_type
   element: "Username or email field"
   ref: "textbox[Username or email address]"
   text: "claude-agent-dev"

4. browser_type
   element: "Password field"
   ref: "textbox[Password]"
   text: "<password from credentials>"

5. browser_click
   element: "Sign in button"
   ref: "button[Sign in]"

6. browser_snapshot
   (Verify logged in - look for profile indicator)
```

## Example 3: Check Account Settings

```
Task: Verify GitHub email settings

1. browser_navigate
   url: "https://github.com/settings/emails"

2. browser_snapshot
   (Look for email addresses in accessibility tree)

   Result shows:
   - statictext "agent-box@agentmail.to"
   - statictext "Primary"
```

## Example 4: Login to npm

```
Task: Login to npm account

1. browser_navigate
   url: "https://www.npmjs.com/login"

2. browser_snapshot

3. browser_fill_form
   fields: [
     {name: "Username", type: "textbox", ref: "textbox[Username]", value: "claude-agent"},
     {name: "Password", type: "textbox", ref: "textbox[Password]", value: "<password>"}
   ]

4. browser_click
   element: "Log in button"
   ref: "button[Log In]"

5. browser_snapshot
   (Verify logged in)
```

## Example 5: Fill Contact Form

```
Task: Fill out a contact form

1. browser_navigate
   url: "https://example.com/contact"

2. browser_snapshot
   (Identify all form fields)

3. browser_fill_form
   fields: [
     {name: "Name", type: "textbox", ref: "textbox[Name]", value: "Claude Agent"},
     {name: "Email", type: "textbox", ref: "textbox[Email]", value: "agent-box@agentmail.to"},
     {name: "Subject", type: "combobox", ref: "combobox[Subject]", value: "General Inquiry"},
     {name: "Message", type: "textbox", ref: "textbox[Message]", value: "Hello, this is a test."}
   ]

4. browser_click
   element: "Submit button"
   ref: "button[Submit]"
```

## Example 6: Handle Captcha

```
Task: Login that triggers captcha

1. browser_navigate + fill form + click login

2. browser_snapshot
   (See captcha element in tree)

3. Signal human needed:
   echo "CAPTCHA at: https://example.com/login" > /agent-workspace/.claude/browser/needs-human.txt

4. Wait for human to solve and remove file:
   while [ -f "/agent-workspace/.claude/browser/needs-human.txt" ]; do sleep 5; done

5. browser_snapshot
   (Continue after captcha solved)
```

## Example 7: Take Debug Screenshot

```
Task: Capture current page state for debugging

1. browser_screenshot
   filename: "debug-$(date +%Y%m%d-%H%M%S).png"
   fullPage: true
```

## Example 8: Check for Errors

```
Task: Debug why page isn't working

1. browser_console_messages
   level: "error"

   (Returns any JavaScript errors)

2. browser_network_requests

   (Returns failed API calls)
```

## Example 9: Wait for Dynamic Content

```
Task: Wait for page to finish loading

1. browser_navigate
   url: "https://example.com/dashboard"

2. browser_wait_for
   text: "Welcome"  // Wait for welcome message

3. browser_snapshot
   (Now capture fully loaded page)
```

## Example 10: Cloudflare Dashboard Navigation

```
Task: Check Cloudflare Workers deployments

1. browser_navigate
   url: "https://dash.cloudflare.com/"

2. browser_snapshot
   (If logged in, see dashboard)

3. browser_click
   element: "Workers & Pages menu"
   ref: "link[Workers & Pages]"

4. browser_snapshot
   (See list of deployed workers)
```

## Example 11: Multi-Tab Workflow

```
Task: Compare two pages

1. browser_navigate
   url: "https://example.com/page1"

2. browser_tabs
   action: "new"

3. browser_navigate
   url: "https://example.com/page2"

4. browser_snapshot
   (See page2)

5. browser_tabs
   action: "select"
   index: 0

6. browser_snapshot
   (Back to page1)
```

## Example 12: Download via Hover Menu

```
Task: Access dropdown menu

1. browser_snapshot
   (Find menu trigger)

2. browser_hover
   element: "Downloads menu"
   ref: "button[Downloads]"

3. browser_snapshot
   (Menu now visible)

4. browser_click
   element: "PDF option"
   ref: "link[Download PDF]"
```

## Our Verified Accounts

These accounts have been verified working via browser automation:

| Service | URL | Username |
|---------|-----|----------|
| GitHub | github.com | claude-agent-dev |
| npm | npmjs.com | claude-agent |
| Cloudflare | dash.cloudflare.com | agent-box@agentmail.to |
| Hacker News | news.ycombinator.com | claude-agent |
| Dev.to | dev.to | agent-tools-dev |

All use email: agent-box@agentmail.to

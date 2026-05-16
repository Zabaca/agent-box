# Playwright MCP Tool Reference

## Navigation Tools

### browser_navigate

Navigate to a URL.

```json
{
  "url": "https://example.com"
}
```

### browser_navigate_back

Go back to previous page. No parameters.

### browser_tabs

Manage browser tabs.

```json
{
  "action": "list|new|close|select",
  "index": 0  // For close/select
}
```

## Page Inspection

### browser_snapshot

Get accessibility tree of current page. **Preferred over screenshot for actions.**

```json
{
  "filename": "snapshot.md"  // Optional: save to file
}
```

Returns structured accessibility tree with refs for elements.

### browser_screenshot

Take visual screenshot.

```json
{
  "filename": "page.png",      // Optional
  "type": "png|jpeg",          // Default: png
  "fullPage": true,            // Capture entire page
  "element": "description",    // Screenshot specific element
  "ref": "element-ref"         // Ref from snapshot
}
```

### browser_console_messages

Get console logs.

```json
{
  "level": "error|warning|info|debug"  // Default: info
}
```

### browser_network_requests

Get network requests since page load.

```json
{
  "includeStatic": false  // Include images, fonts, etc.
}
```

## Interaction Tools

### browser_click

Click an element.

```json
{
  "element": "Human-readable description",
  "ref": "element-ref-from-snapshot",
  "button": "left|right|middle",  // Default: left
  "doubleClick": false,
  "modifiers": ["Alt", "Control", "Shift", "Meta"]
}
```

### browser_type

Type text into editable element.

```json
{
  "element": "Description of input",
  "ref": "element-ref",
  "text": "Text to type",
  "slowly": false,    // Type one char at a time
  "submit": false     // Press Enter after
}
```

### browser_fill_form

Fill multiple form fields at once.

```json
{
  "fields": [
    {
      "name": "Email field",
      "type": "textbox",
      "ref": "email-ref",
      "value": "user@example.com"
    },
    {
      "name": "Password field",
      "type": "textbox",
      "ref": "password-ref",
      "value": "secret"
    },
    {
      "name": "Remember me",
      "type": "checkbox",
      "ref": "remember-ref",
      "value": "true"
    }
  ]
}
```

Field types: `textbox`, `checkbox`, `radio`, `combobox`, `slider`

### browser_select_option

Select dropdown option.

```json
{
  "element": "Country dropdown",
  "ref": "country-ref",
  "values": ["US"]  // Can select multiple
}
```

### browser_hover

Hover over element (for menus, tooltips).

```json
{
  "element": "Menu item",
  "ref": "menu-ref"
}
```

### browser_drag

Drag and drop.

```json
{
  "startElement": "Drag source",
  "startRef": "source-ref",
  "endElement": "Drop target",
  "endRef": "target-ref"
}
```

### browser_press_key

Press keyboard key.

```json
{
  "key": "Enter|Tab|Escape|ArrowDown|..."
}
```

### browser_file_upload

Upload files.

```json
{
  "paths": ["/path/to/file1.pdf", "/path/to/file2.jpg"]
}
```

## JavaScript Execution

### browser_evaluate

Run JavaScript on page.

```json
{
  "function": "() => document.title",
  "element": "Optional element description",
  "ref": "optional-element-ref"
}
```

With element:
```json
{
  "function": "(element) => element.textContent",
  "element": "Target element",
  "ref": "element-ref"
}
```

### browser_run_code

Run full Playwright code.

```json
{
  "code": "async (page) => { await page.click('button'); return page.title(); }"
}
```

## Dialog Handling

### browser_handle_dialog

Handle alert/confirm/prompt dialogs.

```json
{
  "accept": true,           // Accept or dismiss
  "promptText": "response"  // For prompt dialogs
}
```

## Utility

### browser_wait_for

Wait for conditions.

```json
{
  "text": "Success",      // Wait for text to appear
  "textGone": "Loading",  // Wait for text to disappear
  "time": 5               // Wait N seconds
}
```

### browser_resize

Resize browser window.

```json
{
  "width": 1920,
  "height": 1080
}
```

### browser_close

Close the browser. No parameters.

### browser_install

Install browser if missing. No parameters.

## Accessibility Tree Format

From `browser_snapshot`, elements appear as:

```
- button "Submit" [ref=submit-btn]
- textbox "Email" [ref=email-input]
- link "Sign up" [ref=signup-link]
- checkbox "Remember me" [ref=remember-cb] [checked]
```

Use the `ref` value in click/type operations.

## Common Ref Patterns

| Element | Typical Ref Format |
|---------|-------------------|
| Button | `button[Text]` |
| Link | `link[Text]` |
| Input | `textbox[Label]` |
| Checkbox | `checkbox[Label]` |
| Select | `combobox[Label]` |

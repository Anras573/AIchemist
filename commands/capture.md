---
name: capture
description: Quick capture of thoughts, code snippets, or insights to Obsidian without leaving the coding flow.
argument-hint: "<text> [--note <name>] [--tag #tag] [--code]"
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# Capture Command

Quick capture to Obsidian for thoughts, code snippets, and insights during coding sessions. Designed for minimal friction — just type and capture.

## Usage

```
/capture This auth pattern works well for SPAs
/capture --note "Architecture Decisions" Using event sourcing for audit trail
/capture --tag #security Found XSS vulnerability in form handling
/capture --code                        # Capture current file context
```

## Arguments

| Argument | Description |
|----------|-------------|
| `<text>` | Content to capture (required unless `--code`) |
| `--note <name>` | Target a specific note instead of daily note |
| `--tag #tag` | Add tag(s) to the capture |
| `--code` | Include current file context |

Multiple tags can be specified: `--tag #security --tag #auth`

## Default Behavior

Without flags, captures append to **today's daily note** with:
- Timestamp header
- The captured content
- Project context (current directory name)

## Configuration

Uses settings from `${CLAUDE_PLUGIN_ROOT}/config.json`:

```json
{
  "obsidian": {
    "daily_note_path": "Daily Notes/{{date:YYYY-MM-DD}}.md",
    "capture_folder": "Captures"
  }
}
```

## Execution Steps

### 1. Parse Arguments

Extract from user input:
- `text`: The content to capture (everything not a flag)
- `--note <name>`: Optional target note name
- `--tag #tag`: Optional tags (can be multiple)
- `--code`: Boolean flag for code context

### 2. Determine Target

**If `--note` specified:**
- If note name does **not** include `/`: target path is `{capture_folder}/{note_name}.md`
- If note name **includes** `/`: treat as subpath under `capture_folder`
  - Target path is `{capture_folder}/{note_name}.md`
  - Example: `--note "Projects/Auth"` → `Captures/Projects/Auth.md`

**Otherwise (default):**
- Target: today's daily note (using `daily_note_path` pattern)

### 3. Build Capture Content

Format the capture entry:

```markdown

## {{time:HH:MM}} - Capture

{{content}}

{{#if tags}}**Tags:** {{tags}}{{/if}}
{{#if context}}**Context:** {{context}}{{/if}}
```

**Example output:**
```markdown

## 14:32 - Capture

This auth pattern using JWT refresh tokens works well for SPAs

**Tags:** #auth #patterns
**Context:** ProjectName
```

### 4. Handle Code Context (if --code)

If `--code` flag is set:

1. Get current working directory and any recent file context
2. Format as code block:

```markdown

## 14:32 - Code Capture

{{text_content}}

**File:** `src/auth/middleware.ts`
```typescript
// relevant code snippet if available
```

**Context:** ProjectName
```

### 5. Append to Target

**Check if target note exists:**
```bash
# For daily note
obsidian daily:read vault="<preferredVault>" 2>/dev/null
# If exits (exit code 0) → proceed to append
# If not found → create new note

# For named note
obsidian read path="<note-path>" vault="<preferredVault>" 2>/dev/null
# If exists → proceed to append
# If not found → create new note
```

**If target note exists:**
```bash
# For daily note
obsidian daily:append content="<formatted-capture>" vault="<preferredVault>"

# For named note
obsidian append path="<note-path>" content="<formatted-capture>" vault="<preferredVault>"
```

**If target note doesn't exist:**

For daily note:
```bash
# Create with template (if configured in Obsidian)
obsidian create path="<daily-note-path>" template="daily" vault="<preferredVault>"
# Then append the capture
obsidian daily:append content="<formatted-capture>" vault="<preferredVault>"
```

For named note (`--note`):
```bash
# Create minimal note with title
obsidian create path="<note-path>" content="# <note-title>\n\n" vault="<preferredVault>"
# Then append the capture
obsidian append path="<note-path>" content="<formatted-capture>" vault="<preferredVault>"
```

**Note:** The `append` command is safe — it only adds content. The `create` command with `overwrite` flag would replace content.

### 6. Confirm Capture

```markdown
✓ Captured to **Daily Notes/2024-01-15.md**

> This auth pattern using JWT refresh tokens works well for SPAs
```

Or for named notes:
```markdown
✓ Captured to **Architecture Decisions.md**

> Using event sourcing for audit trail
```

## Error Handling

### No Content Provided

```markdown
**Nothing to capture**

Usage: `/capture <your thought here>`

Examples:
- `/capture This approach handles edge cases better`
- `/capture --note "Ideas" New feature concept`
```

### Connection Failed

```markdown
**Obsidian connection failed**

Please verify:
1. Obsidian desktop app is running
2. Obsidian CLI is accessible (see configuration.md for path)

Your capture could not be saved. Please retry when Obsidian is available.
```

### Daily Note Path Not Configured

```markdown
**Daily note path not configured**

Please run `/daily-note` first to set up your daily note location,
or specify a target note: `/capture --note "Quick Notes" your content`
```

## Examples

**Quick thought capture:**
```
/capture The retry logic should use exponential backoff
```

**Capture to specific note:**
```
/capture --note "Meeting Notes" Discussed API versioning strategy
```

**Capture with tags:**
```
/capture --tag #bug --tag #priority Found race condition in checkout flow
```

**Capture code insight:**
```
/capture --code This pattern handles the null case elegantly
```

**Combined flags:**
```
/capture --note "Security Review" --tag #vulnerability SQL injection in search endpoint
```

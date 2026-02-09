---
name: daily-note
description: Interact with today's Obsidian daily note - retrieve, create, or append content.
argument-hint: "[create | add <text> | --date YYYY-MM-DD]"
allowed-tools: mcp__obsidian__get_file_contents, mcp__obsidian__patch_content, mcp__obsidian__append_content, mcp__obsidian__list_files_in_dir, Read, Write, AskUserQuestion
---

# Daily Note Command

Interact with your Obsidian daily note for journaling, task tracking, and session logging.

## Usage

```
/daily-note                          # Retrieve today's note
/daily-note create                   # Create today's note
/daily-note add "Meeting notes..."   # Append to today's note
/daily-note --date 2024-01-15        # Access a specific date
```

## Arguments

| Argument | Description |
|----------|-------------|
| (none) | Retrieve and display today's daily note |
| `create` | Create today's daily note (won't overwrite if one already exists) |
| `add <text>` | Append text to today's daily note |
| `--date YYYY-MM-DD` | Target a specific date instead of today |

## Configuration

This command uses daily note settings from `${CLAUDE_PLUGIN_ROOT}/config.json`:

```json
{
  "obsidian": {
    "daily_note_path": "Daily Notes/{{date:YYYY-MM-DD}}.md",
    "daily_note_template": null
  }
}
```

**If config is missing**, prompt the user on first use:

> "I need to know where your daily notes are stored. What's your daily note path pattern (using `{{date:...}}` token)?"
>
> Common patterns:
> - `Daily Notes/{{date:YYYY-MM-DD}}.md`
> - `Journal/{{date:YYYY-MM-DD}}.md`
> - `{{date:YYYY/MM-MMMM/YYYY-MM-DD}}.md`

Save their preference to config for future use.

## Execution Steps

### 1. Parse Arguments

Extract the operation and any flags:
- No args → `retrieve`
- `create` → `create`
- `add <text>` → `append` with content
- `--date YYYY-MM-DD` → override target date

### 2. Load Configuration

Read `${CLAUDE_PLUGIN_ROOT}/config.json` for daily note path pattern.

If missing or no `obsidian.daily_note_path`:
1. Use `mcp__obsidian__list_files_in_dir` to discover structure
2. Look for common patterns: `Daily Notes/`, `Journal/`, dated folders
3. Ask user to confirm or specify pattern
4. Save to config

### 3. Construct Note Path

Replace `{{date:YYYY-MM-DD}}` (or similar) in path pattern with target date.

**Target date:**
- Default: today in `YYYY-MM-DD` format
- Override: value from `--date` flag

**Example:**
- Pattern: `Daily Notes/{{date:YYYY-MM-DD}}.md`
- Date: `2024-01-15`
- Result: `Daily Notes/2024-01-15.md`

### 4. Execute Operation

#### Retrieve (default)

```
1. Use mcp__obsidian__get_file_contents with constructed path
2. If found: Display contents with clear formatting
3. If not found: Inform user and offer to create
```

**Output format:**
```markdown
## Daily Note: 2024-01-15

[note contents here]

---
_Path: Daily Notes/2024-01-15.md_
```

#### Create

```
1. Check if note already exists using mcp__obsidian__get_file_contents
2. If exists: Inform user and offer to append instead
3. If not exists:
   a. Build initial content with date header
   b. Use mcp__obsidian__patch_content to create
   c. Confirm creation
```

**Default template:**
```markdown
# {{date:YYYY-MM-DD}}

## Tasks

- [ ]

## Notes

```

#### Append

```
1. Verify note exists (create if needed, with user confirmation)
2. Format content to append:
   - Add blank line separator
   - Add timestamp header: ## HH:MM
   - Add the user's content
3. Use mcp__obsidian__append_content
4. Confirm success
```

**Append format:**
```markdown

## 14:30

Meeting notes from standup...
```

## Error Handling

### Connection Failed

```markdown
**Obsidian connection failed**

Please verify:
1. Obsidian is running with Local REST API plugin enabled
2. `OBSIDIAN_API_KEY` environment variable is set
3. Port 27124 is accessible

See the Obsidian skill documentation for setup instructions.
```

### Note Not Found (on retrieve)

```markdown
**Daily note not found:** `Daily Notes/2024-01-15.md`

Would you like me to create it?
```

### Note Already Exists (on create)

```markdown
**Daily note already exists:** `Daily Notes/2024-01-15.md`

Would you like me to:
- Show the existing note
- Append content to it instead
```

## Examples

**Retrieve today's note:**
```
/daily-note
```

**Create today's note:**
```
/daily-note create
```

**Add content:**
```
/daily-note add "Discovered that JWT refresh tokens need a 15-minute window"
```

**Check yesterday:**
```
/daily-note --date 2024-01-14
```

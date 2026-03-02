---
name: daily-note
description: Interact with today's Obsidian daily note - retrieve, create, or append content.
argument-hint: "[create | add <text> | --date YYYY-MM-DD]"
allowed-tools: Bash, Read, Write, AskUserQuestion
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

This command uses the Obsidian CLI to interact with daily notes. Configuration is stored in `${CLAUDE_PLUGIN_ROOT}/config.json`:

```json
{
  "obsidian": {
    "preferredVault": "My Vault"
  }
}
```

**On first use**, if vault preference is not set:
1. Use `obsidian vaults` to list available vaults
2. Prompt user to select a vault
3. Store selection in config.json

The daily note path is automatically detected using `obsidian daily:path vault="<vault-name>"`.

Save their preference to config for future use.

## Execution Steps

### 1. Parse Arguments

Extract the operation and any flags:
- No args → `retrieve`
- `create` → `create`
- `add <text>` → `append` with content
- `--date YYYY-MM-DD` → override target date

### 2. Load Configuration

Read `${CLAUDE_PLUGIN_ROOT}/config.json` for preferred vault.

If missing or no `obsidian.preferredVault`:
1. Use `obsidian vaults` CLI command to list available vaults
2. Ask user to select their vault
3. Save to config.json under `obsidian.preferredVault`

### 3. Determine Daily Note Path

Use the Obsidian CLI to get the daily note path:

```bash
# Get the configured daily note path from Obsidian
obsidian daily:path vault="<preferredVault>"
```

This returns the path pattern configured in Obsidian's daily notes settings.

**For specific dates:**
- The `daily:path` command returns today's path
- For custom dates, construct path manually if needed, or use date-specific CLI features

### 4. Execute Operation

#### Retrieve (default)

```bash
# Read daily note contents
obsidian daily:read vault="<preferredVault>"
```

If found: Display contents with clear formatting
If not found: Inform user and offer to create

**Output format:**
```markdown
## Daily Note: 2024-01-15

[note contents here]

---
_Path: Daily Notes/2024-01-15.md_
```

#### Create

```bash
# Check if note exists first
obsidian daily:read vault="<preferredVault>" 2>/dev/null

# If exists: Inform user and offer to append instead
# If not exists: Create with template (if configured in Obsidian) or default content
obsidian create path="<daily-note-path>" template="daily" vault="<preferredVault>"

# Or create with default content:
obsidian create path="<daily-note-path>" content="# $(date +%Y-%m-%d)\n\n## Tasks\n\n- [ ] \n\n## Notes\n\n" vault="<preferredVault>"
```

#### Append

```bash
# Verify note exists (read command will fail if it doesn't)
# Create if needed, with user confirmation

# Format content with timestamp and append
timestamp=$(date +%H:%M)
obsidian daily:append content="\n\n## [$timestamp]\n\n<user-content>" vault="<preferredVault>"
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
1. Obsidian desktop app is running
2. Obsidian CLI is accessible (see configuration.md for path)
3. At least one vault is configured

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

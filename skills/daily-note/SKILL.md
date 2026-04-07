---
name: Daily Note
description: |
  This skill should be used when the user asks to "show my daily note", "open daily note", "check daily note", "create daily note", "create today's note", "view today's note", "add to daily note", "append to daily note", "what's in my daily note", or wants to interact with today's (or a specific date's) Obsidian daily note.
version: 1.0.0
---

# Daily Note Skill

Interact with your Obsidian daily note for journaling, task tracking, and session logging.

## Operations

| Request | Action |
|---------|--------|
| "show today's daily note" | Retrieve and display today's daily note |
| "create today's daily note" | Create today's daily note |
| "add 'content' to my daily note" | Append content to today's daily note |
| "check daily note for 2024-01-15" | Access a specific date's note |

## Read vs Write Operations

| Type | Operations | Behavior |
|------|------------|----------|
| **Read** | Read daily note contents | Automatic — no confirmation needed |
| **Write** | Append/prepend content, create note | Automatic for append/prepend; confirm before overwriting |
| **Destructive** | Overwrite existing content | Requires explicit user confirmation — see below |

## Destructive Operation Confirmation Prompts

| Operation | Confirmation Prompt |
|-----------|---------------------|
| Overwrite existing daily note content | "This will overwrite the existing content of the daily note for <date>. Are you sure? (yes/no)" |

## Prerequisites

### Obsidian Application

The Obsidian desktop application must be installed and running. The CLI is included with Obsidian (v1.5.0+).

**CLI Location by Platform:**

| Platform | CLI Path |
|----------|----------|
| macOS | `/Applications/Obsidian.app/Contents/MacOS/obsidian` |
| Linux | `/usr/bin/obsidian` or `/opt/Obsidian/obsidian` |
| Windows | `C:\Users\<username>\AppData\Local\Obsidian\obsidian.exe` |

For convenience, add an alias to your shell profile:

```bash
alias obsidian="/Applications/Obsidian.app/Contents/MacOS/obsidian"
```

### Vault Setup

You need an active Obsidian vault. Use `obsidian vaults` to list available vaults.

## AGENT.md Support

On first vault interaction, check for an `AGENT.md` file at the vault root and read it if present. This file describes the user's vault conventions (folder structure, daily note patterns, tagging taxonomy, etc.) — similar to how `CLAUDE.md` works for codebases. Don't prompt users to create one; just use it if present.

## CLI Command Reference

All commands follow the pattern:
```bash
obsidian vault=<vault-name> <command> [options]
```

| Command | Purpose | Key Options |
|---------|---------|-------------|
| `daily:read` | Read today's daily note | — |
| `daily:append` | Append to daily note | `content=<text>`, `inline` |
| `daily:prepend` | Prepend to daily note | `content=<text>`, `inline` |
| `daily:path` | Get today's daily note path | — |
| `create` | Create a new note | `path=<path>`, `content=<text>`, `template=<name>` |
| `vaults` | List available vaults | `verbose` |

**Notes:**
- Quote values with spaces: `content="My content here"`
- Use `\n` for newlines in content values

## Configuration

Store the user's preferred vault in `${CLAUDE_PLUGIN_ROOT}/config.json`:

```json
{
  "obsidian": {
    "preferredVault": "My Vault"
  }
}
```

**On first use**, if `obsidian.preferredVault` is not set:
1. Run `obsidian vaults verbose` to list available vaults
2. Prompt user to select one
3. Before writing, ask for explicit confirmation:
   > `I can remember your preferred Obsidian vault ("<vault-name>") for next time by saving it to config.json. Do you want me to save this preference? (yes/no)`
4. If confirmed, save selection to config.json; otherwise use the selected vault for this request only

**Daily note path detection:**
On first daily note interaction, run `obsidian vault="<preferredVault>" daily:path` to get the concrete path (e.g., `Daily Notes/2024-01-15.md`). Infer the folder/naming convention from this path for custom date operations.

## Execution Steps

### 1. Load Configuration

Read `${CLAUDE_PLUGIN_ROOT}/config.json` for preferred vault. If missing, follow the first-use flow above.

### 2. Determine Target Date

- Default: today (use `daily:path` / `daily:read` directly)
- With specific date: infer path pattern from `daily:path` and substitute the target date

### 3. Execute Operation

#### Retrieve (default)

```bash
obsidian vault="<preferredVault>" daily:read
```

Display contents with clear formatting. If note doesn't exist, offer to create it.

**Output format:**
```markdown
## Daily Note: 2024-01-15

[note contents]

---
_Path: Daily Notes/2024-01-15.md_
```

#### Create

```bash
# Check if note already exists
obsidian vault="<preferredVault>" daily:read 2>/dev/null

# If exists: inform user, offer to show or append instead
# If not exists: create with template (if configured) or default content
obsidian vault="<preferredVault>" create path="<daily-note-path>" template="daily"

# Or with default content:
obsidian vault="<preferredVault>" create path="<daily-note-path>" content="# $(date +%Y-%m-%d)\n\n## Tasks\n\n- [ ] \n\n## Notes\n\n"
```

#### Append

```bash
timestamp=$(date +%H:%M)
obsidian vault="<preferredVault>" daily:append content="\n\n## [$timestamp]\n\n<user-content>"
```

**Append format:**
```markdown

## 14:30

Meeting notes from standup...
```

## Error Handling

### CLI Not Found

```markdown
**Obsidian CLI not found**

Please verify:
1. Obsidian desktop app is installed (v1.5.0+)
2. On macOS, CLI is at: `/Applications/Obsidian.app/Contents/MacOS/obsidian`
3. Consider adding an alias: `alias obsidian="/Applications/Obsidian.app/Contents/MacOS/obsidian"`
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

## Platform Compatibility

Detect platform and use the appropriate CLI path:

```bash
if [[ "$OSTYPE" == "darwin"* ]]; then
  OBSIDIAN_CLI="/Applications/Obsidian.app/Contents/MacOS/obsidian"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  OBSIDIAN_CLI="obsidian"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
  OBSIDIAN_CLI="obsidian.exe"
fi
```

## Additional Resources

- **In-repo reference:** See [skills/references/cli-commands.md](../references/cli-commands.md) for comprehensive CLI documentation
- **Built-in help:** Run `obsidian help` or `obsidian help <command>`

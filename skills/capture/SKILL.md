---
name: capture
description: |
  This skill should be used when the user asks to "capture this", "save this to obsidian", "add to obsidian", "quick capture", "capture to vault", "capture this thought", "capture this insight", "capture this code", "save this insight", "jot this down", or wants to save a thought, snippet, or note to Obsidian without interrupting their workflow.
version: 1.1.0
---

# Capture Skill

Quick capture of thoughts, code snippets, and insights to Obsidian without leaving the coding flow. Designed for minimal friction.

## Operations

| Request | Action |
|---------|--------|
| "capture this thought" | Append to daily note (default) |
| "save this to my 'Note Name' note" | Create/append to specific note |
| "capture this with tag #tag" | Capture with tags |
| "capture the current code context" | Capture with code context |

## Read vs Write Operations

| Type | Operations | Behavior |
|------|------------|----------|
| **Write** | Append to existing note | Automatic — no confirmation needed |
| **Write** | Create new note | Automatic when target doesn't exist |
| **Destructive** | Overwrite existing content | Requires explicit user confirmation — see below |

## Destructive Operation Confirmation Prompts

| Operation | Confirmation Prompt |
|-----------|---------------------|
| Overwrite existing note content | "This will overwrite the existing content of '<note-name>'. Are you sure? (yes/no)" |

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

On first vault interaction, check for an `AGENT.md` file at the vault root and read it if present. This file describes the user's vault conventions (folder structure, capture preferences, tagging taxonomy, etc.) — similar to how `CLAUDE.md` works for codebases. Don't prompt users to create one; just use it if present.

## CLI Command Reference

All commands follow the pattern:
```bash
obsidian vault=<vault-name> <command> [options]
```

| Command | Purpose | Key Options |
|---------|---------|-------------|
| `daily:append` | Append to daily note (creates with template if missing) | `content=<text>`, `inline` |
| `append` | Append to a specific note (file must exist) | `path=<path>`, `content=<text>`, `inline` |
| `create` | Create a new note with content | `path=<path>`, `content=<text>` |
| `read` | Check if a named note exists | `path=<path>` |
| `vaults` | List available vaults | `verbose` |

**Notes:**
- Quote values with spaces: `content="My content here"`
- Use `\n` for newlines in content values
- Use escaped backticks (\`) for code fences in content values

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

## Execution Steps

### 1. Parse the Request

Extract from user input:
- `text`: The content to capture
- `--note <name>`: Optional target note (otherwise defaults to daily note)
- `--tag #tag`: Optional tags (can be multiple)
- `--code`: Flag to include code context

### 2. Load Configuration

Read `${CLAUDE_PLUGIN_ROOT}/config.json` for preferred vault. If missing, follow the first-use flow above.

### 3. Determine Target Note

**If `--note` specified:**
- Without `/`: target is `Captures/<note-name>.md`
- With `/`: treat as subpath — `Captures/<note-name>.md`
  - Example: `--note "Projects/Auth"` → `Captures/Projects/Auth.md`

**Default:** Today's daily note.

### 4. Build Capture Content

Format the entry consistently:

```markdown

## [HH:MM] - Capture

[content]

**Tags:** #tag1 #tag2
**Context:** ProjectName
```

**For code captures (`--code`):**

````markdown

## [HH:MM] - Code Capture

[text content]

**File:** `src/auth/middleware.ts`
```typescript
// relevant code snippet
```

**Context:** ProjectName
````

### 5. Append to Target

**Daily note target** — `daily:append` creates the note if it doesn't exist, so no existence check is needed:

```bash
obsidian vault="<preferredVault>" daily:append content="<formatted-capture>"
```

**Named note target** — `append` requires the file to exist, so check first:

```bash
if obsidian vault="<preferredVault>" read path="<note-path>" >/dev/null 2>&1; then
  # Note exists — append
  obsidian vault="<preferredVault>" append path="<note-path>" content="<formatted-capture>"
else
  # Note doesn't exist — create with full content (header + capture entry)
  obsidian vault="<preferredVault>" create path="<note-path>" content="# <note-title>\n\n<formatted-capture>"
fi
```

### 6. Confirm Capture

```markdown
✓ Captured to **Daily Notes/2024-01-15.md**

> This auth pattern using JWT refresh tokens works well for SPAs
```

## Error Handling

### No Content Provided

```markdown
**Nothing to capture**

Try asking in natural language, for example:
- "Capture this thought: this approach handles edge cases better"
- "Save this to my 'Ideas' note: new feature concept"
```

### CLI Not Found

```markdown
**Obsidian CLI not found**

Please verify:
1. Obsidian desktop app is installed (v1.5.0+)
2. On macOS, CLI is at: `/Applications/Obsidian.app/Contents/MacOS/obsidian`
3. Consider adding an alias: `alias obsidian="/Applications/Obsidian.app/Contents/MacOS/obsidian"`
```

### Connection Failed

```markdown
**Obsidian connection failed**

Your capture could not be saved. Please verify Obsidian is running and retry.
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

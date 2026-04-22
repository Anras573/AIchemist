---
name: daily-note
description: |
  This skill should be used when the user asks to "show my daily note", "open daily note", "check daily note", "create daily note", "create today's note", "view today's note", "add to daily note", "append to daily note", "what's in my daily note", or wants to interact with today's (or a specific date's) Obsidian daily note.
version: 1.1.0
---

# Daily Note Skill

Interact with your Obsidian daily note for journaling, task tracking, and session logging.

## How daily note commands work

`daily:read` and `daily:append` both **automatically create today's daily note** (using the user's configured template) if it does not yet exist. There is no need to check for existence or create the note manually — just run the command.

## Operations

| Request | Action |
|---------|--------|
| "show today's daily note" / "create today's daily note" | `daily:read` — creates with template if needed, reads if it exists |
| "add 'content' to my daily note" | `daily:append` — creates with template if needed, then appends |
| "check daily note for 2024-01-15" | Infer path pattern from `daily:path`, substitute date, use `read path=` |

## Safety Rules

| Type | Operations | Behavior |
|------|------------|----------|
| **Read** | Read daily note contents | Automatic — no confirmation needed |
| **Write** | Append/prepend content | Automatic — no confirmation needed |
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
| `daily:read` | Read today's note (creates with template if missing) | — |
| `daily:append` | Append to today's note (creates with template if missing) | `content=<text>`, `inline` |
| `daily:prepend` | Prepend to today's note (creates with template if missing) | `content=<text>`, `inline` |
| `daily:path` | Get today's daily note path (use to infer date pattern) | — |
| `read` | Read a file by exact path (used for specific dates) | `path=<path>` |
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

## Execution Steps

### 1. Load Configuration

Read `${CLAUDE_PLUGIN_ROOT}/config.json` for preferred vault. If missing, follow the first-use flow above.

### 2. Determine Target Date

- **Today** (default): use `daily:read` or `daily:append` directly — no path needed
- **Specific date**: run `daily:path` to get today's path, infer the folder/filename pattern, substitute the target date

**Example:** if `daily:path` returns `Daily Notes/2026-04-21.md`, the pattern is `Daily Notes/YYYY-MM-DD.md`. For April 10th: `Daily Notes/2026-04-10.md`.

### 3. Execute Operation

#### Read / Create today's note

`daily:read` creates the note with the user's configured template if it doesn't exist, then returns the contents. No existence check needed.

```bash
obsidian vault="<preferredVault>" daily:read
```

**Output format:**
```markdown
## Daily Note: 2026-04-21

[note contents]

---
_Path: Daily Notes/2026-04-21.md_
```

#### Append to today's note

`daily:append` also creates the note with the user's configured template if it doesn't exist. No existence check needed.

**Content safety:** Do not interpolate user-supplied content directly into the shell `content="..."` argument — special characters (`"`, `$`, `` ` ``, `\`) will break shell quoting or allow command injection. Write the content to a temp file first:

```bash
timestamp=$(date +%H:%M)
TMPFILE=$(mktemp /tmp/daily-append.XXXXXX)
printf '\n\n## [%s]\n\n%s' "$timestamp" "<user-content>" > "$TMPFILE"
obsidian vault="$preferredVault" daily:append content="$(cat "$TMPFILE")"
rm -f "$TMPFILE"
```

**Append format:**
```markdown

## 14:30

Meeting notes from standup...
```

#### Read a specific date's note

```bash
# 1. Get today's path to infer the naming pattern
obsidian vault="<preferredVault>" daily:path

# 2. Substitute the target date into the pattern and read
obsidian vault="<preferredVault>" read path="<inferred-path>"
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

## Platform Compatibility

Detect platform and use the appropriate CLI path:

```bash
if [[ "$OSTYPE" == "darwin"* ]]; then
  OBSIDIAN_CLI="/Applications/Obsidian.app/Contents/MacOS/obsidian"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  OBSIDIAN_CLI="obsidian"
elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* ]]; then
  OBSIDIAN_CLI="obsidian.exe"
fi
```

## Additional Resources

- **In-repo reference:** See [skills/references/cli-commands.md](../references/cli-commands.md) for comprehensive CLI documentation
- **Built-in help:** Run `obsidian help` or `obsidian help <command>`

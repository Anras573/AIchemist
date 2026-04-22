---
name: obsidian
description: |
  Use for general Obsidian vault management: tasks ("list my tasks", "mark task done", "show incomplete tasks"), tags ("list tags", "find notes tagged #auth"), properties/frontmatter ("set status to done", "read the status property"), file operations ("move this note", "rename this file", "delete this note"), templates ("list templates", "read template"), and links ("show backlinks", "find orphaned notes"). Do NOT use for daily notes, quick capture, or vault search — those are handled by the daily-note, capture, and research skills.
version: 1.0.0
---

# Obsidian Skill

General-purpose Obsidian vault management via the CLI. Covers task tracking, tag operations, file management, properties, templates, and link analysis.

## Operations

| Request | Command category |
|---------|-----------------|
| "list my tasks", "show incomplete tasks", "mark task done" | Task management |
| "list all tags", "find notes tagged #auth" | Tag operations |
| "set the status property to done", "read frontmatter" | Properties |
| "move this note to Archive", "rename this file" | File operations |
| "list templates", "read my daily template" | Templates |
| "show backlinks for this note", "find orphaned notes" | Link analysis |

## Safety Rules

| Type | Operations | Behavior |
|------|------------|----------|
| **Read** | List tasks/tags/links, read properties, read templates | Automatic — no confirmation needed |
| **Write** | Toggle task status | Requires explicit user confirmation |
| **Write** | Set or remove properties | Requires explicit user confirmation |
| **Destructive** | Delete notes, permanently remove properties | Requires explicit user confirmation |

## Confirmation Prompts

Show the prompt, then **stop and wait for the user's reply before proceeding**. Do not assume, infer, or supply the answer yourself.

| Operation | Confirmation Prompt |
|-----------|---------------------|
| Toggle a task | "Toggle task: '<task-text>'? (yes/no)" |
| Set a property | "Set property '<name>' to '<value>' on '<note-name>'? (yes/no)" |
| Remove a property | "Remove property '<name>' from '<note-name>'? (yes/no)" |
| Delete a note | "This will delete '<note-name>'. Are you sure? (yes/no)" |
| Permanently delete (skip trash) | "This will permanently delete '<note-name>' and cannot be undone. Are you sure? (yes/no)" |

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

On first vault interaction, check for an `AGENT.md` file at the vault root and read it if present. This file describes the user's vault conventions (folder structure, tagging taxonomy, note types, etc.) — similar to how `CLAUDE.md` works for codebases. Don't prompt users to create one; just use it if present.

## CLI Command Reference

All commands follow the pattern:
```bash
obsidian vault=<vault-name> <command> [options]
```

| Command | Purpose | Key Options |
|---------|---------|-------------|
| `tasks` | List tasks — defaults to vault-wide | `daily`, `path=<path>`, `todo`, `done`, `status="<char>"`, `total`, `format=json` |
| `task` | Update a single task | `ref=<path:line>`, `toggle`, `done`, `todo`, `status="<char>"` |
| `tags` | List tags in the vault | `counts`, `sort=count`, `format=json` |
| `tag` | Get info for a specific tag | `name=<tag>`, `verbose` |
| `properties` | List properties in the vault | `path=<path>`, `format=json` |
| `property:read` | Read a property from a file | `name=<name>`, `path=<path>` |
| `property:set` | Set a property on a file | `name=<name>`, `value=<value>`, `type=<type>`, `path=<path>` |
| `property:remove` | Remove a property from a file | `name=<name>`, `path=<path>` |
| `move` | Move or rename a file | `path=<path>`, `to=<dest>` |
| `rename` | Rename a file | `path=<path>`, `name=<new-name>` |
| `delete` | Delete a file | `path=<path>`, `permanent` |
| `template:read` | Read a template | `name=<template>`, `resolve` |
| `templates` | List available templates | — |
| `links` | List outgoing links from a file | `path=<path>`, `total` |
| `backlinks` | List backlinks to a file | `path=<path>`, `format=json` |
| `orphans` | List files with no incoming links | `total` |
| `files` | List files in the vault or a folder | `folder=<path>`, `ext=<ext>` |
| `vaults` | List available vaults | `verbose` |

**Notes:**
- Use `format=json` for programmatic parsing of results
- `path=<path>` uses exact file path; `file=<name>` resolves by name (wikilink-style)
- Quote values with spaces: `content="My content here"`

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

**Vault name safety:** Always wrap the vault name in double quotes when interpolating into shell commands: `vault="<preferredVault>"`. If the vault name contains double quotes or other shell metacharacters (`$`, `` ` ``, `\`), refuse to proceed and ask the user to rename the vault.

## Execution Steps

### 1. Load Configuration

Read `${CLAUDE_PLUGIN_ROOT}/config.json` for preferred vault. If missing, follow the first-use flow above.

### 2. Execute Operation

#### Task Management

Tasks default to the daily note unless the user specifies a file or asks for vault-wide results.

**Listing tasks**

Use `format=json` internally to get file + line numbers for toggling. Present results as plain text to the user.

```bash
# Incomplete tasks from today's daily note (default)
obsidian vault="<preferredVault>" tasks daily todo format=json

# All tasks from today's daily note (done + todo)
obsidian vault="<preferredVault>" tasks daily format=json

# Tasks from a specific note
obsidian vault="<preferredVault>" tasks path="<note-path>" todo format=json

# Vault-wide incomplete tasks
obsidian vault="<preferredVault>" tasks todo format=json
```

**Present results as numbered plain text** so the user can reference them by number when toggling:

```markdown
**Tasks — Daily Note (2026-04-22)**

1. [ ] Implement JWT refresh  ← Projects/API.md:15
2. [ ] Write tests for auth middleware  ← Projects/API.md:22
3. [x] Update README  ← Daily Notes/2026-04-22.md:8
```

Retain the file and line internally for each numbered item to use in toggle commands.

**Toggling and updating tasks**

Use `ref=<path:line>` — constructed from the JSON output above — for precise targeting:

```bash
# Toggle a task (done → todo or todo → done)
obsidian vault="<preferredVault>" task ref="<file>:<line>" toggle

# Explicitly mark done
obsidian vault="<preferredVault>" task ref="<file>:<line>" done

# Explicitly mark todo
obsidian vault="<preferredVault>" task ref="<file>:<line>" todo

# Set a custom status character (e.g. > for deferred, - for cancelled)
obsidian vault="<preferredVault>" task ref="<file>:<line>" status=">"
```

Check the exit code and report accordingly:

```bash
if obsidian vault="<preferredVault>" task ref="<file>:<line>" toggle; then
  echo "✓ Task toggled."
else
  echo "✗ Toggle failed — check that Obsidian is running and the ref is valid."
fi
```

**Filtering by status character**

Obsidian supports custom task statuses beyond `[ ]` and `[x]`. Use `status=` to filter:

```bash
# Show deferred tasks ( [>] )
obsidian vault="<preferredVault>" tasks daily status=">" format=json

# Show cancelled tasks ( [-] )
obsidian vault="<preferredVault>" tasks daily status="-" format=json
```

**Counting tasks**

```bash
# Count incomplete tasks in daily note
obsidian vault="<preferredVault>" tasks daily todo total
```

#### Tag Operations

```bash
# List all tags with occurrence counts
obsidian vault="<preferredVault>" tags counts sort=count format=json

# Find all notes with a specific tag
obsidian vault="<preferredVault>" tag name="#auth" verbose
```

Present tags sorted by count. For tag lookups, list the matching files with modification dates.

#### Properties

```bash
# Read a property from a specific note
obsidian vault="<preferredVault>" property:read name="status" path="<note-path>"

# Set a property
obsidian vault="<preferredVault>" property:set name="status" value="done" type=text path="<note-path>"

# Remove a property
obsidian vault="<preferredVault>" property:remove name="draft" path="<note-path>"
```

#### File Operations

```bash
# Move a note
obsidian vault="<preferredVault>" move path="<source-path>" to="<dest-path>"

# Rename a note
obsidian vault="<preferredVault>" rename path="<note-path>" name="<new-name>"

# Delete a note (to trash)
obsidian vault="<preferredVault>" delete path="<note-path>"

# Delete permanently (requires confirmation first)
obsidian vault="<preferredVault>" delete path="<note-path>" permanent
```

#### Templates

```bash
# List available templates
obsidian vault="<preferredVault>" templates

# Read a template (with variables resolved)
obsidian vault="<preferredVault>" template:read name="<template-name>" resolve
```

#### Link Analysis

```bash
# Show backlinks to a note
obsidian vault="<preferredVault>" backlinks path="<note-path>" format=json

# Find orphaned notes (no incoming links)
obsidian vault="<preferredVault>" orphans
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

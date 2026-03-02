---
name: Obsidian Knowledge Management
description: |
  This skill should be used when the user asks to "capture to obsidian", "add to daily note", "research in vault", "search my notes", "save this insight", "query obsidian", "check daily note", "create daily note", "append to daily note", "find in obsidian", "look up notes", or mentions Obsidian-related knowledge management tasks. Provides three capabilities: daily notes, quick capture, and vault research.
version: 2.0.0
---

# Obsidian Knowledge Management Skill

This skill integrates Claude Code with Obsidian for knowledge management workflows during coding sessions using the Obsidian CLI. It provides three core capabilities:

1. **Daily Note** (`/daily-note`) - Interact with today's daily note
2. **Capture** (`/capture`) - Quick capture of thoughts, code snippets, or insights
3. **Research** (`/research`) - Search vault for relevant context

## Read vs Write Operations

| Type | Operations | Behavior |
|------|------------|----------|
| **Read** | Search, list files, read file contents | Automatic — no confirmation needed |
| **Write** | Append/prepend content, create notes | Automatic for append/prepend; confirm before overwriting |
| **Destructive** | Delete notes, overwrite existing content | **Requires explicit user confirmation** |

**Safety Rules:**
- `append` and `prepend` commands are safe — they only add to existing notes
- `create` with `overwrite` flag overwrites — confirm before using on existing notes
- `delete` is destructive — always confirm before deletion
- Never delete notes without explicit user request

## Prerequisites

### Obsidian Application

The Obsidian desktop application must be installed and running. The CLI is included with Obsidian (v1.5.0+).

**Installation:**
- Download from [obsidian.md](https://obsidian.md)
- Available for macOS, Linux, and Windows

**CLI Location by Platform:**

| Platform | CLI Path |
|----------|----------|
| macOS | `/Applications/Obsidian.app/Contents/MacOS/obsidian` |
| Linux | `/usr/bin/obsidian` or `/opt/Obsidian/obsidian` |
| Windows | `C:\Users\<username>\AppData\Local\Obsidian\obsidian.exe` |

### Vault Setup

You need an active Obsidian vault. The CLI can work with multiple vaults using the `vault=<name>` parameter.

**To list available vaults:**
```bash
# Use the CLI path for your platform
obsidian vaults
```

### Environment Setup (Optional)

For convenience, you can add an alias to your shell profile:

```bash
# Add to ~/.zshrc or ~/.bashrc
alias obsidian="/Applications/Obsidian.app/Contents/MacOS/obsidian"
```

### First-Run Check

On first use, verify prerequisites:

1. Check if Obsidian CLI is available
2. List vaults to verify connectivity
3. **Check for AGENT.md** at the vault root and read it if present

If connection fails, provide setup guidance.

## AGENT.md Support

If an `AGENT.md` file exists at the vault root, read it on first interaction to understand the user's vault conventions. This file provides context similar to how `CLAUDE.md` works for codebases.

### Reading AGENT.md

```
1. On first vault interaction, use the read command to get AGENT.md contents
2. If found, incorporate the context into your understanding of the vault
3. If not found, proceed normally (it's optional)
4. Don't prompt users to create one - just use it if present
```

### What AGENT.md Typically Contains

- **Folder structure** - What each top-level folder is for
- **Daily note conventions** - Path pattern, template structure
- **Tagging taxonomy** - What tags mean, hierarchies used
- **Note types** - MOCs, atomic notes, project notes, etc.
- **Linking conventions** - When to use `[[wikilinks]]` vs tags
- **Capture preferences** - Where quick captures should go

## CLI Command Reference

All commands follow the pattern:
```bash
obsidian <command> [options] vault=<vault-name>
```

(See platform-specific CLI paths in the Prerequisites section above.)

### Essential Commands for This Skill

| Command | Purpose | Key Options |
|---------|---------|-------------|
| `read` | Read file contents | `file=<name>` or `path=<path>` |
| `create` | Create new file | `path=<path>`, `content=<text>`, `template=<name>` |
| `append` | Append to file | `path=<path>`, `content=<text>`, `inline` |
| `prepend` | Prepend to file | `path=<path>`, `content=<text>`, `inline` |
| `search` | Search vault | `query=<text>`, `format=json`, `limit=<n>` |
| `search:context` | Search with context | `query=<text>`, `format=json` |
| `files` | List files | `folder=<path>`, `ext=<extension>`, `total` |
| `folders` | List folders | `folder=<path>`, `total` |
| `daily:read` | Read daily note | None |
| `daily:append` | Append to daily note | `content=<text>`, `inline` |
| `daily:prepend` | Prepend to daily note | `content=<text>`, `inline` |
| `daily:path` | Get daily note path | None |
| `delete` | Delete file | `path=<path>`, `permanent` |
| `vault` | Get vault info | `info=name\|path\|files\|folders\|size` |
| `vaults` | List vaults | `verbose` |

### Important Notes

- Use `path=<path>` for exact file paths (e.g., `path="Folder/Note.md"`)
- Use `file=<name>` for name-based resolution (like wikilinks)
- Quote values with spaces: `content="My content here"`
- Use `\n` for newlines in content values
- Default vault is used unless `vault=<name>` is specified
- Most commands default to the active file when file/path is omitted

## Daily Note Capability

### Overview

Interact with today's daily note for journaling, task tracking, and session logging.

### Operations

| Command | Action |
|---------|--------|
| `/daily-note` | Retrieve and display today's daily note |
| `/daily-note create` | Create today's daily note |
| `/daily-note add "content"` | Append content to today's daily note |
| `/daily-note --date 2024-01-15` | Access a specific date's note |

### Daily Note Path Convention

Daily notes are typically stored in one of these locations:
- `Daily Notes/YYYY-MM-DD.md`
- `Journal/YYYY-MM-DD.md`
- `YYYY/MM-MMMM/YYYY-MM-DD.md`

**On first use**, run `daily:path` to get the concrete path to today's daily note and, if needed, infer the folder/filename convention from that path. If daily notes are not configured, ask the user for their preferred location and naming.

### Workflow: Retrieve Daily Note

```bash
# Get daily note path
obsidian daily:path vault="My Vault"

# Read daily note contents
obsidian daily:read vault="My Vault"
```

Display contents with clear formatting. If note doesn't exist, offer to create it.

### Workflow: Create Daily Note

```bash
# Check if daily note exists first
obsidian daily:path vault="My Vault"

# Create daily note with template (if configured)
obsidian create path="Daily Notes/2024-01-15.md" template="daily" vault="My Vault"

# Or create with initial content
obsidian create path="Daily Notes/2024-01-15.md" content="# 2024-01-15\n\n## Today's Focus\n\n" vault="My Vault"
```

### Workflow: Append to Daily Note

```bash
# Append content with newlines
obsidian daily:append content="## 14:30 - Code Review Notes\n\nFound issue with token refresh logic..." vault="My Vault"

# Inline append (no newline)
obsidian daily:append content=" - Additional task" inline vault="My Vault"
```

## Capture Capability

### Overview

Quick capture of thoughts, code snippets, and insights to Obsidian without leaving the coding flow.

### Operations

| Command | Action |
|---------|--------|
| `/capture This is my thought` | Append to daily note (default) |
| `/capture --note "Note Name" content` | Create/append to specific note |
| `/capture --tag #tag content` | Capture with tags |
| `/capture --code` | Capture current code context |

### Capture Targets

**Default (Daily Note):**
- Appends to today's daily note
- Adds timestamp
- Includes project context if available

**Specific Note:**
- Creates note if doesn't exist
- Appends if exists
- Supports nested paths: `Folder/Subfolder/Note`

### Capture Format

When capturing, format entries consistently:

```markdown
## [HH:MM] Capture

> [content]

**Context:** [project/file if relevant]
**Tags:** #tag1 #tag2
```

### Workflow: Quick Capture

```bash
# Capture to daily note
timestamp=$(date +"%H:%M")
obsidian daily:append content="\n## [$timestamp] Capture\n\n> Quick thought about authentication\n\n**Tags:** #dev #auth" vault="My Vault"

# Capture to specific note
full_timestamp=$(date +'%Y-%m-%d %H:%M')
obsidian append path="Captures/Ideas.md" content="\n## $full_timestamp\n\nNew feature idea..." vault="My Vault"
```

### Workflow: Code Capture

When `--code` flag is used, format with escaped newlines for consistency:

````bash
# Format code capture and append to daily note
obsidian daily:append content="## [15:30] Code Snippet\n\n\`\`\`typescript\n// File: src/auth/middleware.ts\nexport async function validateToken(token: string) {\n  // Implementation\n}\n\`\`\`\n\n**Context:** Working on authentication middleware\n**Tags:** #code #typescript #auth" vault="My Vault"
````

**Note:** Use `\n` for newlines and escaped backticks (\`) for code fences in content values.

## Research Capability

### Overview

Search the vault for relevant context on a topic, leveraging past knowledge during coding sessions.

### Operations

| Command | Action |
|---------|--------|
| `/research authentication patterns` | Full-text search for term |
| `/research --folder Projects/ query` | Search within folder |
| `/research --limit 10 query` | Return more results |

### Search Strategy

1. **Full-text search** using `search` command
2. **Get context** using `search:context` for matching lines
3. **Filter results** by relevance
4. **Summarize findings** for quick consumption
5. **Suggest related notes** via backlinks (if available)

### Workflow: Research Query

```bash
# Simple search (returns file list with match counts)
obsidian search query="authentication patterns" format=json vault="My Vault"

# Search with context (returns matching lines)
obsidian search:context query="JWT" format=json limit=5 vault="My Vault"

# Search within folder
obsidian search query="API" path="Projects/" format=json vault="My Vault"
```

Parse JSON output to present results cleanly.

### Result Presentation

```markdown
### Research Results: "authentication patterns"

**Found 5 relevant notes:**

1. **Authentication Design** (`Architecture/Auth.md`)
   > We decided to use JWT with refresh tokens because...
   _Modified: 2024-01-10_

2. **API Security Notes** (`Projects/API/security.md`)
   > OAuth2 flow handles the authentication layer...
   _Modified: 2024-01-08_

---
Say "read 1" to see the full note, or refine your search.
```

### Reading Full Note After Research

```bash
# Read specific note from results
obsidian read path="Architecture/Auth.md" vault="My Vault"
```

## Error Handling

### CLI Not Found

If Obsidian CLI is not available:

```markdown
**Obsidian CLI not found**

Please verify:
1. Obsidian desktop app is installed (v1.5.0+)
2. On macOS, CLI is at: `/Applications/Obsidian.app/Contents/MacOS/obsidian`
3. Consider adding an alias: `alias obsidian="/Applications/Obsidian.app/Contents/MacOS/obsidian"`
```

### Vault Not Found

```markdown
**Vault not found:** "My Vault"

Available vaults:
- Personal Notes
- Work Notes

Use one of these names with the vault=<name> parameter.
```

### Note Not Found

```markdown
**Note not found:** `Daily Notes/2024-01-15.md`

Would you like me to create it?
```

### Search No Results

```markdown
**No results found** for "authentication patterns"

Suggestions:
- Try broader terms
- Check spelling
- Search in specific folder with `path=<folder>`
```

## Configuration

### Vault Selection

Store the user's preferred vault in `${CLAUDE_PLUGIN_ROOT}/config.json` under the key `obsidian.preferredVault`. On first use, if this key is not set:

1. List available vaults
2. Prompt user to select one
3. Persist the selection for future use

```bash
# List available vaults
obsidian vaults verbose

# Get vault info
obsidian vault info=name vault="My Vault"
```

Example config.json entry:
```json
{
  "obsidian": {
    "preferredVault": "My Vault"
  }
}
```

### Daily Note Detection

On first daily note interaction:

```bash
# Get today's daily note path
obsidian daily:path vault="My Vault"
```

This returns the concrete path to today's daily note (e.g., `Daily Notes/2024-01-15.md`). The folder and naming convention can be inferred from this path if needed for custom date operations.

### First-Time Setup

On first use, detect preferences:

1. Available vaults (via `vaults` command)
2. Daily note location pattern (via `daily:path`)
3. Vault structure (via `folders` command)

## Common Patterns

### Check if Note Exists

```bash
# Attempt to read the file
obsidian read path="Folder/Note.md" vault="My Vault" 2>&1

# If returns error, file doesn't exist
# If returns content, file exists
```

### Create Note if Missing

```bash
# Try to read first
content=$(obsidian read path="Folder/Note.md" vault="My Vault" 2>&1)

if [[ $? -ne 0 ]]; then
  # File doesn't exist, create it
  obsidian create path="Folder/Note.md" content="# Note Title\n\n" vault="My Vault"
else
  # File exists, append instead
  obsidian append path="Folder/Note.md" content="\n## New Section\n\n" vault="My Vault"
fi
```

### List Files in Folder

```bash
# List markdown files
obsidian files folder="Daily Notes" ext=md vault="My Vault"

# Get total count
obsidian files folder="Daily Notes" total vault="My Vault"
```

### Parse JSON Output

Some commands support `format=json` option (e.g., `search`, `tasks`, `tags`). Parse the JSON for programmatic access:

````bash
# Search with JSON output
result=$(obsidian search query="test" format=json vault="My Vault")
echo "$result" | jq -r '.[] | "\(.file): \(.matches) matches"'
````

## Platform Compatibility

The Obsidian CLI path varies by platform:

| Platform | CLI Location |
|----------|-------------|
| macOS | `/Applications/Obsidian.app/Contents/MacOS/obsidian` |
| Linux | `/usr/bin/obsidian` (or installed location) |
| Windows | `C:\Users\<username>\AppData\Local\Obsidian\obsidian.exe` |

Detect platform and use appropriate path:

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

For complete CLI documentation:

1. **In-repo reference:** See [references/cli-commands.md](references/cli-commands.md) for comprehensive command documentation with examples
2. **Built-in help:** Run `obsidian help` or `obsidian help <command>` for command-specific help

# Obsidian CLI Commands Reference

This reference documents the Obsidian CLI commands relevant to this skill. The CLI is included with Obsidian v1.5.0+.

## Command Syntax

```bash
obsidian vault=<vault-name> <command> [options]
```

**Key Points:**
- `vault=<name>` must be the **first parameter** (before the command) when targeting a specific vault
- Options use `key=value` format (e.g., `path="Note.md"`)
- Quote values with spaces: `content="My content"`
- Use `\n` for newlines, `\t` for tabs in content
- `file=<name>` resolves by name (like wikilinks)
- `path=<path>` uses exact path (e.g., `folder/note.md`)

## File Operations

### read
Read file contents.

**Options:**
- `file=<name>` - File name (wikilink-style resolution)
- `path=<path>` - Exact file path
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" read path="Daily Notes/2024-01-15.md"
```

**Returns:** File content as text

---

### create
Create a new file.

**Options:**
- `name=<name>` - File name (creates in vault root)
- `path=<path>` - Full file path including folders
- `content=<text>` - Initial content
- `template=<name>` - Template to use
- `overwrite` - Overwrite if file exists
- `open` - Open file after creating
- `newtab` - Open in new tab
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" create path="Projects/New Note.md" content="# New Note\n\nContent here"
```

**Returns:** Success confirmation

---

### append
Append content to a file.

**Options:**
- `file=<name>` - File name
- `path=<path>` - File path
- `content=<text>` - Content to append (required)
- `inline` - Append without newline
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" append path="Daily Notes/Today.md" content="\n## New Section\n\nContent"
```

**Returns:** Success confirmation

---

### prepend
Prepend content to a file.

**Options:**
- `file=<name>` - File name
- `path=<path>` - File path
- `content=<text>` - Content to prepend (required)
- `inline` - Prepend without newline
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" prepend path="TODO.md" content="- New urgent task\n"
```

**Returns:** Success confirmation

---

### delete
Delete a file.

**Options:**
- `file=<name>` - File name
- `path=<path>` - File path
- `permanent` - Skip trash, delete permanently
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" delete path="Temp/Old Note.md"
```

**Warning:** Use with caution. Requires confirmation.

---

### move
Move or rename a file.

**Options:**
- `file=<name>` - Source file name
- `path=<path>` - Source file path
- `to=<path>` - Destination folder or full path (required)
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" move path="Old Folder/Note.md" to="New Folder/Note.md"
```

---

### rename
Rename a file.

**Options:**
- `file=<name>` - Current file name
- `path=<path>` - Current file path
- `name=<name>` - New file name (required)
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" rename path="Projects/Old Name.md" name="New Name"
```

## Search Operations

### search
Search vault for text.

**Options:**
- `query=<text>` - Search query (required)
- `path=<folder>` - Limit to folder
- `limit=<n>` - Max files to return
- `total` - Return match count only
- `case` - Case sensitive search
- `format=text|json` - Output format (default: text)
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" search query="authentication" format=json limit=10
```

**JSON Output Format:**
```json
[
  {
    "file": "Architecture/Auth.md",
    "matches": 5,
    "modified": "2024-01-10T15:30:00Z"
  }
]
```

---

### search:context
Search with matching line context.

**Options:**
- `query=<text>` - Search query (required)
- `path=<folder>` - Limit to folder
- `limit=<n>` - Max files to return
- `case` - Case sensitive search
- `format=text|json` - Output format (default: text)
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" search:context query="JWT" format=json
```

**JSON Output Format:**
```json
[
  {
    "file": "Architecture/Auth.md",
    "line": 42,
    "context": "We use JWT tokens for authentication because...",
    "match": "JWT"
  }
]
```

## List Operations

### files
List files in the vault.

**Options:**
- `folder=<path>` - Filter by folder
- `ext=<extension>` - Filter by extension (e.g., `md`, `pdf`)
- `total` - Return file count only
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" files folder="Daily Notes" ext=md
```

**Returns:** List of file paths, one per line

---

### folders
List folders in the vault.

**Options:**
- `folder=<path>` - Filter by parent folder
- `total` - Return folder count only
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" folders
```

**Returns:** List of folder paths, one per line

---

### file
Show file info.

**Options:**
- `file=<name>` - File name
- `path=<path>` - File path
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" file path="Projects/Note.md"
```

**Returns:** File metadata (path, size, modified date, etc.)

---

### folder
Show folder info.

**Options:**
- `path=<path>` - Folder path (required)
- `info=files|folders|size` - Return specific info only
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" folder path="Projects" info=files
```

## Daily Note Operations

### daily:read
Read daily note contents.

**Options:**
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" daily:read
```

**Returns:** Daily note content

---

### daily:path
Get daily note path.

**Options:**
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" daily:path
```

**Returns:** Path to today's daily note (e.g., `Daily Notes/2024-01-15.md`)

---

### daily:append
Append content to daily note.

**Options:**
- `content=<text>` - Content to append (required)
- `inline` - Append without newline
- `open` - Open file after adding
- `paneType=tab|split|window` - Pane type to open in
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" daily:append content="\n## 15:30 Meeting Notes\n\nDiscussed authentication approach"
```

---

### daily:prepend
Prepend content to daily note.

**Options:**
- `content=<text>` - Content to prepend (required)
- `inline` - Prepend without newline
- `open` - Open file after adding
- `paneType=tab|split|window` - Pane type to open in
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" daily:prepend content="## 🎯 Today's Priority\n\nFinish auth feature\n\n"
```

---

### daily
Open daily note.

**Options:**
- `paneType=tab|split|window` - Pane type to open in
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" daily
```

## Task Operations

### tasks
List tasks in the vault.

**Options:**
- `file=<name>` - Filter by file name
- `path=<path>` - Filter by file path
- `total` - Return task count only
- `done` - Show completed tasks
- `todo` - Show incomplete tasks
- `status="<char>"` - Filter by status character (e.g., `x`, `-`, `>`)
- `verbose` - Group by file with line numbers
- `format=json|tsv|csv` - Output format (default: text)
- `active` - Show tasks for active file
- `daily` - Show tasks from daily note
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" tasks todo format=json
```

**JSON Output Format:**
```json
[
  {
    "file": "Projects/API.md",
    "line": 15,
    "task": "- [ ] Implement JWT refresh",
    "status": " ",
    "done": false
  }
]
```

---

### task
Show or update a task.

**Options:**
- `ref=<path:line>` - Task reference (e.g., `Projects/API.md:15`)
- `file=<name>` - File name
- `path=<path>` - File path
- `line=<n>` - Line number
- `toggle` - Toggle task status
- `done` - Mark as done
- `todo` - Mark as todo
- `daily` - Use daily note
- `status="<char>"` - Set status character
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" task path="Projects/API.md" line=15 done
```

## Tag Operations

### tags
List tags in the vault.

**Options:**
- `file=<name>` - File name
- `path=<path>` - File path
- `total` - Return tag count only
- `counts` - Include tag occurrence counts
- `sort=count` - Sort by count (default: name)
- `format=json|tsv|csv` - Output format (default: tsv)
- `active` - Show tags for active file
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" tags counts sort=count format=json
```

**JSON Output Format:**
```json
[
  {"tag": "dev", "count": 42},
  {"tag": "api", "count": 28}
]
```

---

### tag
Get tag info.

**Options:**
- `name=<tag>` - Tag name (required, include `#`)
- `total` - Return occurrence count only
- `verbose` - Include file list and count
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" tag name="#dev" verbose
```

## Properties (Frontmatter)

### property:read
Read a property value from a file.

**Options:**
- `name=<name>` - Property name (required)
- `file=<name>` - File name
- `path=<path>` - File path
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" property:read name="status" path="Projects/API.md"
```

---

### property:set
Set a property on a file.

**Options:**
- `name=<name>` - Property name (required)
- `value=<value>` - Property value (required)
- `type=text|list|number|checkbox|date|datetime` - Property type
- `file=<name>` - File name
- `path=<path>` - File path
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" property:set name="status" value="in-progress" type=text path="Projects/API.md"
```

---

### property:remove
Remove a property from a file.

**Options:**
- `name=<name>` - Property name (required)
- `file=<name>` - File name
- `path=<path>` - File path
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" property:remove name="draft" path="Projects/API.md"
```

---

### properties
List properties in the vault.

**Options:**
- `file=<name>` - Show properties for file
- `path=<path>` - Show properties for path
- `name=<name>` - Get specific property count
- `total` - Return property count only
- `sort=count` - Sort by count (default: name)
- `counts` - Include occurrence counts
- `format=yaml|json|tsv` - Output format (default: yaml)
- `active` - Show properties for active file
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" properties counts format=json
```

## Template Operations

### template:read
Read template content.

**Options:**
- `name=<template>` - Template name (required)
- `resolve` - Resolve template variables
- `title=<title>` - Title for variable resolution
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" template:read name="daily" resolve title="2024-01-15"
```

---

### templates
List templates.

**Options:**
- `total` - Return template count only
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" templates
```

## Vault Operations

### vault
Show vault info.

**Options:**
- `info=name|path|files|folders|size` - Return specific info only
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" vault info=path
```

**Returns:** Vault metadata (name, path, stats)

---

### vaults
List known vaults.

**Options:**
- `total` - Return vault count only
- `verbose` - Include vault paths

**Example:**
```bash
obsidian vaults verbose
```

**Returns:** List of vault names (and paths if verbose)

---

### version
Show Obsidian version.

**Example:**
```bash
obsidian version
```

**Returns:** Version string (e.g., `1.5.3`)

## Link Operations

### links
List outgoing links from a file.

**Options:**
- `file=<name>` - File name
- `path=<path>` - File path
- `total` - Return link count only
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" links path="Architecture/Auth.md"
```

---

### backlinks
List backlinks to a file.

**Options:**
- `file=<name>` - Target file name
- `path=<path>` - Target file path
- `counts` - Include link counts
- `total` - Return backlink count only
- `format=json|tsv|csv` - Output format (default: tsv)
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" backlinks path="Architecture/Auth.md" format=json
```

---

### orphans
List files with no incoming links.

**Options:**
- `total` - Return orphan count only
- `all` - Include non-markdown files
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" orphans
```

---

### unresolved
List unresolved links in vault.

**Options:**
- `total` - Return unresolved link count only
- `counts` - Include link counts
- `verbose` - Include source files
- `format=json|tsv|csv` - Output format (default: tsv)
- `vault=<name>` - Target vault (**must be first parameter**)

**Example:**
```bash
obsidian vault="My Vault" unresolved format=json
```

## Common Patterns

### Check if File Exists

```bash
if obsidian vault="My Vault" read path="Note.md" >/dev/null 2>&1; then
  echo "File exists"
else
  echo "File not found"
fi
```

### Create or Append

```bash
if ! obsidian vault="My Vault" read path="Note.md" >/dev/null 2>&1; then
  obsidian vault="My Vault" create path="Note.md" content="# Note\n\n"
else
  obsidian vault="My Vault" append path="Note.md" content="\nNew content"
fi
```

### Parse JSON Output

```bash
# Get search results as JSON
results=$(obsidian vault="My Vault" search query="test" format=json)

# Parse with jq
echo "$results" | jq -r '.[] | "\(.file): \(.matches) matches"'
```

### Get Vault Path

```bash
vault_path=$(obsidian vault="My Vault" vault info=path)
echo "Vault is at: $vault_path"
```

### List Recent Files

```bash
# Use files command and sort by modification time
# Get vault path first
vault_path=$(obsidian vault="My Vault" vault info=path)

# Note: stat syntax differs between macOS/BSD and Linux
if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "freebsd"* ]]; then
  # macOS/BSD
  obsidian vault="My Vault" files | while read -r file; do
    stat -f "%m %N" "$vault_path/$file"
  done | sort -rn | head -10
else
  # Linux
  obsidian vault="My Vault" files | while read -r file; do
    stat -c "%Y %n" "$vault_path/$file"
  done | sort -rn | head -10
fi
```

## Error Handling

### Exit Codes

- `0` - Success
- `1` - General error
- `2` - File/folder not found
- `3` - Invalid arguments

### Error Messages

Errors are printed to stderr. Capture them:

```bash
error=$(obsidian vault="My Vault" read path="nonexistent.md" 2>&1)
if [[ $? -ne 0 ]]; then
  echo "Error: $error"
fi
```

## Platform-Specific Paths

| Platform | CLI Location |
|----------|-------------|
| macOS | `/Applications/Obsidian.app/Contents/MacOS/obsidian` |
| Linux | `/usr/bin/obsidian` or `/opt/Obsidian/obsidian` |
| Windows | `C:\Users\<username>\AppData\Local\Obsidian\obsidian.exe` |

For portable scripts:

```bash
case "$OSTYPE" in
  darwin*)  OBSIDIAN="/Applications/Obsidian.app/Contents/MacOS/obsidian" ;;
  linux*)   OBSIDIAN="obsidian" ;;
  msys*|cygwin*) OBSIDIAN="obsidian.exe" ;;
esac
```

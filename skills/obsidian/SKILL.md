---
name: Obsidian Knowledge Management
description: |
  This skill should be used when the user asks to "capture to obsidian", "add to daily note", "research in vault", "search my notes", "save this insight", "query obsidian", "check daily note", "create daily note", "append to daily note", "find in obsidian", "look up notes", or mentions Obsidian-related knowledge management tasks. Provides three capabilities: daily notes, quick capture, and vault research.
version: 1.0.0
---

# Obsidian Knowledge Management Skill

This skill integrates Claude Code with Obsidian for knowledge management workflows during coding sessions. It provides three core capabilities:

1. **Daily Note** (`/daily-note`) - Interact with today's daily note
2. **Capture** (`/capture`) - Quick capture of thoughts, code snippets, or insights
3. **Research** (`/research`) - Search vault for relevant context

## Prerequisites

### Obsidian Local REST API Plugin

The [Obsidian Local REST API plugin](https://github.com/coddingtonbear/obsidian-local-rest-api) must be installed and enabled in your vault:

1. Open Obsidian Settings > Community plugins
2. Search for "Local REST API"
3. Install and enable the plugin
4. Copy the API key from the plugin settings

### Environment Variable

Set `OBSIDIAN_API_KEY` in your environment:

```bash
export OBSIDIAN_API_KEY="your-api-key-here"
```

### MCP Server

The `mcp-obsidian` server should be configured in `.mcp.json` (already included in this plugin).

### First-Run Check

On first use, verify prerequisites:

1. Check if Obsidian MCP tools are available
2. Test vault connectivity with `list_files_in_vault`

If connection fails, provide setup guidance.

## Available MCP Tools

| Tool | Purpose |
|------|---------|
| `obsidian/list_files_in_vault` | List all files in the vault |
| `obsidian/list_files_in_dir` | List files in a specific directory |
| `obsidian/get_file_contents` | Read note contents |
| `obsidian/search` | Full-text search across vault |
| `obsidian/patch_content` | Modify note content |
| `obsidian/append_content` | Append content to a note |
| `obsidian/delete_file` | Delete a note |

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

**On first use**, ask the user for their daily note path pattern if not obvious from vault structure.

### Workflow: Retrieve Daily Note

```
1. Calculate today's date in YYYY-MM-DD format
2. Construct path based on user's pattern (or detect from vault)
3. Use obsidian/get_file_contents to fetch the note
4. Display contents with clear formatting
5. If note doesn't exist, offer to create it
```

### Workflow: Create Daily Note

```
1. Check if daily note already exists
2. If exists, inform user and offer to append instead
3. If creating, use appropriate template:
   - Date header
   - Standard sections (optional)
4. Use obsidian/patch_content to create the note
```

### Workflow: Append to Daily Note

```
1. Verify daily note exists (create if needed)
2. Format content appropriately:
   - Add timestamp if requested
   - Include context (current project/file if relevant)
3. Use obsidian/append_content to add the entry
4. Confirm success
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

```
1. Parse capture command for options (--note, --tag, --code)
2. Determine target (daily note or specific note)
3. Format content with timestamp and context
4. Use obsidian/append_content to save
5. Confirm capture with link to note
```

### Workflow: Code Capture

When `--code` flag is used:

```
1. Get current file context (path, selection if any)
2. Format as code block with language
3. Add file path as reference
4. Capture to specified target
```

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

1. **Full-text search** using `obsidian/search`
2. **Filter results** by relevance
3. **Summarize findings** for quick consumption
4. **Suggest related notes** via backlinks

### Workflow: Research Query

```
1. Parse research query and options
2. Execute search via obsidian/search
3. Filter and rank results by relevance
4. Present top results with:
   - Note title and path
   - Relevant excerpt
5. Offer to read full note if requested
```

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

## Error Handling

### Connection Errors

If MCP tools fail:

```markdown
**Obsidian connection failed**

Please verify:
1. Obsidian is running
2. Local REST API plugin is enabled
3. `OBSIDIAN_API_KEY` environment variable is set
4. Port 27124 is accessible
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
- Search in specific folder with `--folder`
```

## Configuration

### Daily Note Settings

Store user preferences in `${CLAUDE_PLUGIN_ROOT}/config.json`:

```json
{
  "obsidian": {
    "daily_note_path": "Daily Notes/{{date:YYYY-MM-DD}}.md",
    "daily_note_template": "templates/daily.md",
    "default_capture_target": "daily"
  }
}
```

### First-Time Setup

On first use, prompt for preferences:

1. Daily note location pattern
2. Default capture behavior
3. Preferred timestamp format

## Additional Resources

For MCP tool details, see `references/mcp-tools.md`.

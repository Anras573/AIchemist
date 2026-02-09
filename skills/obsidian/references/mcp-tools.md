# Obsidian MCP Tools Reference

This reference documents the available tools from the `mcp-obsidian` MCP server.

## Tool Overview

| Tool | Description | Returns |
|------|-------------|---------|
| `list_files_in_vault` | Lists all files in the vault | Array of file paths |
| `list_files_in_dir` | Lists files in a specific directory | Array of file paths |
| `get_file_contents` | Reads the content of a note | Note content as string |
| `search` | Full-text search across vault | Array of search results |
| `patch_content` | Creates or overwrites note content | Success confirmation |
| `append_content` | Appends content to existing note | Success confirmation |
| `delete_file` | Deletes a note from the vault | Success confirmation |

## Tool Details

### list_files_in_vault

Lists all files in the Obsidian vault.

**Parameters:** None

**Returns:** Array of relative file paths

**Example:**
```json
["Daily Notes/2024-01-15.md", "Projects/API/notes.md", "Templates/daily.md"]
```

**Use case:** Discovering vault structure, finding daily note patterns.

---

### list_files_in_dir

Lists files within a specific directory.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `dirpath` | string | Yes | Relative path to directory |

**Returns:** Array of file paths within the directory

**Example call:**
```json
{
  "dirpath": "Daily Notes"
}
```

**Use case:** Listing recent daily notes, exploring project folders.

---

### get_file_contents

Retrieves the content of a specific note.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `filepath` | string | Yes | Relative path to the note |

**Returns:** Note content as markdown string

**Example call:**
```json
{
  "filepath": "Daily Notes/2024-01-15.md"
}
```

**Use case:** Reading daily notes, fetching research context.

---

### search

Performs full-text search across the vault.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `query` | string | Yes | Search query |

**Returns:** Array of search results with:
- `filename`: Path to matching note
- `matches`: Array of matching text excerpts

**Example call:**
```json
{
  "query": "authentication JWT"
}
```

**Use case:** Research queries, finding related notes.

---

### patch_content

Creates a new note or overwrites an existing one.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `filepath` | string | Yes | Path for the note |
| `content` | string | Yes | Full markdown content |

**Returns:** Success confirmation

**Example call:**
```json
{
  "filepath": "Daily Notes/2024-01-15.md",
  "content": "# 2024-01-15\n\n## Today's Focus\n\n- Work on authentication feature"
}
```

**Warning:** This overwrites existing content. Use `append_content` to add to existing notes.

**Use case:** Creating new daily notes, creating new capture notes.

---

### append_content

Appends content to an existing note.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `filepath` | string | Yes | Path to existing note |
| `content` | string | Yes | Content to append |

**Returns:** Success confirmation

**Example call:**
```json
{
  "filepath": "Daily Notes/2024-01-15.md",
  "content": "\n\n## 14:30 - Code Review Notes\n\nFound issue with token refresh logic..."
}
```

**Use case:** Adding entries to daily notes, capturing quick thoughts.

---

### delete_file

Deletes a note from the vault.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `filepath` | string | Yes | Path to note to delete |

**Returns:** Success confirmation

**Warning:** This permanently deletes the file. Use with caution.

**Use case:** Cleaning up temporary notes (rarely needed).

## Common Patterns

### Check if Note Exists

1. Call `list_files_in_dir` for the parent directory
2. Check if file is in the returned array
3. Or try `get_file_contents` and handle error

### Create Note if Missing

```
1. Try get_file_contents(filepath)
2. If not found:
   - Use patch_content to create with initial content
3. If found:
   - Use append_content to add new content
```

### Date-Based Paths

For daily notes, construct paths with current date:

```
Pattern: "Daily Notes/{{date:YYYY-MM-DD}}.md"
Example: "Daily Notes/2024-01-15.md"
```

Common date patterns:
- `YYYY-MM-DD` → `2024-01-15`
- `YYYY/MM-MMMM/DD` → `2024/01-January/15`
- `DD-MM-YYYY` → `15-01-2024`

## Error Responses

### File Not Found

```json
{
  "error": "File not found",
  "filepath": "Daily Notes/2024-01-15.md"
}
```

### Connection Error

```json
{
  "error": "Connection refused",
  "message": "Could not connect to Obsidian REST API"
}
```

### Authentication Error

```json
{
  "error": "Unauthorized",
  "message": "Invalid or missing API key"
}
```

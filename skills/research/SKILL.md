---
name: research
description: |
  This skill should be used when the user asks to "research in vault", "search my notes", "search obsidian", "find in obsidian", "look up notes", "find notes about", "what do I have on", "search my vault for", or wants to search their Obsidian vault for relevant context, past knowledge, or notes on a topic.
version: 1.0.0
---

# Research Skill

Search your Obsidian vault for relevant context during coding sessions. Quickly surface past notes, decisions, and knowledge without leaving your workflow.

## Operations

| Request | Action |
|---------|--------|
| "research authentication patterns" | Full-text search |
| "search in Projects/ for caching" | Search within a specific folder |
| "find top 10 results for error handling" | Return more results |

## Read vs Write Operations

Search operations are **read-only** — no confirmation needed. The one exception is first-use configuration: if no preferred vault is set, the skill will prompt you to select one and ask for explicit confirmation before saving to `${CLAUDE_PLUGIN_ROOT}/config.json`.

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
| `search` | Search vault (file list + match counts) | `query=<text>`, `format=json`, `path=<folder>` |
| `search:context` | Search with matching lines | `query=<text>`, `format=json`, `limit=<n>`, `path=<folder>` |
| `read` | Read a specific note | `path=<path>`, `file=<name>` |
| `files` | List files in a folder | `folder=<path>`, `ext=<extension>`, `total` |
| `vaults` | List available vaults | `verbose` |

**Notes:**
- Use `format=json` for programmatic parsing of search results
- Use `path=<folder>` to restrict search scope to a folder

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
- `query`: The search terms
- `--folder <path>`: Optional folder filter
- `--limit <n>`: Max results (default: 5)

### 2. Load Configuration

Read `${CLAUDE_PLUGIN_ROOT}/config.json` for preferred vault. If missing, follow the first-use flow above.

### 3. Execute Search

```bash
# Search with context (provides matching lines — preferred)
obsidian vault="<preferredVault>" search:context query="<query>" format=json

# With folder filter:
obsidian vault="<preferredVault>" search:context query="<query>" path="<folder-path>" format=json
```

### 4. Rank and Limit Results

Take the top N results (default: 5). The search API returns results in relevance order.

### 5. Present Results

```markdown
### Research Results: "authentication patterns"

**Found 5 relevant notes:**

---

**1. Authentication Design**
`Architecture/Auth.md`

> We decided to use JWT with refresh tokens because they allow stateless
> verification while still providing a mechanism for token revocation...

---

**2. API Security Notes**
`Projects/API/security.md`

> OAuth2 flow handles the authentication layer...

---

_Say "read 1" to see the full note, or refine your search._
```

### 6. Handle Follow-up (read N)

If the user responds with "read 1", "read 2", etc.:

```bash
obsidian vault="<preferredVault>" read path="<result-file-path>"
```

Display the complete note.

## Error Handling

### No Query Provided

```markdown
**No search query provided**

Try asking in natural language, for example:
- "Research authentication patterns"
- "Search my notes in Projects/ for caching"

Legacy (slash command): `/research <your query>`
```

### No Results Found

```markdown
**No results found** for "quantum encryption"

Suggestions:
- Try broader terms: "encryption" instead of "quantum encryption"
- Check spelling
- Search in a specific folder: `--folder Projects/`
```

### CLI Not Found

```markdown
**Obsidian CLI not found**

Please verify:
1. Obsidian desktop app is installed (v1.5.0+)
2. On macOS, CLI is at: `/Applications/Obsidian.app/Contents/MacOS/obsidian`
3. Consider adding an alias: `alias obsidian="/Applications/Obsidian.app/Contents/MacOS/obsidian"`
```

### Folder Not Found

```markdown
**Folder not found:** `Projects/OldProject/`

Available top-level folders:
- Projects/
- Archive/
- Daily Notes/
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

## Tips

- **Be specific**: "JWT refresh token rotation" finds better matches than "auth"
- **Use folder filters**: Narrow down to relevant project or topic area
- **Follow up**: Use "read N" to dive into promising results
- **Iterate**: Refine your query based on initial results

## Additional Resources

- **In-repo reference:** See [skills/references/cli-commands.md](../references/cli-commands.md) for comprehensive CLI documentation
- **Built-in help:** Run `obsidian help` or `obsidian help <command>`

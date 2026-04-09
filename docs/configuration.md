# Configuration

## Auto-Configuration

AIchemist uses lazy configuration — settings are fetched and cached on first use:

- **Jira user info**: Fetched via Atlassian MCP and stored in `config.json` within the plugin directory
- **No manual placeholders required**: Just install and use

> **Note:** The config file contains personal data (email, account ID) and is excluded from version control via `.gitignore`.

## MCP Servers

### Official Claude Code Integrations

For **GitHub**, **Atlassian** (Jira/Confluence), **Context7**, and **Microsoft Learn**, use the official Claude Code MCP integrations available via the Claude marketplace. These are managed via Claude Code's integrations UI, not via `.mcp.json`.

To add them, run the following slash command inside Claude Code (not your system shell):

```text
/mcp
```

These are maintained by Anthropic and provide the best integration experience. The plugin's Jira skills work seamlessly with the official Atlassian MCP server.

### Additional MCP Servers (.mcp.json)

The `.mcp.json` file configures additional MCP servers not available as official integrations.

#### Local Servers (stdio)

| Server | Description | Auth Required |
| ------ | ----------- | ------------- |
| `mempalace` | Local vector + knowledge graph memory | None |
| `markitdown` | Local document-to-Markdown conversion server | None |

## Skill-Specific Setup

### MemPalace

MemPalace stores memories locally using ChromaDB and SQLite. No Docker, no cloud account, no API key required.

### Requirements

1. **Python 3** installed
2. **`mempalace` package** installed:
   ```bash
   pip install mempalace
   ```
3. **Initialise a palace directory** (one-time setup):
   ```bash
   mempalace init ~/.mempalace
   ```

### Verify the server is working

```bash
mempalace --version
mempalace status
```

---

### Markitdown

The Markitdown skill converts remote URLs and local files to clean markdown using a Docker-based MCP server. No cloud account or API key is required.

### Requirements

1. **Docker** installed and running
2. **markitdown image** available locally:
   ```bash
   docker pull mcp/markitdown@sha256:1cef3bf502503310ed0884441874ccf6cdaac20136dc1179797fa048269dc4cb
   ```

### Verify the server is working

Test a remote URL conversion directly:

```bash
docker run --rm -i --entrypoint markitdown mcp/markitdown@sha256:1cef3bf502503310ed0884441874ccf6cdaac20136dc1179797fa048269dc4cb "https://example.com"
```

Test local file conversion via the bundled helper script:

```bash
tools/markitdown.sh /path/to/file.pdf
```

### Local File Conversion

The MCP server runs in a sandboxed Docker container with no volume mounts, so `file://` URIs cannot be passed directly to `mcp__markitdown__convert_to_markdown`. For local files, use the bundled script instead:

```bash
tools/markitdown.sh <path-to-file>
```

The script mounts the file's **parent directory** (read-only) into the container. Avoid running it against files in sensitive directories such as `~` or `~/.ssh`.

### Supported File Types

PDF, DOCX, PPTX, XLSX, HTML, CSV, JSON, XML, images (OCR), and plain text.

---

### Obsidian

The Obsidian skill uses the Obsidian CLI (included with Obsidian v1.5.0+) to interact with your vault. No MCP server or API key is required.

### Requirements

1. **Obsidian desktop app** installed (v1.5.0 or later)
2. **At least one vault** created in Obsidian
3. **Obsidian running** (the CLI communicates with the running application)

### CLI Location

The CLI is included with Obsidian:

| Platform | CLI Path |
| -------- | -------- |
| macOS | `/Applications/Obsidian.app/Contents/MacOS/obsidian` |
| Linux | `/usr/bin/obsidian` or `/opt/Obsidian/obsidian` |
| Windows | `C:\Users\<username>\AppData\Local\Obsidian\obsidian.exe` |

### Optional Shell Alias

For convenience, add an alias to your shell profile:

```bash
# macOS: Add to ~/.zshrc or ~/.bashrc
alias obsidian="/Applications/Obsidian.app/Contents/MacOS/obsidian"

# Linux: Add to ~/.zshrc or ~/.bashrc (adjust path if needed)
# alias obsidian="/usr/bin/obsidian"

# Windows (Git Bash/WSL): Add to ~/.bashrc
# alias obsidian="/c/Users/<username>/AppData/Local/Obsidian/obsidian.exe"
```

### First Use

On first use of Obsidian skills, you'll be prompted to select a vault if you have multiple vaults. The skill will remember your preference.

### AGENT.md File

Optionally create an `AGENT.md` file at the root of your vault to document your vault structure, conventions, and preferences. The skill will automatically read this file on first interaction to better understand your vault.

Example `AGENT.md`:
```markdown
# My Vault Guide

## Folder Structure
- `Daily Notes/` — Daily journals in YYYY-MM-DD format
- `Projects/` — Project documentation
- `Captures/` — Quick captures and fleeting notes

## Tagging Conventions
- `#dev` — Development notes
- `#meeting` — Meeting notes
- `#idea` — Ideas and brainstorming

## Daily Note Template
Daily notes use the "daily" template with sections for:
- Morning planning
- Work log
- Evening reflection
```

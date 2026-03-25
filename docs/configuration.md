# Configuration

## Auto-Configuration

AIchemist uses lazy configuration — settings are fetched and cached on first use:

- **Jira user info**: Fetched via Atlassian MCP and stored in `config.json` within the plugin directory
- **No manual placeholders required**: Just install and use

> **Note:** The config file contains personal data (email, account ID) and is excluded from version control via `.gitignore`.

## MCP Servers

### Official Claude Code Integrations

For **GitHub**, **Atlassian** (Jira/Confluence), **Context7**, and **Microsoft Learn**, use the official MCP servers built into Claude Code. These are managed via Claude Code's integrations UI, not via `.mcp.json`.

To add them, run the following slash command inside Claude Code (not your system shell):

```text
/mcp
```

These are maintained by Anthropic and provide the best integration experience. The plugin's Jira skills work seamlessly with the official Atlassian MCP server.

### Additional MCP Servers (.mcp.json)

The `.mcp.json` file configures additional MCP servers not available as official integrations.

#### HTTP Servers (Hosted)

| Server | Description | Auth Required |
| ------ | ----------- | ------------- |
| `graphiti` | Graphiti graph memory for persistent agent knowledge | None (local Docker) |

## Skill-Specific Setup

### Graphiti

The Graphiti skill uses a locally-running Docker container as its MCP server. No cloud account or API key is required.

### Requirements

1. **Docker** installed and running
2. **Graphiti container** running — see the [Graphiti documentation](https://github.com/getzep/graphiti) for setup
3. **`GRAPHITI_MCP_URL` environment variable** set to the container's MCP endpoint:
   ```bash
   export GRAPHITI_MCP_URL=http://localhost:8123/mcp
   ```
   Add this to your shell profile (`.zshrc`, `.bashrc`) for persistence.

### Verify the server is reachable

Once running, the skill will automatically call `graphiti/get_status` if it encounters connection errors. You can also ask Claude directly: *"check graphiti status"*.

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

# Configuration

## Auto-Configuration

AIchemist uses lazy configuration — settings are fetched and cached on first use:

- **Jira user info**: Fetched via Atlassian MCP and stored in `config.json` within the plugin directory
- **No manual placeholders required**: Just install and use

> **Note:** The config file contains personal data (email, account ID) and is excluded from version control via `.gitignore`.

## MCP Servers

### Official Claude Code Integrations

For **GitHub**, **Atlassian** (Jira/Confluence), and **Context7**, use the official MCP servers built into Claude Code. These are managed via Claude Code's integrations UI, not via `.mcp.json`.

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
| `microsoft-docs` | Microsoft Learn documentation (.NET, Azure, C#) | None |

#### Local Servers (stdio)

| Server | Description | Auth Required |
| ------ | ----------- | ------------- |
| `obsidian` | Obsidian vault access via Local REST API | API key + Obsidian running |

The `obsidian` MCP server is launched via `uvx mcp-obsidian`, so you need `uv` (which provides the `uvx` command) installed and on your `PATH`. On first use, `uvx` will automatically download and run the `mcp-obsidian` package if it is not already available.

## Environment Variables

| Variable | Required For | Description |
| -------- | ------------ | ----------- |
| `OBSIDIAN_API_KEY` | Obsidian MCP server | API key from Obsidian Local REST API plugin |

### Obsidian API Key

The Obsidian MCP server requires:

1. **Obsidian Local REST API plugin** installed and enabled in your vault
2. **API key** from the plugin settings

```bash
export OBSIDIAN_API_KEY="your-api-key-here"
```

The MCP server connects to `127.0.0.1:27124` by default. Obsidian must be running for the connection to work.

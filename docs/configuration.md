# Configuration

## Auto-Configuration

AIchemist uses lazy configuration — settings are fetched and cached on first use:

- **Jira user info**: Fetched via Atlassian MCP and stored in `config.json` within the plugin directory
- **No manual placeholders required**: Just install and use

> **Note:** The config file contains personal data (email, account ID) and is excluded from version control via `.gitignore`.

## MCP Servers

The `.mcp.json` file configures external MCP servers.

### HTTP Servers (Hosted)

| Server | Description | Auth Required |
| ------ | ----------- | ------------- |
| `github` | GitHub Copilot MCP integration | GitHub Copilot subscription |
| `atlassian` | Jira and Confluence access | Atlassian account (OAuth via browser) |
| `microsoft-docs` | Microsoft Learn documentation (.NET, Azure, C#) | None |
| `context7` | Up-to-date library documentation | API key |

### Local Servers (stdio)

| Server | Description | Auth Required |
| ------ | ----------- | ------------- |
| `obsidian` | Obsidian vault access via Local REST API | API key + Obsidian running |

The `obsidian` MCP server is launched via `uvx mcp-obsidian`, so you need `uv` (which provides the `uvx` command) installed and on your `PATH`. On first use, `uvx` will automatically download and run the `mcp-obsidian` package if it is not already available.

## Environment Variables

| Variable | Required For | Description |
| -------- | ------------ | ----------- |
| `CONTEXT7_API_KEY` | Context7 MCP server | API key for library documentation lookups |
| `OBSIDIAN_API_KEY` | Obsidian MCP server | API key from Obsidian Local REST API plugin |

### Context7 API Key

Context7 requires an API key set as an environment variable:

```bash
export CONTEXT7_API_KEY="your-api-key-here"
```

Get your API key from [Context7](https://context7.com).

Add this to your shell profile (`.bashrc`, `.zshrc`, etc.) for persistence.

### Obsidian API Key

The Obsidian MCP server requires:

1. **Obsidian Local REST API plugin** installed and enabled in your vault
2. **API key** from the plugin settings

```bash
export OBSIDIAN_API_KEY="your-api-key-here"
```

The MCP server connects to `127.0.0.1:27124` by default. Obsidian must be running for the connection to work.

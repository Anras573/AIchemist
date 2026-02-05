# Configuration

## Auto-Configuration

AIchemist uses lazy configuration — settings are fetched and cached on first use:

- **Jira user info**: Fetched via Atlassian MCP and stored in `config.json` within the plugin directory
- **No manual placeholders required**: Just install and use

> **Note:** The config file contains personal data (email, account ID) and is excluded from version control via `.gitignore`.

## MCP Servers

The `.mcp.json` file configures external MCP servers. All servers use hosted HTTP endpoints.

| Server | Description | Auth Required |
| ------ | ----------- | ------------- |
| `github` | GitHub Copilot MCP integration | GitHub Copilot subscription |
| `atlassian` | Jira and Confluence access | Atlassian account (OAuth via browser) |
| `microsoft-docs` | Microsoft Learn documentation (.NET, Azure, C#) | None |
| `context7` | Up-to-date library documentation | API key |

## Environment Variables

| Variable | Required For | Description |
| -------- | ------------ | ----------- |
| `CONTEXT7_API_KEY` | Context7 MCP server | API key for library documentation lookups |

### Context7 API Key

Context7 requires an API key set as an environment variable:

```bash
export CONTEXT7_API_KEY="your-api-key-here"
```

Get your API key from [Context7](https://context7.com).

Add this to your shell profile (`.bashrc`, `.zshrc`, etc.) for persistence.

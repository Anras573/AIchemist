# AIchemist

_Transmuting raw AI capabilities into golden solutions_

A personal collection of custom agents, skills, prompts, tools, and MCP servers for AI-assisted development.

## Repository Structure

```text
AIchemist/
├── .claude-plugin/  # Plugin manifest (plugin.json)
├── .lsp.json        # LSP server configurations
├── .mcp.json        # MCP server configurations
├── agents/          # Custom AI agents with specialized behaviors
├── commands/        # Executable commands (slash commands)
├── hooks/           # Event hooks (e.g., notifications)
├── skills/          # Reusable skills and workflows
├── prompts/         # Prompt templates and system prompts
├── tools/           # Custom tools and utilities
└── examples/        # Usage examples and demonstrations
```

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/Anras573/AIchemist.git
   ```

2. Add the plugin to Claude Code by navigating to **Settings > Plugins** and adding the path to the `.claude-plugin` directory.

3. **(Optional)** Configure the MCP servers as described in [MCP Server Configuration](#mcp-server-configuration).

That's it! User-specific configuration (like Atlassian account info) is auto-fetched on first use.

## Agents

AIchemist includes specialized agents for different development tasks:

| Agent | Description |
| ----- | ----------- |
| **Code Review** | Expert code reviewer with parallel agent support, Jira integration, and confidence scoring |
| **TypeScript/React** | Full-stack TypeScript developer specializing in React, Next.js, Node.js, and modern frontend patterns |
| **.NET** | C#/.NET expert covering async patterns, SOLID principles, DDD, and testing frameworks |
| **DDD** | Domain-Driven Design expert for strategic modeling and tactical pattern review |
| **Jira** | Jira issue management with auto-configured user context |

Agents can consult each other for specialized guidance. For example, the Code Review agent consults the .NET agent for C# reviews and the TypeScript/React agent for frontend reviews.

## Commands

### `/jira-my-tickets [date]`

Show all Jira tickets where you are the assignee or creator since a specified date.

```text
/jira-my-tickets 2025-01-01
/jira-my-tickets last week
```

**First run**: The command will prompt to fetch and cache your Atlassian user info.

### `/code-review [options]`

Comprehensive code review with parallel agents, Jira integration, and confidence-based filtering.

```text
/code-review                     # Review current branch vs origin/main
/code-review --base develop      # Review against different base branch
/code-review --comment           # Post findings as inline PR comments
/code-review --ticket PROJ-123   # Override Jira ticket detection
```

**Features:**
- Launches 4+ parallel review agents (guidelines, bugs, security, DDD)
- Confidence scoring (0-100) with 80 threshold to filter false positives
- Auto-detects Jira tickets from branch name or PR description
- Inline PR comments with committable suggestions

## Configuration

### Auto-Configuration

AIchemist uses lazy configuration - settings are fetched and cached on first use:

- **Jira user info**: Fetched via Atlassian MCP and stored in `~/.aichemist/config.json`
- **No manual placeholders required**: Just install and use

### MCP Server Configuration

The `.mcp.json` file configures external MCP servers. All servers use hosted HTTP endpoints.

| Server | Description | Auth Required |
| ------ | ----------- | ------------- |
| `github` | GitHub Copilot MCP integration | GitHub Copilot subscription |
| `atlassian` | Jira and Confluence access | Atlassian account (OAuth via browser) |
| `microsoft-docs` | Microsoft Learn documentation (.NET, Azure, C#) | None |
| `context7` | Up-to-date library documentation | API key |

### Required Environment Variables

| Variable | Required For | Description |
| -------- | ------------ | ----------- |
| `CONTEXT7_API_KEY` | Context7 MCP server | API key for library documentation lookups |

#### Context7 API Key

Context7 requires an API key set as an environment variable:

```bash
export CONTEXT7_API_KEY="your-api-key-here"
```

Get your API key from [Context7](https://context7.com).

Add this to your shell profile (`.bashrc`, `.zshrc`, etc.) for persistence.

## Directories

### `agents/`

Custom agents configured for specific tasks - code review, exploration, planning, and domain-specific workflows.

### `commands/`

Executable commands invoked via slash syntax (e.g., `/jira-my-tickets`). Commands are action-oriented and perform specific operations.

### `skills/`

Reusable skills that extend AI agent capabilities with specialized knowledge and tool integrations.

### `prompts/`

Curated prompt templates, system prompts, and prompt engineering patterns for various use cases.

### `tools/`

Custom tools, scripts, and utilities that enhance AI workflows.

### `hooks/`

Event hooks that trigger actions based on Claude Code events. For example, the notification hook sends a desktop notification when Claude is awaiting user input. See `hooks/hooks.json` for configuration.

### `.lsp.json`

LSP (Language Server Protocol) configurations that provide code intelligence features like diagnostics, completions, and go-to-definition. Currently empty, reserved for future configurations.

### `.mcp.json`

MCP (Model Context Protocol) server configurations that expose new capabilities and integrations to AI agents.

### `examples/`

Practical examples demonstrating how to use and combine the components in this repository.

## Philosophy

Like the alchemists of old who sought to transform base metals into gold, AIchemist aims to refine and combine AI building blocks into powerful, practical solutions. Each component is crafted to be:

- **Composable** - Works well independently and in combination
- **Documented** - Clear purpose and usage instructions
- **Practical** - Solves real problems in daily workflows

## License

See [LICENSE](LICENSE) for details.

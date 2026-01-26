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
├── skills/          # Reusable skills and workflows
├── prompts/         # Prompt templates and system prompts
├── tools/           # Custom tools and utilities
└── examples/        # Usage examples and demonstrations
```

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

### `.lsp.json`

LSP (Language Server Protocol) configurations that provide code intelligence features like diagnostics, completions, and go-to-definition. Currently empty, reserved for future configurations.

### `.mcp.json`

MCP (Model Context Protocol) server configurations that expose new capabilities and integrations to AI agents. Currently empty, reserved for future configurations.

### `examples/`

Practical examples demonstrating how to use and combine the components in this repository.

## Philosophy

Like the alchemists of old who sought to transform base metals into gold, AIchemist aims to refine and combine AI building blocks into powerful, practical solutions. Each component is crafted to be:

- **Composable** - Works well independently and in combination
- **Documented** - Clear purpose and usage instructions
- **Practical** - Solves real problems in daily workflows

## Configuration

Some agents and skills use placeholders that must be replaced with your own values before use.

### Jira Placeholders

The following placeholders are used by Jira-related components:

| Placeholder | Used By | Description | Example |
| ----------- | ------- | ----------- | ------- |
| `{{USER_NAME}}` | Agent | Your full name | `Jane Smith` |
| `{{USER_NICKNAME}}` | Agent | Your display name | `Jane` |
| `{{USER_EMAIL}}` | Agent | Your Atlassian email | `jane.smith@company.com` |
| `{{ATLASSIAN_ACCOUNT_ID}}` | Agent, Skill | Your Atlassian account ID | `712020:abc123...` |
| `{{USER_LOCALE}}` | Agent | Your locale | `en-US` |
| `{{USER_JOB_TITLE}}` | Agent | Your job title | `Software Engineer` |
| `{{USER_TEAM_TYPE}}` | Agent | Your team type | `Software development` |
| `{{DEFAULT_PROJECT_KEY}}` | Agent | Default Jira project key | `MYPROJECT` |

**Components:**

- `agents/jira.agent.md` - Requires all placeholders above
- `commands/jira-my-tickets.md` - Requires only `{{ATLASSIAN_ACCOUNT_ID}}`

To find your Atlassian account ID, visit your Atlassian profile or use the Atlassian API.

## Commands

### `/jira-my-tickets [date]`

Show all Jira tickets where you are the assignee or creator since a specified date.

```text
/jira-my-tickets 2025-01-01
/jira-my-tickets last week
```

## License

See [LICENSE](LICENSE) for details.

# AIchemist

_Transmuting raw AI capabilities into golden solutions_

A personal collection of custom agents, skills, prompts, tools, and MCP servers for AI-assisted development.

## Repository Structure

```text
AIchemist/
├── agents/          # Custom AI agents with specialized behaviors
├── skills/          # Claude Code skills and workflows
├── prompts/         # Prompt templates and system prompts
├── tools/           # Custom tools and utilities
├── mcp-servers/     # Model Context Protocol servers
└── examples/        # Usage examples and demonstrations
```

## Directories

### `agents/`

Custom agents configured for specific tasks - code review, exploration, planning, and domain-specific workflows.

### `skills/`

Reusable skills for Claude Code that extend its capabilities with specialized knowledge and tool integrations.

### `prompts/`

Curated prompt templates, system prompts, and prompt engineering patterns for various use cases.

### `tools/`

Custom tools, scripts, and utilities that enhance AI workflows.

### `mcp-servers/`

Model Context Protocol servers that expose new capabilities and integrations to AI assistants.

### `examples/`

Practical examples demonstrating how to use and combine the components in this repository.

## Philosophy

Like the alchemists of old who sought to transform base metals into gold, AIchemist aims to refine and combine AI building blocks into powerful, practical solutions. Each component is crafted to be:

- **Composable** - Works well independently and in combination
- **Documented** - Clear purpose and usage instructions
- **Practical** - Solves real problems in daily workflows

## Configuration

Some agents use placeholders that must be replaced with your own values before use.

### Jira Agent Placeholders

Copy `agents/jira.agent.md` and replace the following placeholders:

| Placeholder | Description | Example |
| ----------- | ----------- | ------- |
| `{{USER_NAME}}` | Your full name | `Jane Smith` |
| `{{USER_NICKNAME}}` | Your display name | `Jane` |
| `{{USER_EMAIL}}` | Your Atlassian email | `jane.smith@company.com` |
| `{{ATLASSIAN_ACCOUNT_ID}}` | Your Atlassian account ID | `712020:abc123...` |
| `{{USER_LOCALE}}` | Your locale | `en-US` |
| `{{USER_JOB_TITLE}}` | Your job title | `Software Engineer` |
| `{{USER_TEAM_TYPE}}` | Your team type | `Software development` |
| `{{DEFAULT_PROJECT_KEY}}` | Default Jira project key | `MYPROJECT` |

To find your Atlassian account ID, visit your Atlassian profile or use the Atlassian API.

## License

See [LICENSE](LICENSE) for details.

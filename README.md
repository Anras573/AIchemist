# AIchemist

_Transmuting raw AI capabilities into golden solutions_

A Claude Code plugin with custom agents, skills, and commands for AI-assisted development.

## Installation

```bash
claude plugin install aichemist
```

See [docs/installation.md](docs/installation.md) for alternative installation methods and MCP server configuration.

## What's Included

**Agents** — Specialized agents for the Task tool:

- **Code Review** — Parallel review with Jira integration and confidence scoring
- **TypeScript/React** — Full-stack TypeScript, React, Next.js, Node.js
- **.NET** — C#/.NET with async patterns, SOLID, DDD, testing
- **DDD** — Domain-Driven Design guidance (language-agnostic)

**Skills** — Context-aware capabilities:

- **Jira** — Issue management with confirmation gates for write operations
- **PostgreSQL** — Safe database querying with blocked writes by default
- **Obsidian** — Knowledge management with daily notes, capture, and research
- **Tool Preferences** — Consistent tool selection patterns

**Commands** — Slash commands:

- `/jira-my-tickets [date]` — List your assigned/created tickets
- `/code-review [options]` — Run comprehensive code review

See [docs/](docs/) for detailed documentation.

## Quick Start

```bash
# Review your current branch
/code-review

# See your recent Jira tickets
/jira-my-tickets last week

# The agents work automatically via Task tool
# e.g., "Review this PR for DDD patterns" invokes the DDD agent
```

## Philosophy

Like the alchemists of old who sought to transform base metals into gold, AIchemist aims to refine and combine AI building blocks into powerful, practical solutions. Each component is crafted to be:

- **Composable** — Works well independently and in combination
- **Documented** — Clear purpose and usage instructions
- **Practical** — Solves real problems in daily workflows

## License

See [LICENSE](LICENSE) for details.

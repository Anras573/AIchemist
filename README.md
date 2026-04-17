# AIchemist

_Transmuting raw AI capabilities into golden solutions_

A plugin for Claude Code and GitHub Copilot CLI with custom agents and skills for AI-assisted development.

## Installation

**Claude Code:**
```bash
claude plugin install aichemist
```

**GitHub Copilot CLI:**
```bash
copilot plugin install aichemist
```

See [docs/installation.md](docs/installation.md) for alternative installation methods and MCP server configuration.

## What's Included

**Agents** — Specialized agents for the Task tool:

- **Code Review** — Parallel review with Jira integration and confidence scoring
- **TypeScript/React** — Full-stack TypeScript, React, Next.js, Node.js
- **.NET** — C#/.NET with async patterns, SOLID, DDD, testing
- **DDD** — Domain-Driven Design guidance (language-agnostic)

**Skills** — Context-aware capabilities:

- **Ticket Flow** — End-to-end workflow for taking a Jira ticket from definition to reviewed implementation
- **Brainstorming** — Structured design dialogue with a hard gate before any implementation
- **Beads** — AI-native task tracking with automatic sidecar storage outside your repo
- **Code Review** — Parallel review agents with confidence scoring and Jira integration
- **Jira** — Issue management with confirmation gates for write operations
- **Mermaid** — Generate diagrams (flowcharts, sequence, ER, C4, and more) as markdown
- **PostgreSQL** — Safe database querying with blocked writes by default
- **Daily Note** — Interact with your Obsidian daily note for journaling and task tracking
- **Capture** — Quick capture of thoughts and code snippets to Obsidian
- **Research** — Search your Obsidian vault for context during coding sessions
- **Playwright** — Browser automation and web testing via `playwright-cli`
- **Markitdown** — Convert remote URLs and local files to clean markdown
- **MemPalace** — Persistent local memory (vector + knowledge graph) across sessions
- **Tool Preferences** — Consistent tool selection patterns

See [docs/](docs/) for detailed documentation.

## Quick Start

```bash
# Review your current branch (skill auto-invoked by natural language)
# "Do a code review" or /code-review

# See your recent Jira tickets
# "Show my Jira tickets from last week" or /jira

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

# AIchemist – Copilot Instructions

AIchemist is a plugin for Claude Code and GitHub Copilot CLI that provides custom agents and skills for AI-assisted development.

**Claude Code:** `claude plugin install aichemist`
**GitHub Copilot CLI:** `copilot plugin install aichemist`

## Repository Structure

```
agents/     *.agent.md       Specialized AI agents invoked via the Task tool
skills/     <name>/SKILL.md  Slash commands and context-aware capabilities that extend the conversation
tools/                       Shell utilities (notify.sh)
hooks/      hooks.json       Claude Code event hooks
docs/                        User-facing documentation
```

## Component Types

### Agents (`agents/*.agent.md`)

Agents are subprocesses launched via the Task tool. They have focused domain expertise and run in isolation.

**Frontmatter schema:**
```yaml
---
name: <kebab-case-agent-name>
description: |
  One-paragraph description for when this agent should be invoked.
  Must include 3–4 <example> blocks showing trigger context, user message,
  and how the assistant should respond.
model: opus | sonnet | haiku
used-by: ['skills/example']   # optional — if invoked by a skill
skills:                             # optional — skills this agent loads
  - tool-preferences
inspiration:                        # optional — source URLs
  - https://...
---
```

**Rules:**
- One agent per file. File name: `<name>.agent.md`
- The `description` field is how Claude decides when to invoke the agent — be specific and include examples
- Prefer `opus` for review/reasoning-heavy agents, `sonnet` for generation, `haiku` for fast/simple tasks
- Agents may consult each other using the `agent` tool for cross-domain questions

### Skills (`skills/<name>/`)

Skills are Markdown prompts loaded into the active conversation when triggered by user intent. Unlike agents they don't run in a subprocess — they extend the current context.

**Directory structure:**
```
skills/<name>/
  SKILL.md          Required. Main skill definition
  examples/         Optional. Usage examples
  references/       Optional. Detailed reference material loaded on demand
```

**SKILL.md frontmatter schema:**
```yaml
---
name: kebab-case-slug
description: |
  Trigger phrases and conditions. Must include the exact phrases a user might say
  to activate this skill (e.g. "search Jira tickets", "PROJ-123").
version: 1.0.0
---
```

**Rules:**
- Skill name: lowercase letters, numbers, and hyphens only (e.g. `jira`, `code-review`) — used as the slash command trigger
- The `description` field controls auto-activation — list concrete trigger phrases
- Read operations should execute automatically; write/destructive operations require explicit user confirmation
- Document the confirmation prompt text for each write operation in a table
- Skills must not store secrets; use environment variables or auto-fetched config

### Hooks (`hooks/hooks.json`)

Event hooks run shell commands in response to Claude Code lifecycle events (e.g. `Stop`, `PreToolUse`).

```json
{
  "hooks": {
    "Stop": [{ "matcher": "", "hooks": [{ "type": "command", "command": "..." }] }]
  }
}
```

## Commit Messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/). Every commit must follow:

```
<type>(<scope>): <description>
```

| Type | When |
|------|------|
| `feat` | New agent, skill, or capability |
| `fix` | Bug fix in existing component |
| `docs` | Documentation changes only |
| `refactor` | Restructuring without behavior change |
| `chore` | Build, CI, dependency updates |

**Scopes:** `agents`, `skills`, `tools`, `hooks`, `mcp`, `docs`

Breaking changes: append `!` or add `BREAKING CHANGE:` footer → triggers major version bump.

## Design Principles

- **Composable**: Components work independently and in combination. Skills can trigger or orchestrate agents; agents can load supporting skills.
- **Explicit over implicit**: Write operations always confirm before executing. Agents state what they're doing.
- **Self-documenting**: Every agent and skill must have a description that explains when and why to use it.

## Adding a New Component

**New agent:**
1. Create `agents/<name>.agent.md` with required frontmatter and domain instructions
2. Add an entry to `docs/agents.md`

**New skill:**
1. Create `skills/<name>/SKILL.md` with trigger phrases and workflow instructions
2. Optionally add `examples/` and `references/` subdirectories
3. Add an entry to `docs/skills.md`
4. If the skill requires an MCP server, add it to `.mcp.json` and document setup in `docs/configuration.md`

## Key Files

| File | Purpose |
|------|---------|
| `.mcp.json` | MCP server configuration (mempalace, markitdown) |
| `hooks/hooks.json` | Claude Code event hook definitions |
| `.claude-plugin/` | Plugin manifest for the Claude marketplace |
| `docs/configuration.md` | User setup guide for MCP servers and skills |

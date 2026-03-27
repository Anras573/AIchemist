# Contributing to AIchemist

Thank you for your interest in contributing to AIchemist! This document outlines the contribution workflow and guidelines.

## Branch Protection

Direct pushes to `main` are not allowed. All changes must go through a pull request.

## Workflow

1. **Fork** the repository (external contributors) or **create a branch** (maintainers)
2. Make your changes following the guidelines below
3. Open a **pull request** targeting `main`
4. Ensure all checks pass
5. Request review from a maintainer

## Commit Message Format

This project uses [Conventional Commits](https://www.conventionalcommits.org/) and [release-please](https://github.com/googleapis/release-please) for automated releases. Every commit message must follow this format:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Description | Version Bump |
| ---- | ----------- | ------------ |
| `feat` | A new feature | Minor |
| `fix` | A bug fix | Patch |
| `docs` | Documentation only changes | None (included in changelog) |
| `style` | Formatting, missing semicolons, etc. (no code change) | None (included in changelog) |
| `refactor` | Code change that neither fixes a bug nor adds a feature | None (included in changelog) |
| `perf` | Performance improvement | None (included in changelog) |
| `test` | Adding or correcting tests | None (included in changelog) |
| `chore` | Maintenance tasks (build, CI, dependencies) | None (included in changelog) |

In the `simple` release-please strategy, only `feat` and `fix` commits trigger releases; other types are included in the changelog and bundled with the next such release.
### Breaking Changes

For breaking changes, either:
- Add `!` after the type: `feat!: remove deprecated skill`
- Include `BREAKING CHANGE:` in the footer

Breaking changes trigger a **major** version bump.

### Examples

```bash
# Feature
feat(agents): add Python code review agent

# Bug fix
fix(commands): correct date parsing in jira-my-tickets

# Documentation
docs: update MCP configuration instructions

# Breaking change
feat!: restructure agents directory

# Or with footer
feat: restructure agents directory

BREAKING CHANGE: Agent files moved from agents/ to agents/v2/
```

### Scopes

Common scopes for this project:

- `agents` - Custom AI agents
- `commands` - Slash commands
- `skills` - Reusable skills
- `prompts` - Prompt templates
- `tools` - Custom tools
- `hooks` - Event hooks
- `mcp` - MCP server configurations

## Pull Request Guidelines

### Title

PR titles should also follow Conventional Commits format, as they become the merge commit message:

```
feat(agents): add database migration assistant
```

### Description

Include in your PR description:
- **What** changes you made
- **Why** you made them
- **How** to test (if applicable)

### Checklist

Before submitting:

- [ ] Commit messages follow Conventional Commits format
- [ ] PR title follows Conventional Commits format
- [ ] Documentation updated (if applicable)
- [ ] Placeholders documented in README (if new ones added)

## Adding New Components

### Agents

Place new agents in `agents/` with the naming convention `<name>.agent.md`.

### Commands

Place new commands in `commands/` with the naming convention `<name>.md`.

### Skills

Place new skills in `skills/` following existing patterns.

### Hooks

Update `hooks/hooks.json` for new event hooks.

## Plugin Manifests

The plugin metadata is spread across two files:

| File | Used by | Purpose |
|------|---------|---------|
| `.claude-plugin/plugin.json` | Claude Code | Plugin identity and metadata |
| `.claude-plugin/marketplace.json` | Claude Code marketplace | Marketplace listing |

The root `plugin.json` was removed — `.claude-plugin/plugin.json` is now the single source of truth for plugin metadata.

**Note:** `.claude-plugin/plugin.json` does not need to declare component paths (`agents`, `skills`, `commands`, `hooks`, `mcpServers`) — Claude Code picks these up automatically from the default directories.

**When updating plugin metadata** (description, keywords, author, etc.), update `.claude-plugin/plugin.json`. The `marketplace.json` has its own schema and only needs updating if the marketplace description changes.

**Version numbers are managed automatically** by release-please — both files are listed in `extra-files` in `release-please-config.json` and will be bumped together on each release.

## Questions?

Open an issue for questions or discussions about potential contributions.

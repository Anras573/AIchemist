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
| `docs` | Documentation only changes | Patch |
| `style` | Formatting, missing semicolons, etc. (no code change) | Patch |
| `refactor` | Code change that neither fixes a bug nor adds a feature | Patch |
| `perf` | Performance improvement | Patch |
| `test` | Adding or correcting tests | Patch |
| `chore` | Maintenance tasks (build, CI, dependencies) | Patch |

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

## Questions?

Open an issue for questions or discussions about potential contributions.

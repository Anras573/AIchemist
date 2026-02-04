---
name: Tool Preferences
description: |
  Guidance for selecting between equivalent tools when multiple options exist. Inject this skill into agents that may interact with GitHub, git, or other systems where both CLI tools and MCP servers are available. This skill ensures consistent, efficient tool selection across all agents.
version: 1.0.0
---

# Tool Selection Preferences

This skill provides guidance on choosing between equivalent tools when multiple options are available. Following these preferences ensures consistent behavior, better performance, and predictable output across all agents.

## GitHub Operations

**Prefer `gh` CLI (via Bash) over GitHub MCP tools.**

| Operation | Preferred | Avoid |
|-----------|-----------|-------|
| View PR details | `gh pr view` | `pull_request_read` MCP |
| Get PR diff | `gh pr diff` | `get_commit` MCP |
| List PRs | `gh pr list` | `list_pull_requests` MCP |
| Search PRs | `gh pr list --search "query"` | `search_pull_requests` MCP |
| Post PR comment | `gh pr comment` | `add_issue_comment` MCP |
| View issues | `gh issue view` | `issue_read` MCP |
| List issues | `gh issue list` | `list_issues` MCP |
| Create issues | `gh issue create` | `issue_write` MCP |

### Why Prefer `gh` CLI

1. **Already authenticated** - Uses user's existing git/GitHub credentials
2. **Faster execution** - No HTTP round-trip to MCP server
3. **Predictable output** - Consistent format with `--json` flag
4. **Better errors** - Clear, actionable error messages
5. **Offline caching** - Some operations work with cached data

### When GitHub MCP Tools ARE Appropriate

Use GitHub MCP tools only when they provide functionality the CLI lacks:

| Use Case | MCP Tool | Reason |
|----------|----------|--------|
| Inline PR review comments | `add_comment_to_pending_review` | CLI doesn't support line-specific review comments |
| Pending review management | `pull_request_review_write` | Creating/submitting pending reviews |
| File contents at specific ref | `get_file_contents` | When you need content without cloning |
| Cross-repo code search | `search_code` | GitHub's code search API |

### Common `gh` CLI Patterns

```bash
# View PR with specific fields
gh pr view --json number,title,body,baseRefName,headRefName

# Get PR diff
gh pr diff

# List PRs with filters
gh pr list --state open --author @me

# View issue details
gh issue view 123 --json title,body,state,labels

# Search issues
gh issue list --search "bug in:title"

# Post comment to PR
gh pr comment 123 --body "Comment text"

# Get repo info
gh repo view --json nameWithOwner,defaultBranchRef
```

## Git Operations

**Prefer native git commands over any wrapper or MCP tool.**

| Operation | Preferred | Avoid |
|-----------|-----------|-------|
| Check status | `git status` | Any wrapper |
| View diff | `git diff` | GitHub MCP diff tools |
| Create branch | `git checkout -b name` | `create_branch` MCP |
| Commit changes | `git commit` | Any remote commit API |
| Push changes | `git push` | `push_files` MCP |

### Rationale

Git operations should be local-first. Using MCP tools for git operations:
- Bypasses local hooks (pre-commit, pre-push)
- Doesn't update local repository state
- May cause sync issues between local and remote

## Atlassian/Jira Operations

**Prefer Atlassian MCP tools** - there is no equivalent CLI.

The Atlassian MCP server (`atlassian/*` tools) is the correct choice for all Jira and Confluence operations. See the Jira skill for detailed guidance.

## Documentation Lookups

**Prefer MCP tools** for documentation:

| Source | Tool |
|--------|------|
| Library docs | Context7 (`context7/*`) |
| .NET/Microsoft docs | Microsoft Learn (`microsoft-docs/*`) |

These MCP tools provide curated, up-to-date documentation that's more reliable than web searches.

## Decision Framework

When unsure which tool to use, apply this framework:

```
1. Is there a local CLI tool that does this?
   YES → Use the CLI (gh, git, npm, dotnet, etc.)
   NO  → Continue to step 2

2. Does the MCP tool provide unique functionality?
   YES → Use the MCP tool
   NO  → Prefer CLI if available

3. Does the operation need to respect local state/hooks?
   YES → Must use local tools (git commit, npm install)
   NO  → Either is acceptable
```

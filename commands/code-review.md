---
name: code-review
description: Comprehensive code review with specialized agents, Jira integration, and flexible scope (PR or branch diff).
---

# Code Review Command

A comprehensive code review command that combines project guidelines, specialized agents, and optional Jira context to provide thorough feedback.

## Usage

```
/code-review                     # Review current branch vs origin/main
/code-review --base develop      # Review current branch vs origin/develop
/code-review --comment           # Review and post findings to GitHub PR
/code-review --ticket PROJ-123   # Override Jira ticket detection
```

## Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--comment` | Post findings as GitHub PR comment | Off (local output only) |
| `--base <branch>` | Base branch for comparison | `main` |
| `--ticket <KEY>` | Manually specify Jira ticket | Auto-detect |

## Execution Steps

When this command is invoked, follow these steps in order:

### 1. Parse Arguments

Extract flags from user input:
- `--comment`: Boolean, enables GitHub PR commenting
- `--base <branch>`: String, base branch for diff (default: `main`)
- `--ticket <KEY>`: String, optional Jira ticket override

### 2. Determine Review Scope

Check if there's an open PR for the current branch:

```bash
gh pr view --json number,title,body,baseRefName 2>/dev/null
```

**If PR exists:**
- Use PR's base branch for diff (ignore `--base` flag)
- Extract PR description for Jira ticket detection
- Note: `--comment` flag will post to this PR

**If no PR exists:**
- Use `git diff origin/<base>...HEAD` for the diff
- `--comment` flag should warn that no PR exists and skip commenting

### 3. Gather Project Guidelines

Search for and combine content from these instruction files (if they exist):
- `CLAUDE.md`
- `AGENTS.md`
- `.github/copilot-instructions.md`

Combine all found files into a unified context. These guidelines inform what patterns, conventions, and standards the review should enforce.

### 4. Detect Jira Ticket

**If `--ticket` flag provided:**
- Use the specified ticket directly

**Otherwise, detect from two sources:**

1. **Branch name**: Match patterns like `feature/{{DEFAULT_PROJECT_KEY}}-123-description` or `{{DEFAULT_PROJECT_KEY}}-123/description`
   - Regex: `({{DEFAULT_PROJECT_KEY}}-\d+)` to extract ticket key

2. **PR description** (if PR exists): Search for Jira ticket references
   - Look for patterns like `{{DEFAULT_PROJECT_KEY}}-123`, `[{{DEFAULT_PROJECT_KEY}}-123]`, or Jira URLs containing the ticket key

**If both sources found different tickets:**
- Ask the user which ticket is correct before proceeding
- Present both options and allow them to choose or skip Jira context

**If ticket found:**
- Fetch the Jira issue using `mcp__atlassian__getJiraIssue`
- Extract: summary, description, acceptance criteria, labels
- This context will be used to verify implementation matches requirements

### 5. Get the Diff

Retrieve the changes to review:

**PR mode:**
```bash
gh pr diff
```

**Branch mode:**
```bash
git diff origin/<base>...HEAD
```

Also get list of changed files for agent routing:
```bash
git diff --name-only origin/<base>...HEAD
```

### 6. Run Base Code Review

Using the gathered context (guidelines + Jira requirements), perform a comprehensive code review covering:

- **Correctness**: Does the code do what it's supposed to do?
- **Security**: OWASP Top 10, injection vulnerabilities, auth issues
- **Maintainability**: Readability, structure, ease of change
- **Performance**: Obvious inefficiencies or anti-patterns
- **Testing**: Test coverage and quality
- **Guidelines compliance**: Does it follow project conventions?

If Jira context is available, also verify:
- Implementation matches ticket description
- Acceptance criteria are addressed
- Edge cases from the ticket are handled

### 7. Route to Specialized Agents

Based on the changed files, invoke relevant specialized agents:

#### File-Triggered Agents

Check the list of changed files and invoke agents when matching patterns are found:

| File Patterns | Agent | Description |
|---------------|-------|-------------|
| `*.cs`, `*.csproj`, `*.sln`, `*.fsproj` | .NET Coding Agent | C#/F# and .NET project files |

To add a new agent: simply add a row to this table with the file patterns and agent name.

#### Always-Run Agents

These agents run on every review regardless of file types in the diff:

| Agent | Description |
|-------|-------------|
| <!-- Add agents here --> | <!-- Description --> |

To add an always-run agent: add a row to this table. Examples of candidates:
- Security scanner
- Dependency checker
- Documentation validator

For each triggered agent:
1. Provide the relevant subset of the diff
2. Include project guidelines context
3. Collect their findings

### 8. Aggregate Findings

Combine all feedback into a structured report:

```markdown
## Code Review Summary

### Jira Context (if available)
**Ticket**: PROJ-123 - [Summary]
**Acceptance Criteria Status**:
- ✅ Criterion 1 - Implemented
- ⚠️ Criterion 2 - Partial
- ❌ Criterion 3 - Missing

### Findings

#### 🚫 Blockers (must fix)
- [Issue description with file:line reference]

#### ⚠️ Warnings (should fix)
- [Issue description with file:line reference]

#### 💡 Suggestions (nice to have)
- [Issue description with file:line reference]

#### ✅ Good Patterns
- [Positive feedback on well-written code]

### Specialized Agent Feedback

#### .NET Agent
[Findings from .NET agent if invoked]

### Summary
- X blocker(s), Y warning(s), Z suggestion(s)
- [Overall assessment]
```

### 9. Output Results

**If `--comment` flag is set AND PR exists:**

Post findings as a PR comment using `gh pr comment` with collapsible sections:

```markdown
## Code Review

### Jira Context
**{{DEFAULT_PROJECT_KEY}}-123**: [Ticket summary]

### 🚫 X Blocker(s)
<!-- Always expanded - these must be addressed -->
- [Blocker 1 with file:line reference]
- [Blocker 2 with file:line reference]

<details>
<summary>⚠️ X Warning(s)</summary>

- [Warning 1 with file:line reference]
- [Warning 2 with file:line reference]

</details>

<details>
<summary>💡 X Suggestion(s)</summary>

- [Suggestion 1 with file:line reference]

</details>

<details>
<summary>✅ Good Patterns</summary>

- [Positive feedback]

</details>

<details>
<summary>🤖 Specialized Agent Feedback</summary>

#### .NET Agent
[Findings if invoked]

</details>
```

Also display the full report locally for immediate feedback.

**Otherwise:**
- Display the full report locally only
- If `--comment` was set but no PR exists, warn: "No PR found for current branch. Skipping GitHub comment."

## Error Handling

- If no changes to review: "No changes found between current branch and origin/<base>"
- If Jira ticket not found: Proceed without Jira context, note this in output
- If specialized agent fails: Log the error, continue with other agents
- If `--comment` fails: Display error, ensure local output still shown

## Configuration

The command uses these template variables (configure in your environment):
- `{{DEFAULT_PROJECT_KEY}}`: Default Jira project key for ticket detection

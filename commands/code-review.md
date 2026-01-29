---
name: code-review
description: Comprehensive code review with specialized agents, Jira integration, and flexible scope (PR or branch diff).
allowed-tools: Bash(gh pr comment:*), Bash(gh pr diff:*), Bash(gh pr view:*), Bash(gh pr list:*), mcp__github_inline_comment__create_inline_comment
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

## False Positive Exclusions

Do NOT flag the following - these are considered false positives:

- **Pre-existing issues**: Problems that existed before this PR/branch
- **Correct code that looks wrong**: Code that appears buggy but is actually correct
- **Pedantic nitpicks**: Minor issues a senior engineer would not flag
- **Linter-catchable issues**: Problems that automated linting will catch (do not run linter to verify)
- **General quality concerns**: Lack of test coverage, general security issues - unless explicitly required in project guidelines
- **Silenced issues**: Problems mentioned in guidelines but explicitly silenced in code (e.g., via lint ignore comments, `// NOSONAR`, `#pragma warning disable`)
- **Subjective improvements**: Style preferences or "nice to have" refactors without clear benefit
- **Issues outside the diff**: Problems in unchanged code that the PR author didn't touch

## Confidence Scoring

Every issue found must be assigned a confidence score from 0-100:

| Score | Meaning | Action |
|-------|---------|--------|
| 0-25 | Not confident, likely false positive | Do not report |
| 26-50 | Somewhat confident, might be real | Do not report |
| 51-75 | Moderately confident, probably real | Do not report |
| 76-89 | Highly confident, real and important | Report as suggestion |
| 90-100 | Certain, definitely a real issue | Report as warning/blocker |

**Default threshold: 80** - Only issues scoring 80+ are reported.

**Scoring guidance:**
- Syntax/type errors that will fail compilation → 100
- Clear logic errors producing wrong results → 95
- Unambiguous guideline violations (can quote exact rule) → 90
- Security vulnerabilities with clear exploit path → 95
- Performance issues with measurable impact → 85
- Potential issues depending on specific inputs/state → 50 (do not report)

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

**For each potential issue found:**
1. Check against the False Positive Exclusions list - skip if it matches
2. Assign a confidence score (0-100) based on the Confidence Scoring guidance
3. Only keep issues scoring 80 or above

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

### 8. Aggregate and Validate Findings

Combine all feedback from base review and specialized agents, then validate:

**For each issue:**
1. Verify it doesn't match any False Positive Exclusion
2. Confirm confidence score is 80+
3. Validate the issue is real (e.g., if "variable undefined" - verify it's actually undefined)
4. Categorize by severity based on confidence:
   - **90-100**: Blocker (must fix)
   - **80-89**: Warning/Suggestion (should fix)

**Local report structure:**

```markdown
## Code Review Summary

### Jira Context (if available)
**Ticket**: PROJ-123 - [Summary]
**Acceptance Criteria Status**:
- ✅ Criterion 1 - Implemented
- ⚠️ Criterion 2 - Partial
- ❌ Criterion 3 - Missing

### Findings (X issues, threshold: 80)

#### 🚫 Blockers (confidence 90+)
- [Issue] - file.cs:42 (confidence: 95)

#### ⚠️ Warnings (confidence 80-89)
- [Issue] - file.cs:87 (confidence: 82)

### Specialized Agent Feedback

#### .NET Agent
[Findings from .NET agent if invoked]

### Summary
- X blocker(s), Y warning(s)
- Y issues filtered (below threshold)
```

### 9. Output Results

**If `--comment` flag is set AND PR exists:**

Post findings as **inline comments** on the PR using `mcp__github_inline_comment__create_inline_comment`. For each issue:

1. **Location**: Comment directly on the file and line(s) where the issue exists
2. **Description**: Brief explanation of the issue and why it was flagged
3. **Suggestion**: For small, self-contained fixes (< 6 lines), include a committable suggestion block:
   ```suggestion
   // corrected code here
   ```
4. **Larger fixes**: For changes spanning 6+ lines or multiple locations, describe the fix without a suggestion block

**Important guidelines for inline comments:**
- Post only ONE comment per unique issue (no duplicates)
- Only include a suggestion block if committing it completely fixes the issue
- Include confidence score in the comment (e.g., "Confidence: 92")
- Link to relevant guideline if it's a compliance issue

**If NO issues were found**, post a single summary comment using `gh pr comment`:
```markdown
## Code Review

No issues found (confidence threshold: 80). Checked for:
- Bugs and logic errors
- Security vulnerabilities
- Project guideline compliance
- Jira acceptance criteria (if applicable)
```

**Code link format** (required for proper GitHub rendering):
```
https://github.com/owner/repo/blob/[full-sha]/path/file.ext#L[start]-L[end]
```
- Must use full git SHA (not abbreviated)
- Use `#L` notation for line numbers
- Include at least 1 line of context before and after

Also display the full report locally for immediate feedback.

**Otherwise (no `--comment` flag or no PR):**
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

---
name: code-review
description: Comprehensive code review with specialized agents, Jira integration, and flexible scope (PR or branch diff).
argument-hint: "[--comment] [--base <branch>] [--ticket <KEY>]"
allowed-tools: Bash(gh pr comment:*), Bash(gh pr diff:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(git diff:*), mcp__atlassian__getJiraIssue, mcp__github_inline_comment__create_inline_comment
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
| `--base <branch>` | Base branch for comparison (ignored when PR exists) | `main` |
| `--ticket <KEY>` | Manually specify Jira ticket | Auto-detect |

## False Positive Exclusions

Do NOT flag the following - these are considered false positives:

- **Pre-existing issues**: Problems that existed before this PR/branch
- **Correct code that looks wrong**: Code that appears buggy but is actually correct
- **Pedantic nitpicks**: Minor issues a senior engineer would not flag
- **Linter-catchable issues**: Problems that automated linting will catch (do not run linter to verify)
- **General, non-actionable quality concerns**: Broad comments like "add more tests" or "improve security in general" - still report specific, exploitable vulnerabilities or clearly missing tests directly related to the diff
- **Silenced issues**: Problems mentioned in guidelines but explicitly silenced in code (e.g., via lint ignore comments, `// NOSONAR`, `#pragma warning disable`)
- **Subjective improvements**: Style preferences or "nice to have" refactors without clear benefit
- **Issues outside the diff**: Problems in unchanged code that the PR author didn't touch

## Confidence Scoring

Every issue found must be assigned a confidence score from 0-100:

| Score | Meaning | Action |
|-------|---------|--------|
| 0-25 | Not confident, likely false positive | Do not report |
| 26-50 | Somewhat confident, might be real | Do not report |
| 51-79 | Moderately confident, probably real | Do not report |
| 80-89 | Highly confident, real and important | Report as warning |
| 90-100 | Certain, definitely a real issue | Report as blocker |

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

**PR mode:**
```bash
gh pr view --json files --jq '.files[].path'
```

**Branch mode:**
```bash
git diff --name-only origin/<base>...HEAD
```

### 6. Launch Parallel Review Agents

Launch multiple specialized agents **in parallel** to review the changes from different perspectives. Each agent independently analyzes the diff and returns a list of issues with confidence scores.

**IMPORTANT:** All agents must be launched in a single message to ensure parallel execution.

#### Core Agents (always run)

All review agents inherit behavior from the **Code Review Agent** (`agents/code-review.agent.md`), which defines:
- Core review principles (correctness, security, maintainability, performance, testing)
- Documentation lookup via Context7 and Microsoft Learn
- Review checklist and feedback categories
- Communication style guidelines

| Agent | Model | Focus | Additional Instructions |
|-------|-------|-------|------------------------|
| Guidelines Agent 1 | sonnet | Project conventions | Check diff against CLAUDE.md, AGENTS.md, and .github/copilot-instructions.md. Flag violations where you can quote the exact rule being broken. |
| Guidelines Agent 2 | sonnet | Project conventions | Same as Agent 1 - redundancy to catch different violations. Review independently without seeing Agent 1's findings. |
| Bug Detection Agent | opus | Logic errors | Scan for obvious bugs: syntax errors, type errors, null references, off-by-one errors, logic flaws. Focus only on the diff itself. Flag only issues you're certain about. |
| Security Agent | opus | Vulnerabilities | Check for OWASP Top 10, injection vulnerabilities, auth/authz issues, hardcoded secrets, insecure data handling. Only flag clear vulnerabilities with exploitable paths. |

#### Conditional Agents (run when applicable)

| Agent | Model | Condition | Focus |
|-------|-------|-----------|-------|
| Jira Validation Agent | sonnet | Jira ticket found | Verify implementation matches ticket description, acceptance criteria are addressed, edge cases from ticket are handled. |

#### File-Triggered Agents (run when file patterns match)

Check the list of changed files and include these agents in the parallel launch when patterns match:

| File Patterns | Agent | Model | Description |
|---------------|-------|-------|-------------|
| `*.cs`, `*.csproj`, `*.sln`, `*.fsproj` | .NET Coding Agent | opus | C#/F# best practices, async patterns, SOLID principles, .NET conventions |
| `**/Domain/**/*.cs`, `**/Entities/**/*.cs`, `**/ValueObjects/**/*.cs`, `**/Aggregates/**/*.cs`, `**/DomainEvents/**/*.cs` | DDD Agent | sonnet | Domain model design, aggregate boundaries, invariant enforcement |

To add a new file-triggered agent: add a row to this table.

#### Always-Run Agents (additional)

These agents run on every review in addition to the core agents:

| Agent | Model | Description |
|-------|-------|-------------|
| <!-- Add agents here --> | <!-- Model --> | <!-- Description --> |

To add an always-run agent: add a row to this table. Examples:
- Security scanner (if you want more depth than the core Security Agent)
- Dependency checker
- Documentation validator

#### Agent Launch Instructions

Provide each agent with:
1. The **Code Review Agent** base instructions from `agents/code-review.agent.md`:
   - Core Review Principles
   - Documentation Lookup guidance
   - Review Process
   - Feedback Categories
   - Review Checklist
   - Communication Style
   - (Skip the Jira Integration section and step 1 "Check Branch & Fetch Jira" in Review Process - this command handles Jira)
2. The diff to review
3. The project guidelines (combined instruction files)
4. The PR title and description (for context on author's intent)
5. The False Positive Exclusions list (from this command)
6. The Confidence Scoring guidance (from this command)
7. Jira context (if available - already fetched by this command)

Each agent should:
- Follow the Code Review Agent's review process and checklist
- Use Context7 and Microsoft Learn to verify API usage when uncertain

Each agent must return:
- List of issues found
- For each issue: description, file:line location, confidence score (0-100), reason flagged

> **Note**: The command determines feedback categories from confidence scores (90+ = Blocker, 80-89 = Warning). Agents don't need to provide categories.

### 7. Validate Findings

For each issue returned by the parallel agents, launch a **validation subagent** to verify it's real:

| Issue Type | Validator Model | Validation Task |
|------------|-----------------|-----------------|
| Bug/Logic errors | opus | Verify the bug exists - check if the flagged condition is actually true in the code |
| Guideline violations | sonnet | Verify the rule exists in guidelines and applies to this file path |
| Security issues | opus | Verify the vulnerability is exploitable and not a false positive |

**Validation process:**
1. Provide the validator with: issue description, relevant code context, PR title/description
2. Validator confirms or rejects the issue
3. Rejected issues are filtered out

### 8. Aggregate Validated Findings

Combine validated findings from all parallel agents:

**Aggregation steps:**
1. Collect all validated issues (rejected issues already filtered in step 7)
2. Deduplicate - multiple agents may flag the same issue
3. Filter out any issues with confidence < 80
4. Categorize by severity:
   - **90-100**: Blocker (must fix)
   - **80-89**: Warning/Suggestion (should fix)

**Local report structure:**

```markdown
## Code Review Summary

### Review Stats
- Agents launched: X (Y core + Z specialized)
- Issues found: X
- Issues validated: X
- Issues filtered (< 80 confidence): X

### Jira Context (if available)
**Ticket**: PROJ-123 - [Summary]
**Acceptance Criteria Status**:
- ✅ Criterion 1 - Implemented
- ⚠️ Criterion 2 - Partial
- ❌ Criterion 3 - Missing

### Findings (X issues, threshold: 80)

#### 🚫 Blockers (confidence 90+)
| Issue | Location | Source | Confidence |
|-------|----------|--------|------------|
| [Description] | file.cs:42 | Bug Agent | 95 |

#### ⚠️ Warnings (confidence 80-89)
| Issue | Location | Source | Confidence |
|-------|----------|--------|------------|
| [Description] | file.cs:87 | Guidelines Agent 1 | 82 |

### Summary
- X blocker(s), Y warning(s)
- Z issues filtered (below threshold or failed validation)
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

First, retrieve the repository info and commit SHA:
```bash
gh repo view --json nameWithOwner --jq '.nameWithOwner'  # e.g., "owner/repo"
gh pr view --json headRefOid --jq '.headRefOid'          # full SHA of PR head
```

Then format links as:
```
https://github.com/[owner/repo]/blob/[full-sha]/path/file.ext#L[start]-L[end]
```
- Must use full git SHA (not abbreviated)
- Use `#L` notation for line numbers
- Include at least 1 line of context before and after

Also display the full report locally for immediate feedback.

**Otherwise (no `--comment` flag or no PR):**
- Display the full report locally only
- If `--comment` was set but no PR exists, warn: "No PR found for current branch. Skipping GitHub comment."

## Review Checklist

> This command uses the same review checklist and feedback categories as the Code Review Agent.
> For the authoritative and up-to-date checklist, see the "Review Checklist" section in `agents/code-review.agent.md`.

## Error Handling

- If no changes to review: "No changes found between current branch and origin/<base>"
- If Jira ticket not found: Proceed without Jira context, note this in output
- If specialized agent fails: Log the error, continue with other agents
- If `--comment` fails: Display error, ensure local output still shown

## Configuration

The command uses these template variables (configure in your environment):
- `{{DEFAULT_PROJECT_KEY}}`: Default Jira project key for ticket detection

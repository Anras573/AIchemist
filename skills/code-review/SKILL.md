---
name: Code Review
description: |
  This skill should be used when the user asks to "review my code", "do a code review", "review this PR", "review this pull request", "check my changes", "review changes against main", "review against develop", "post review comments", "review and comment on PR", "code review with Jira context", "review my branch", or asks for a review with specific options like "with --comment", "against base branch". Provides comprehensive code review using parallel specialized agents, confidence-based filtering, Jira integration, and optional inline PR comments.
version: 1.0.0
---

# Code Review Skill

Comprehensive code review using parallel specialized agents, Jira integration, and confidence-based filtering. Automatically adapts to the current branch or open PR.

## Read vs Write Operations

| Type | Operations | Behavior |
|------|------------|----------|
| **Read** | Fetch diff, gather guidelines, read PR details, fetch Jira ticket | Automatic — no confirmation needed |
| **Write** | Post inline PR comments, post summary comment | Requires explicit user confirmation (or `--comment` flag) |

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--comment` | Post findings as inline PR comments | Off (local output only) |
| `--base <branch>` | Base branch for comparison (ignored when PR exists) | `main` |
| `--ticket <KEY>` | Manually specify Jira ticket | Auto-detect from branch/PR |

## False Positive Exclusions

Do NOT flag the following — these are considered false positives:

- **Pre-existing issues**: Problems that existed before this PR/branch
- **Correct code that looks wrong**: Code that appears buggy but is actually correct
- **Pedantic nitpicks**: Minor issues a senior engineer would not flag
- **Linter-catchable issues**: Problems that automated linting will catch (do not run linter to verify)
- **General, non-actionable quality concerns**: Broad comments like "add more tests" or "improve security in general" — still report specific, exploitable vulnerabilities or clearly missing tests directly related to the diff
- **Silenced issues**: Problems mentioned in guidelines but explicitly silenced in code (e.g., via lint ignore comments, `// NOSONAR`, `#pragma warning disable`)
- **Subjective improvements**: Style preferences or "nice to have" refactors without clear benefit
- **Issues outside the diff**: Problems in unchanged code that the PR author didn't touch

## Confidence Scoring

Every issue found must be assigned a confidence score from 0–100:

| Score | Meaning | Action |
|-------|---------|--------|
| 0–25 | Not confident, likely false positive | Do not report |
| 26–50 | Somewhat confident, might be real | Do not report |
| 51–79 | Moderately confident, probably real | Do not report |
| 80–89 | Highly confident, real and important | Report as warning |
| 90–100 | Certain, definitely a real issue | Report as blocker |

**Default threshold: 80** — only issues scoring 80+ are reported.

**Scoring guidance:**
- Syntax/type errors that will fail compilation → 100
- Clear logic errors producing wrong results → 95
- Unambiguous guideline violations (can quote exact rule) → 90
- Security vulnerabilities with clear exploit path → 95
- Performance issues with measurable impact → 85
- Potential issues depending on specific inputs/state → 50 (do not report)

## Workflow

### Step 1 – Determine Review Scope

Check if there's an open PR for the current branch:

```bash
gh pr view --json number,title,body,baseRefName 2>/dev/null
```

**If PR exists:**
- Use PR's base branch for diff (ignore `--base` option)
- Extract PR description for Jira ticket detection
- `--comment` will post to this PR

**If no PR exists:**
- Use `git diff origin/<base>...HEAD` for the diff
- `--comment` should warn that no PR exists and skip commenting

### Step 2 – Gather Project Guidelines

Search for and combine content from these instruction files (if they exist):
- `CLAUDE.md`
- `AGENTS.md`
- `.github/copilot-instructions.md`

Combine all found files into unified context. These guidelines define what patterns, conventions, and standards the review should enforce.

### Step 3 – Detect Jira Ticket

**If `--ticket` option provided:** use the specified ticket directly.

**Otherwise, detect from two sources:**

1. **Branch name**: Match patterns like `feature/PROJ-123-description` or `PROJ-123/description`
   - Regex: `([A-Z]+-\d+)` to extract ticket key

2. **PR description** (if PR exists): Search for Jira ticket references
   - Look for patterns like `PROJ-123`, `[PROJ-123]`, or Jira URLs containing the ticket key

**If both sources return different tickets:** ask the user which ticket is correct before proceeding.

**If ticket found:** fetch the Jira issue using `mcp__atlassian__getJiraIssue`. Extract: summary, description, acceptance criteria, labels. This context verifies the implementation matches requirements.

### Step 4 – Get the Diff

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

### Step 5 – Launch Parallel Review Agents

Launch multiple specialized agents **in parallel** (single message) to review the changes from different perspectives. Each agent independently analyzes the diff and returns a list of issues with confidence scores.

#### Core Agents (always run)

All review agents inherit behavior from the **Code Review Agent** (`agents/code-review.agent.md`), which defines core review principles, documentation lookup via Context7 and Microsoft Learn, the review checklist, feedback categories, and communication style guidelines.

| Agent | Model | Focus | Additional Instructions |
|-------|-------|-------|------------------------|
| Guidelines Agent 1 | sonnet | Project conventions | Check diff against CLAUDE.md, AGENTS.md, and .github/copilot-instructions.md. Flag violations where you can quote the exact rule being broken. |
| Guidelines Agent 2 | sonnet | Project conventions | Same as Agent 1 — redundancy to catch different violations. Review independently without seeing Agent 1's findings. |
| Bug Detection Agent | opus | Logic errors | Scan for obvious bugs: syntax errors, type errors, null references, off-by-one errors, logic flaws. Focus only on the diff itself. Flag only issues you're certain about. |
| Security Agent | opus | Vulnerabilities | Check for OWASP Top 10, injection vulnerabilities, auth/authz issues, hardcoded secrets, insecure data handling. Only flag clear vulnerabilities with exploitable paths. |

#### Conditional Agents

| Agent | Model | Condition | Focus |
|-------|-------|-----------|-------|
| Jira Validation Agent | sonnet | Jira ticket found | Verify implementation matches ticket description, acceptance criteria are addressed, edge cases from ticket are handled. |

#### File-Triggered Agents

Inspect the list of changed files and include these agents when patterns match:

| File Patterns | Agent | Model | Description |
|---------------|-------|-------|-------------|
| `*.cs`, `*.csproj`, `*.sln`, `*.fsproj` | .NET Coding Agent | opus | C#/F# best practices, async patterns, SOLID principles, .NET conventions |
| `**/domain/**/*`, `**/Domain/**/*` | DDD Agent | sonnet | Domain model design, aggregate boundaries, invariant enforcement (any language) |
| `**/entities/**/*`, `**/Entities/**/*` | DDD Agent | sonnet | Entity design, identity patterns |
| `**/value-objects/**/*`, `**/valueobjects/**/*`, `**/ValueObjects/**/*` | DDD Agent | sonnet | Value object immutability, equality |
| `**/aggregates/**/*`, `**/Aggregates/**/*` | DDD Agent | sonnet | Aggregate boundaries, consistency rules |
| `**/domain-events/**/*`, `**/domainevents/**/*`, `**/DomainEvents/**/*` | DDD Agent | sonnet | Domain event design, eventual consistency |

#### Agent Launch Instructions

Provide each agent with:
1. The **Code Review Agent** base instructions from `agents/code-review.agent.md` (skip the Jira Integration section and step 1 "Check Branch & Fetch Jira" in Review Process — the skill handles Jira)
2. The diff to review
3. The project guidelines (combined instruction files)
4. The PR title and description (for context on author's intent)
5. The False Positive Exclusions list (from this skill)
6. The Confidence Scoring guidance (from this skill)
7. Jira context (if available — already fetched by this skill)

Each agent must return:
- List of issues found
- For each issue: description, `file:line` location, confidence score (0–100), reason flagged

### Step 6 – Validate Findings

For each issue returned by the parallel agents, launch a **validation subagent**:

| Issue Type | Validator Model | Validation Task |
|------------|-----------------|-----------------|
| Bug/Logic errors | opus | Verify the bug exists — check if the flagged condition is actually true in the code |
| Guideline violations | sonnet | Verify the rule exists in guidelines and applies to this file path |
| Security issues | opus | Verify the vulnerability is exploitable and not a false positive |

Provide the validator with: issue description, relevant code context, PR title/description. Rejected issues are filtered out.

### Step 7 – Aggregate Validated Findings

1. Collect all validated issues (rejected issues already filtered)
2. Deduplicate — multiple agents may flag the same issue
3. Filter out issues with confidence < 80
4. Categorize by severity:
   - **90–100**: Blocker (must fix)
   - **80–89**: Warning/Suggestion (should fix)

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

### Step 8 – Output Results

**If `--comment` option is set AND PR exists:**

Post findings as inline PR review comments using the GitHub MCP tools. GitHub's review API is a **three-step process** — create a pending review, add comments to it, then submit:

**Step 8a — Create a pending review:**

Use `mcp__plugin_github_github__pull_request_review_write` with `method: "create"` and no `event` parameter. This opens a pending review container that comments are attached to.

**Step 8b — Add inline comments:**

For each issue, use `mcp__plugin_github_github__add_comment_to_pending_review` with:
- `path`: the file path where the issue is located
- `line`: the line number in the diff
- `side`: `"RIGHT"` for new code (additions), `"LEFT"` for removed code
- `body`: the comment body (see format below)

Comment body format:
1. **Description**: Brief explanation of the issue and why it was flagged
2. **Suggestion**: For small, self-contained fixes (< 6 lines), include a committable suggestion block:
   ````
   ```suggestion
   // corrected code here
   ```
   ````
3. **Larger fixes**: For changes spanning 6+ lines or multiple locations, describe the fix without a suggestion block
4. Include confidence score (e.g., `Confidence: 92`) and link to the relevant guideline if it's a compliance issue

**Step 8c — Submit the review:**

Use `mcp__plugin_github_github__pull_request_review_write` with `method: "submit_pending"` and `event: "COMMENT"` (never `REQUEST_CHANGES` or `APPROVE` — the skill is informational only).

**Guidelines for inline comments:**
- Post only ONE comment per unique issue (no duplicates)
- Only include a suggestion block if committing it completely fixes the issue

**If no issues were found**, skip the pending review and post a single summary comment using `gh pr comment`:
```markdown
## Code Review

No issues found (confidence threshold: 80). Checked for:
- Bugs and logic errors
- Security vulnerabilities
- Project guideline compliance
- Jira acceptance criteria (if applicable)
```

**Code link format** (required for proper GitHub rendering):

```bash
gh repo view --json nameWithOwner --jq '.nameWithOwner'  # e.g., "owner/repo"
gh pr view --json headRefOid --jq '.headRefOid'          # full SHA of PR head
```

Format links as: `https://github.com/[owner/repo]/blob/[full-sha]/path/file.ext#L[start]-L[end]`
- Must use full git SHA (not abbreviated)
- Use `#L` notation for line numbers
- Include at least 1 line of context before and after

**If no `--comment` option or no PR:** display the full local report only. If `--comment` was set but no PR exists, warn: "No PR found for current branch. Skipping GitHub comment."

## Error Handling

| Situation | Behavior |
|-----------|----------|
| No changes to review | Report: "No changes found between current branch and `origin/<base>`" |
| Jira ticket not found | Proceed without Jira context; note in output |
| Specialized agent fails | Log the error, continue with remaining agents |
| `--comment` posting fails | Display error; ensure local output is still shown |

## Configuration

Uses `{{DEFAULT_PROJECT_KEY}}` template variable for Jira ticket detection from branch names. Configure in your environment or `CLAUDE.md`.

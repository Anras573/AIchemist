---
name: Jira Management
description: |
  This skill should be used when the user asks to "search Jira tickets", "get ticket details", "check ticket status", "find my tickets", "what am I working on", "create a Jira issue", "update a ticket", "add a comment to ticket", "transition ticket status", "move ticket to done", or mentions Jira issue keys like "PROJ-123". Provides Jira integration for issue management with automatic read operations and confirmed write operations.
version: 1.0.0
---

# Jira Management Skill

This skill provides Jira integration for searching, viewing, creating, and managing issues. **Read operations execute automatically. Write operations require explicit user confirmation.**

## Quick Reference

### Atlassian MCP Tools Available

**READ Operations (Automatic - No Confirmation Needed):**

| Tool | Purpose |
|------|---------|
| `atlassian/searchJiraIssuesUsingJql` | Search issues using JQL queries |
| `atlassian/getJiraIssue` | Fetch single issue details by key |
| `atlassian/getVisibleJiraProjects` | List accessible projects |
| `atlassian/getJiraProjectIssueTypesMetadata` | Get issue type metadata for a project |
| `atlassian/atlassianUserInfo` | Fetch current user information |
| `atlassian/getTransitionsForJiraIssue` | Get available status transitions |
| `atlassian/lookupJiraAccountId` | Look up user account IDs |
| `atlassian/search` | Rovo Search across Jira and Confluence |
| `atlassian/getJiraIssueRemoteIssueLinks` | Get remote issue links |

**WRITE Operations (Confirmation Required):**

| Tool | Purpose | Confirmation Message |
|------|---------|---------------------|
| `atlassian/createJiraIssue` | Create new issue | "Create issue '[summary]' in [project]?" |
| `atlassian/editJiraIssue` | Update issue fields | "Update [field] on [issue-key] to '[value]'?" |
| `atlassian/transitionJiraIssue` | Change issue status | "Move [issue-key] to [status]?" |
| `atlassian/addCommentToJiraIssue` | Add comment to issue | "Add comment to [issue-key]?" |
| `atlassian/addWorklogToJiraIssue` | Log work on issue | "Log [time] on [issue-key]?" |

## Configuration Management

### First-Run Setup

On first use, check for configuration at `${CLAUDE_PLUGIN_ROOT}/config.json`:

**If config exists:** Load and use cached user information for JQL queries.

**If config missing:** Use `AskUserQuestion` to ask:
> "I don't have your Atlassian user info cached. Should I fetch and save it to speed up future queries?"

If confirmed, use `atlassianUserInfo` to fetch details and write to config file.

### Config Structure

```json
{
  "atlassian": {
    "account_id": "...",
    "email": "...",
    "name": "..."
  },
  "defaults": {
    "project_key": "..."
  }
}
```

## Core Workflows

### Searching Issues

For any search request, build appropriate JQL and use `atlassian/searchJiraIssuesUsingJql`:

```
# Find user's assigned tickets
assignee = currentUser() ORDER BY updated DESC

# Find tickets by status
project = PROJ AND status = "In Progress"

# Find recent tickets
project = PROJ AND updated >= -7d ORDER BY updated DESC
```

### Viewing Issue Details

Use `atlassian/getJiraIssue` with the issue key. Present results clearly:
- **Summary** and **Description**
- **Status**, **Priority**, **Type**
- **Assignee** and **Reporter**
- **Labels** and **Components**
- **Created** and **Updated** dates

### Creating Issues (Confirmation Required)

Before calling `atlassian/createJiraIssue`, use `AskUserQuestion`:

```
Question: "Create this Jira issue?"
Options:
  - "Yes, create it" - Proceed with creation
  - "Edit details first" - Let user modify before creating
  - "Cancel" - Abort the operation
```

Show the issue details being created:
- Project, Issue Type, Summary
- Description (if provided)
- Priority, Labels, Assignee (if specified)

### Updating Issues (Confirmation Required)

Before calling `atlassian/editJiraIssue`, use `AskUserQuestion`:

```
Question: "Update [ISSUE-KEY]?"
Options:
  - "Yes, update it" - Proceed with update
  - "Show current values first" - Fetch and display current state
  - "Cancel" - Abort the operation
```

### Transitioning Issues (Confirmation Required)

1. First, use `atlassian/getTransitionsForJiraIssue` to get available transitions
2. Present options to user
3. Before calling `atlassian/transitionJiraIssue`, use `AskUserQuestion`:

```
Question: "Move [ISSUE-KEY] from [current-status] to [new-status]?"
Options:
  - "Yes, transition it" - Proceed with transition
  - "Choose different status" - Show other available transitions
  - "Cancel" - Abort the operation
```

### Adding Comments (Confirmation Required)

Before calling `atlassian/addCommentToJiraIssue`, use `AskUserQuestion`:

```
Question: "Add this comment to [ISSUE-KEY]?"
Options:
  - "Yes, add comment" - Proceed
  - "Edit comment first" - Let user modify
  - "Cancel" - Abort
```

Show the comment text being added.

## Write Operation Confirmation Pattern

**CRITICAL:** For ALL write operations, follow this pattern:

1. **Prepare** - Gather all necessary information
2. **Preview** - Show user exactly what will happen
3. **Confirm** - Use `AskUserQuestion` with clear options
4. **Execute** - Only proceed if user confirms
5. **Report** - Confirm success or explain failure

Example confirmation flow:

```markdown
I'm ready to create this issue:

**Project:** PROJ
**Type:** Bug
**Summary:** Login button not responding on mobile
**Priority:** High

[Use AskUserQuestion to confirm]
```

## Common JQL Patterns

```sql
-- My open tickets
assignee = currentUser() AND status != Done ORDER BY priority DESC

-- Recently updated in project
project = PROJ AND updated >= -7d ORDER BY updated DESC

-- High priority bugs
project = PROJ AND type = Bug AND priority in (High, Highest)

-- Tickets in sprint
project = PROJ AND sprint in openSprints()

-- Tickets I created
reporter = currentUser() ORDER BY created DESC

-- Unassigned tickets
project = PROJ AND assignee is EMPTY

-- Tickets with specific label
project = PROJ AND labels = "needs-review"
```

## Error Handling

**Authentication errors:** Guide user to check Atlassian MCP server configuration.

**Permission errors:** Explain required permissions and suggest contacting Jira admin.

**Not found errors:** Verify issue key format and project access.

**Validation errors:** Show which fields failed validation and expected formats.

## Additional Resources

For detailed JQL syntax and advanced patterns, see `references/jql-patterns.md`.
For issue type metadata and field schemas, see `references/issue-types.md`.

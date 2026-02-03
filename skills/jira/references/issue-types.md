# Jira Issue Types Reference

## Standard Issue Types

### Epic

**Purpose:** Large body of work that can be broken down into smaller stories

**Typical Fields:**
- Summary (required)
- Description
- Epic Name (unique identifier)
- Start Date
- Due Date
- Labels

**Hierarchy:** Contains Stories, Tasks, Bugs

### Story

**Purpose:** User-facing feature or requirement

**Typical Fields:**
- Summary (required)
- Description
- Story Points
- Sprint
- Epic Link
- Acceptance Criteria

**Format:** "As a [user], I want [feature], so that [benefit]"

### Task

**Purpose:** Technical work item not directly user-facing

**Typical Fields:**
- Summary (required)
- Description
- Time Tracking (Original Estimate, Time Spent)
- Sprint
- Epic Link

### Bug

**Purpose:** Defect or problem in existing functionality

**Typical Fields:**
- Summary (required)
- Description
- Steps to Reproduce
- Expected Result
- Actual Result
- Environment
- Severity
- Affected Version
- Fix Version

### Sub-task

**Purpose:** Smaller unit of work within a parent issue

**Typical Fields:**
- Summary (required)
- Parent (required - must be Story, Task, or Bug)
- Description
- Time Tracking

**Note:** Cannot exist without parent issue

## Issue Creation Requirements

### Using `atlassian/createJiraIssue`

**Required Parameters:**
- `cloudId` - Atlassian Cloud ID
- `projectKey` - Project identifier (e.g., "PROJ")
- `issueTypeName` - Type name (e.g., "Bug", "Story", "Task")
- `summary` - Brief issue title

**Optional Parameters:**
- `description` - Detailed description (Markdown supported)
- `assignee_account_id` - User to assign
- `parent` - Parent issue key (for sub-tasks)
- `additional_fields` - Object with custom fields

### Field Discovery

To discover available fields for a project/issue type:

1. Get project metadata:
```
atlassian/getVisibleJiraProjects
```

2. Get issue type metadata:
```
atlassian/getJiraProjectIssueTypesMetadata
  projectIdOrKey: "PROJ"
```

3. Get field details for specific issue type:
```
atlassian/getJiraIssueTypeMetaWithFields
  projectIdOrKey: "PROJ"
  issueTypeId: "10001"
```

## Issue Transitions

### Standard Workflow States

| Status | Category | Description |
|--------|----------|-------------|
| Open | To Do | Newly created, not started |
| To Do | To Do | Ready to be worked on |
| In Progress | In Progress | Actively being worked on |
| In Review | In Progress | Code review or QA |
| Done | Done | Completed successfully |
| Closed | Done | Verified and closed |

### Getting Available Transitions

Use `atlassian/getTransitionsForJiraIssue` to get valid transitions:

```json
{
  "issueIdOrKey": "PROJ-123"
}
```

Response includes:
- `id` - Transition ID (used in transitionJiraIssue)
- `name` - Display name
- `to` - Target status
- `hasScreen` - Whether transition shows a screen

### Executing Transitions

Use `atlassian/transitionJiraIssue`:

```json
{
  "issueIdOrKey": "PROJ-123",
  "transition": {
    "id": "21"
  }
}
```

Optional fields during transition:
- `fields` - Update fields during transition
- `update` - Add comments, worklogs
- `historyMetadata` - Transition context

## Issue Updates

### Using `atlassian/editJiraIssue`

**Common Field Updates:**

```json
{
  "issueIdOrKey": "PROJ-123",
  "fields": {
    "summary": "New summary",
    "description": "Updated description",
    "priority": { "name": "High" },
    "labels": ["label1", "label2"],
    "assignee": { "accountId": "..." }
  }
}
```

### Field Types

**Text Fields:**
```json
{ "summary": "Text value" }
```

**User Fields:**
```json
{ "assignee": { "accountId": "123abc..." } }
```

**Option Fields:**
```json
{ "priority": { "name": "High" } }
```

**Array Fields:**
```json
{ "labels": ["label1", "label2"] }
```

**Date Fields:**
```json
{ "duedate": "2024-12-31" }
```

## Comments

### Adding Comments

Use `atlassian/addCommentToJiraIssue`:

```json
{
  "issueIdOrKey": "PROJ-123",
  "commentBody": "Comment text in **Markdown**"
}
```

### Comment Visibility

Restrict comment visibility:

```json
{
  "commentVisibility": {
    "type": "role",
    "value": "Developers"
  }
}
```

## Work Logging

### Adding Worklogs

Use `atlassian/addWorklogToJiraIssue`:

```json
{
  "issueIdOrKey": "PROJ-123",
  "timeSpent": "2h 30m"
}
```

**Time Format:**
- `2h` - 2 hours
- `30m` - 30 minutes
- `1d` - 1 day (typically 8 hours)
- `1w` - 1 week (typically 5 days)
- `2h 30m` - Combined

## Best Practices

### Issue Creation

1. **Clear Summaries:** Action-oriented, specific
   - Good: "Fix null pointer in UserService.login()"
   - Bad: "Bug fix"

2. **Complete Descriptions:** Include context, steps, expectations

3. **Appropriate Type:** Match issue type to work nature

4. **Correct Project:** Verify project before creation

### Issue Updates

1. **Verify First:** Read current state before updating
2. **Minimal Changes:** Update only necessary fields
3. **Add Context:** Use comments to explain changes
4. **Log Time:** Track effort for reporting

### Transitions

1. **Valid Transitions:** Only use available transitions
2. **Required Fields:** Some transitions require field updates
3. **Comments:** Add transition comments for context

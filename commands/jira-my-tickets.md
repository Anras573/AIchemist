---
name: jira-my-tickets
description: Show all Jira tickets you've been involved with (as assignee or creator) since a specified date.
---

# My Jira Tickets Command

This command retrieves all Jira issues where you are either the assignee or the reporter (creator) since a specified date.

## Usage

Invoke with: `/jira-my-tickets [date]`

Examples:
- `/jira-my-tickets 2025-01-01`
- `/jira-my-tickets last week`
- `/jira-my-tickets 2024-12-15`

## Configuration

This command requires your Atlassian account ID. Replace the placeholder below with your actual account ID:

```
Account ID: {{ATLASSIAN_ACCOUNT_ID}}
```

To find your account ID, visit your Atlassian profile or use the `atlassianUserInfo` MCP tool.

## Execution Steps

When this command is invoked:

1. **Parse the date**: Extract the date from the user's input. Accept formats like:
   - ISO format: `2025-01-01`
   - Relative: `last week`, `last month`, `30 days ago`
   - Convert relative dates to JQL format (e.g., `-7d`, `-1w`, `-30d`)

2. **Build the JQL query**:
   ```
   (assignee = "{{ATLASSIAN_ACCOUNT_ID}}" OR reporter = "{{ATLASSIAN_ACCOUNT_ID}}") AND updated >= "YYYY-MM-DD" ORDER BY updated DESC
   ```

3. **Execute the search**: Use the `mcp__atlassian__searchJiraIssuesUsingJql` tool with:
   - The constructed JQL query
   - Fields: `summary`, `status`, `issuetype`, `priority`, `created`, `updated`, `assignee`, `reporter`

4. **Present results**: Display the issues in a clear table format:
   | Key | Type | Summary | Status | Role | Updated |
   |-----|------|---------|--------|------|---------|

   Where "Role" indicates whether the user is "Assignee", "Reporter", or "Both".

5. **Summarize**: Provide a brief summary:
   - Total issues found
   - Breakdown by role (assignee vs reporter)
   - Breakdown by status

## Error Handling

- If no date is provided, ask the user for one
- If no issues are found, confirm the search was successful but returned no results
- If the account ID placeholder hasn't been replaced, remind the user to configure it

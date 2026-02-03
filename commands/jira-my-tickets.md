---
name: jira-my-tickets
description: Show all Jira tickets you've been involved with (as assignee or creator) since a specified date.
argument-hint: "<date> (e.g., 2025-01-01, 'last week')"
allowed-tools: mcp__atlassian__searchJiraIssuesUsingJql, mcp__atlassian__atlassianUserInfo, Read, Write
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

This command uses your Atlassian account information from `${CLAUDE_PLUGIN_ROOT}/config.json`.

**If the config file exists**: Read `atlassian.account_id` and use it directly.

**If the config file is missing or incomplete**:
1. Use `atlassianUserInfo` to fetch your Atlassian user details
2. Ask the user: "Would you like me to save your Atlassian info for future use? This avoids fetching it each time."
3. If yes: Create `${CLAUDE_PLUGIN_ROOT}/config.json` with the full schema (matching the Jira skill):
   ```json
   {
     "atlassian": {
       "account_id": "<your Atlassian account ID>",
       "email": "<your Atlassian email>",
       "name": "<your full name>",
       "nickname": "<your display name>",
       "locale": "<your locale, e.g. en-US>"
     },
     "defaults": {
       "project_key": "<optional: default Jira project key>"
     }
   }
   ```
4. If no: Use the fetched account ID for this session only without saving

## Execution Steps

When this command is invoked:

1. **Parse the date**: Extract the date from the user's input. Accept formats like:
   - ISO format: `2025-01-01`
   - Relative: `last week`, `last month`, `30 days ago`
   - Convert relative dates to JQL format (e.g., `-7d`, `-1w`, `-30d`)

2. **Build the JQL query** using the loaded or fetched account ID:
   ```
   (assignee = "<account_id>" OR reporter = "<account_id>") AND updated >= "YYYY-MM-DD" ORDER BY updated DESC
   ```
   Replace `<account_id>` with the value from `atlassian.account_id` in the config file (or the session value if not cached).

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
- If the config file is missing and user declines to cache, proceed with session-only fetch
- If `atlassianUserInfo` fails, inform the user and suggest checking their Atlassian authentication

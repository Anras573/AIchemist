# Write Operation Confirmation Examples

This file demonstrates how to use `AskUserQuestion` for write operation confirmations.

## Creating an Issue

**User Request:** "Create a bug ticket for the login timeout issue"

**Step 1: Gather Information**
```
Summary: Login timeout on mobile devices
Type: Bug
Project: PROJ (from config or ask user)
Priority: High (inferred or ask user)
```

**Step 2: Present Preview**
```markdown
I'll create this bug ticket:

**Project:** PROJ
**Type:** Bug
**Summary:** Login timeout on mobile devices
**Priority:** High
**Description:** Users report login timeouts when accessing the application on mobile devices.
```

**Step 3: Use AskUserQuestion**
```json
{
  "questions": [{
    "question": "Create this Jira bug ticket?",
    "header": "Create Bug",
    "options": [
      {
        "label": "Yes, create it",
        "description": "Create the bug ticket in PROJ with the details shown above"
      },
      {
        "label": "Edit details first",
        "description": "Modify the summary, description, or priority before creating"
      },
      {
        "label": "Cancel",
        "description": "Don't create the ticket"
      }
    ],
    "multiSelect": false
  }]
}
```

**Step 4: Execute (only if confirmed)**
```
atlassian/createJiraIssue with gathered parameters
```

---

## Transitioning an Issue

**User Request:** "Move PROJ-123 to done"

**Step 1: Get Current State**
```
atlassian/getJiraIssue - Get current status
atlassian/getTransitionsForJiraIssue - Get available transitions
```

**Step 2: Present Options**
```markdown
**PROJ-123** is currently "In Review"

Available transitions:
- Done
- Back to In Progress
- Rejected
```

**Step 3: Use AskUserQuestion**
```json
{
  "questions": [{
    "question": "Move PROJ-123 from 'In Review' to 'Done'?",
    "header": "Transition",
    "options": [
      {
        "label": "Yes, mark as Done",
        "description": "Transition PROJ-123 to Done status"
      },
      {
        "label": "Choose different status",
        "description": "Select from other available transitions"
      },
      {
        "label": "Cancel",
        "description": "Keep current status"
      }
    ],
    "multiSelect": false
  }]
}
```

---

## Updating an Issue

**User Request:** "Change the priority of PROJ-456 to critical"

**Step 1: Get Current State**
```
atlassian/getJiraIssue - Verify issue exists, get current priority
```

**Step 2: Present Change**
```markdown
**PROJ-456:** Database connection pool exhaustion

Current Priority: High
New Priority: Critical
```

**Step 3: Use AskUserQuestion**
```json
{
  "questions": [{
    "question": "Update PROJ-456 priority from High to Critical?",
    "header": "Update",
    "options": [
      {
        "label": "Yes, update priority",
        "description": "Change priority to Critical"
      },
      {
        "label": "Show full issue details",
        "description": "View complete issue before updating"
      },
      {
        "label": "Cancel",
        "description": "Keep current priority"
      }
    ],
    "multiSelect": false
  }]
}
```

---

## Adding a Comment

**User Request:** "Add a comment to PROJ-789 saying the fix is deployed"

**Step 1: Prepare Comment**
```markdown
The fix has been deployed to production. Please verify and close if resolved.
```

**Step 2: Use AskUserQuestion**
```json
{
  "questions": [{
    "question": "Add this comment to PROJ-789?",
    "header": "Comment",
    "options": [
      {
        "label": "Yes, add comment",
        "description": "Post the comment to PROJ-789"
      },
      {
        "label": "Edit comment first",
        "description": "Modify the comment text before posting"
      },
      {
        "label": "Cancel",
        "description": "Don't add comment"
      }
    ],
    "multiSelect": false
  }]
}
```

---

## Logging Work

**User Request:** "Log 2 hours on PROJ-101"

**Step 1: Present Worklog**
```markdown
**Issue:** PROJ-101 - Implement user authentication
**Time to Log:** 2 hours
```

**Step 2: Use AskUserQuestion**
```json
{
  "questions": [{
    "question": "Log 2 hours of work on PROJ-101?",
    "header": "Log Work",
    "options": [
      {
        "label": "Yes, log time",
        "description": "Add 2h worklog to PROJ-101"
      },
      {
        "label": "Change time amount",
        "description": "Specify a different amount of time"
      },
      {
        "label": "Cancel",
        "description": "Don't log time"
      }
    ],
    "multiSelect": false
  }]
}
```

---

## Handling User Responses

### If "Yes" selected:
Execute the write operation and confirm success:
```
Created PROJ-124: "Login timeout on mobile devices"
```

### If "Edit" selected:
Ask follow-up questions to gather corrections, then re-confirm.

### If "Cancel" selected:
Acknowledge and move on:
```
Okay, I won't create the ticket.
```

### If "Other" selected (custom input):
Parse user's custom response and adjust accordingly.

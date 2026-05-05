---
name: calendar
description: |
  This skill should be used when the user asks about "my calendar", "what's on my schedule", "what meetings do I have", "what's today's agenda", "what's coming up this week", "next meeting", "prepare me for my next meeting", "meeting prep", "brief me on", "briefing for", or asks about specific calendar events. Provides Microsoft 365 calendar integration via the m365 CLI.
version: 1.0.0
---

# Calendar Skill

Fetch and interpret Microsoft 365 calendar events via `tools/msgraph.sh`. Primary use cases: daily schedule overview, upcoming events, and meeting preparation briefings.

Calendar queries are **read-only** — no confirmation needed. Authentication commands (`login`/`logout`) manage local credentials and are a one-time setup step.

## Prerequisites

1. **Environment variables** exported in your shell profile (`.zshrc` / `.bash_profile`):
   ```bash
   export MSGRAPH_APP_ID=<your-azure-app-id>
   export MSGRAPH_TENANT_ID=<your-azure-tenant-id>
   ```

2. **Authenticated once**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/tools/msgraph.sh login
   ```
   This opens a browser window for Microsoft OAuth login. Tokens are cached by m365 and auto-refreshed.

   The script uses `m365` if installed globally, otherwise falls back to `npx` automatically. Install globally for faster startup:
   ```bash
   npm install -g @pnp/cli-microsoft365
   ```

## Available Commands

| Command | What it does |
|---------|-------------|
| `msgraph.sh get-events [--start ISO] [--end ISO]` | List events in a time range (default: now → +7 days) |
| `msgraph.sh get-event-detail EVENT_ID` | Full event details including body/description |
| `msgraph.sh login` | Authenticate (browser OAuth) |
| `msgraph.sh logout` | Clear cached tokens |

## ISO 8601 Time Helpers (macOS)

Use local time with UTC offset (`%z`) so day boundaries match the user's timezone:

```bash
# Now (local time)
date +"%Y-%m-%dT%H:%M:%S%z"

# Start / end of today (local time)
date +"%Y-%m-%dT00:00:00%z"
date +"%Y-%m-%dT23:59:59%z"

# 2 hours from now — BSD (macOS) / GNU fallback
date -v+2H +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || date -d "+2 hours" +"%Y-%m-%dT%H:%M:%S%z"

# 7 days from now — BSD (macOS) / GNU fallback
date -v+7d +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || date -d "+7 days" +"%Y-%m-%dT%H:%M:%S%z"
```

## Core Workflows

### Today's Schedule

```bash
${CLAUDE_PLUGIN_ROOT}/tools/msgraph.sh get-events \
  --start "$(date +"%Y-%m-%dT00:00:00%z")" \
  --end "$(date +"%Y-%m-%dT23:59:59%z")"
```

Present as:

```
## Today's Schedule — [Weekday, Month Day]

**HH:MM – HH:MM**  Event Subject
  📍 Location (or "Online Meeting" if isOnlineMeeting is true)
  🔗 Join: [onlineMeetingUrl if present]

[N events total]
```

If the array is empty: "Your calendar is clear today."

### Upcoming Events (Next N Days)

Use the default `get-events` (no flags = next 7 days). Group output by day:

```
## Upcoming Events

### Monday, May 5
- 09:00 – 09:30  Standup
- 14:00 – 15:00  Design Review

### Tuesday, May 6
- 11:00 – 12:00  1:1 with Manager
```

### Next Meeting

Fetch events from now to 2 hours from now:

```bash
${CLAUDE_PLUGIN_ROOT}/tools/msgraph.sh get-events \
  --start "$(date +"%Y-%m-%dT%H:%M:%S%z")" \
  --end "$(date -v+2H +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || date -d "+2 hours" +"%Y-%m-%dT%H:%M:%S%z")"
```

If the result is empty, extend to end of day.

### Meeting Prep / Briefing

The primary high-value workflow. When asked to "prepare for" or "brief me on" a meeting:

1. Run `get-events` to locate the event (use a narrow window if the meeting is specific)
2. Take the event `id` and run `get-event-detail` for the full body:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/tools/msgraph.sh get-event-detail "EVENT_ID"
   ```
3. The `body.content` field may be HTML — extract readable text. Strip tracking pixels, signatures, and boilerplate footers. Keep agenda items, questions, pre-reads, and attendee lists.
4. Present a structured brief:

```
## Meeting Brief: [Subject]

**When:** [Weekday, Date] at HH:MM – HH:MM
**Where:** [location.displayName] / Online
**Join:** [onlineMeetingUrl if present]

### Agenda / Description
[Cleaned body content — key points only]

### Suggested Prep
- [Action items or questions visible in the body]
- [Pre-reads if mentioned]
```

## Cross-Skill Integrations

### Calendar → Daily Note
After fetching today's schedule, offer to append it to the daily note:
> "Want me to add today's schedule to your daily note?"
Use the `daily-note` skill to append.

### Calendar → Capture (Obsidian)
After generating a meeting brief, offer to save it to the vault:
> "Want me to save this brief to your vault?"
Use the `capture` skill to write to `Meeting Notes/[Subject]`.

### Calendar → Jira
If a meeting description mentions Jira issue keys (e.g. `PROJ-123`), extract them and offer to fetch their current status via the `jira` skill.

## Error Handling

**Not logged in / token expired:**
```
Calendar access requires authentication. Run:
  ${CLAUDE_PLUGIN_ROOT}/tools/msgraph.sh login
Then retry.
```

**MSGRAPH_APP_ID / MSGRAPH_TENANT_ID not set:**
```
Missing environment variables. Add to your shell profile:
  export MSGRAPH_APP_ID=<your-app-id>
  export MSGRAPH_TENANT_ID=<your-tenant-id>
Then open a new terminal and retry.
```

**No events in range:**
"No events found between [start] and [end]."
Suggest: widen the window or verify the account has calendar events.

**Event detail fetch fails:**
Fall back to the summary data from `get-events` (subject, start, end, location). Note: "Full event description unavailable."

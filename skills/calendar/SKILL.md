---
name: calendar
description: |
  This skill should be used when the user asks about "my calendar", "what's on my schedule", "what meetings do I have", "what's today's agenda", "what's coming up this week", "next meeting", "prepare me for my next meeting", "meeting prep", "brief me on", "briefing for", or asks about specific calendar events. Provides Microsoft 365 calendar integration via the m365 CLI.
version: 1.0.0
---

# Calendar Skill

Fetch and interpret Microsoft 365 calendar events via `tools/msgraph.sh`. Primary use cases: daily schedule overview, upcoming events, and meeting preparation briefings.

All operations are **read-only** — no confirmation needed.

## Prerequisites

1. **m365 CLI installed** (or available via npx):
   ```bash
   npm install -g @pnp/cli-microsoft365
   ```

2. **Environment variables** exported in your shell profile (`.zshrc` / `.bash_profile`):
   ```bash
   export MSGRAPH_APP_ID=<your-azure-app-id>
   export MSGRAPH_TENANT_ID=<your-azure-tenant-id>
   ```

3. **Authenticated once**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/tools/msgraph.sh login
   ```
   This opens a browser window for Microsoft OAuth login. Tokens are cached by m365 and auto-refreshed.

## Available Commands

| Command | What it does |
|---------|-------------|
| `msgraph.sh get-events [--start ISO] [--end ISO]` | List events in a time range (default: now → +7 days) |
| `msgraph.sh get-event-detail EVENT_ID` | Full event details including body/description |
| `msgraph.sh login` | Authenticate (browser OAuth) |
| `msgraph.sh logout` | Clear cached tokens |

## ISO 8601 Time Helpers (macOS)

```bash
# Now
date -u +"%Y-%m-%dT%H:%M:%SZ"

# Start / end of today
date -u +"%Y-%m-%dT00:00:00Z"
date -u +"%Y-%m-%dT23:59:59Z"

# 2 hours from now
date -u -v+2H +"%Y-%m-%dT%H:%M:%SZ"

# 7 days from now
date -u -v+7d +"%Y-%m-%dT%H:%M:%SZ"
```

## Core Workflows

### Today's Schedule

```bash
${CLAUDE_PLUGIN_ROOT}/tools/msgraph.sh get-events \
  --start "$(date -u +"%Y-%m-%dT00:00:00Z")" \
  --end "$(date -u +"%Y-%m-%dT23:59:59Z")"
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
  --start "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --end "$(date -u -v+2H +"%Y-%m-%dT%H:%M:%SZ")"
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

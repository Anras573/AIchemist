---
name: calendar
description: |
  This skill should be used when the user asks about "my calendar", "what's on my schedule", "what meetings do I have", "what's today's agenda", "what's coming up this week", "next meeting", "prepare me for my next meeting", "meeting prep", "brief me on", "briefing for", or asks about specific calendar events. Provides read-only calendar integration for Microsoft 365 (via the m365 CLI) and iCloud or other CalDAV servers.
version: 1.1.0
---

# Calendar Skill

Fetch and interpret calendar events via `tools/calendar.sh`, which runs one of two backends with the same commands and the same JSON output:

| Backend | Script | For |
|---------|--------|-----|
| Microsoft 365 | `tools/msgraph.sh` | Work calendars in Outlook / Microsoft 365, via the m365 CLI |
| CalDAV | `tools/caldav.sh` | iCloud by default; also other CalDAV servers (Fastmail, Nextcloud, Radicale) via `CALDAV_URL` |

Primary use cases: daily schedule overview, upcoming events, and meeting preparation briefings.

Calendar queries are **read-only** — no confirmation needed. Microsoft 365's `login`/`logout` manage local credentials and are a one-time setup step.

## Prerequisites

**python3** must be in `PATH` (pre-installed on macOS; verify with `python3 --version`). Then set up **one** backend. `calendar.sh` uses Microsoft 365 when its variables are set, otherwise CalDAV; set `CALENDAR_PROVIDER=msgraph` or `CALENDAR_PROVIDER=caldav` to choose explicitly.

### Microsoft 365

1. **Environment variables** exported in your shell profile (`.zshrc` / `.bash_profile`):
   ```bash
   export MSGRAPH_APP_ID=<your-azure-app-id>
   export MSGRAPH_TENANT_ID=<your-azure-tenant-id>
   ```

2. **Authenticated once**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/tools/calendar.sh login
   ```
   This opens a browser window for Microsoft OAuth login. Tokens are cached by m365 and auto-refreshed.

   The script uses `m365` if installed globally, otherwise falls back to `npx` automatically. Install globally for faster startup:
   ```bash
   npm install -g @pnp/cli-microsoft365
   ```

### iCloud (CalDAV)

1. **Create an app-specific password** at [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords. iCloud does not accept your Apple ID password over CalDAV.

2. **Environment variables** exported in your shell profile:
   ```bash
   export CALDAV_USERNAME=<your-apple-id-email>
   # Either the app-specific password itself...
   export CALDAV_PASSWORD=<app-specific-password>
   # ...or, better, a command that prints it, e.g. from the macOS keychain:
   export CALDAV_PASSWORD_CMD='security find-generic-password -s icloud-caldav -w'
   ```
   To store it in the keychain: `security add-generic-password -s icloud-caldav -a "$CALDAV_USERNAME" -w`.

   For another CalDAV server, also set `CALDAV_URL` (default `https://caldav.icloud.com/`).

3. **Check the setup**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/tools/calendar.sh check
   ```

## Available Commands

| Command | What it does |
|---------|-------------|
| `calendar.sh list-calendars` | List all calendars (name and id; Microsoft 365 also flags the default, both flag read-only ones) |
| `calendar.sh get-events [--start ISO] [--end ISO] [--calendar-id ID]` | List events in a time range (default: now → +7 days). Recurring events are expanded into individual occurrences. |
| `calendar.sh get-event-detail EVENT_ID` | Full event details including body/description, organizer and attendees |
| `calendar.sh provider` | Print the backend in use (`msgraph` or `caldav`) |
| `calendar.sh login` / `logout` | Microsoft 365 only: authenticate (browser OAuth) / clear cached tokens |
| `calendar.sh check` | CalDAV only: verify the credentials and count the event calendars |

`--calendar-id` is optional; obtain IDs from `list-calendars`. Without it, Microsoft 365 reads the default calendar and CalDAV reads **every** event calendar on the account (iCloud has no default calendar). Reminders and task lists are never included.

## ISO 8601 Time Helpers

Both backends require ISO 8601 timestamps with a `+HH:MM` UTC offset (e.g. `2026-05-11T09:00:00+02:00`). Use Python — `date +"%z"` on macOS (BSD) emits `+0200` without the colon, which is invalid:

```bash
# Now (local time with +HH:MM offset)
python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).astimezone().isoformat(timespec='seconds'))"

# N days from now (DST-correct: .astimezone() applied after timedelta)
python3 -c "import sys; from datetime import datetime, timezone, timedelta; print((datetime.now(timezone.utc) + timedelta(days=int(sys.argv[1]))).astimezone().isoformat(timespec='seconds'))" 7

# Start of today (midnight local time)
python3 -c "from datetime import datetime, timezone; d=datetime.now(timezone.utc).astimezone(); print(d.replace(hour=0,minute=0,second=0,microsecond=0).isoformat(timespec='seconds'))"

# End of today (23:59:59 local time)
python3 -c "from datetime import datetime, timezone; d=datetime.now(timezone.utc).astimezone(); print(d.replace(hour=23,minute=59,second=59,microsecond=0).isoformat(timespec='seconds'))"
```

## Core Workflows

### Today's Schedule

```bash
${CLAUDE_PLUGIN_ROOT}/tools/calendar.sh get-events \
  --start "$(python3 -c 'from datetime import datetime,timezone; d=datetime.now(timezone.utc).astimezone(); print(d.replace(hour=0,minute=0,second=0,microsecond=0).isoformat(timespec="seconds"))')" \
  --end "$(python3 -c 'from datetime import datetime,timezone; d=datetime.now(timezone.utc).astimezone(); print(d.replace(hour=23,minute=59,second=59,microsecond=0).isoformat(timespec="seconds"))')"
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
${CLAUDE_PLUGIN_ROOT}/tools/calendar.sh get-events \
  --start "$(python3 -c 'from datetime import datetime,timezone; print(datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"))')" \
  --end "$(python3 -c 'from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)+timedelta(hours=2)).astimezone().isoformat(timespec="seconds"))')"
```

If the result is empty, extend to end of day.

### Meeting Prep / Briefing

The primary high-value workflow. When asked to "prepare for" or "brief me on" a meeting:

1. Run `get-events` to locate the event (use a narrow window if the meeting is specific)
2. Take the event `id` and run `get-event-detail` for the full body:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/tools/calendar.sh get-event-detail "EVENT_ID"
   ```
3. The `body.content` field may be HTML (Microsoft 365) or plain text (CalDAV) — extract readable text. Strip tracking pixels, signatures, and boilerplate footers. Keep agenda items, questions, pre-reads, and attendee lists (`attendees` and `organizer` hold names and addresses).
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

**No calendar configured** (`calendar.sh` exits 2):
```
No calendar is set up. Export one of these in your shell profile:
  Microsoft 365: MSGRAPH_APP_ID and MSGRAPH_TENANT_ID
  iCloud:        CALDAV_USERNAME and CALDAV_PASSWORD (or CALDAV_PASSWORD_CMD)
Then open a new terminal and retry.
```

**Microsoft 365 — not logged in / token expired:**
```
Calendar access requires authentication. Run:
  ${CLAUDE_PLUGIN_ROOT}/tools/calendar.sh login
Then retry.
```

**Microsoft 365 — MSGRAPH_APP_ID / MSGRAPH_TENANT_ID not set:**
```
Missing environment variables. Add to your shell profile:
  export MSGRAPH_APP_ID=<your-app-id>
  export MSGRAPH_TENANT_ID=<your-tenant-id>
Then open a new terminal and retry.
```

**CalDAV — `authentication failed (401)`:**
```
iCloud rejected the credentials. Check that CALDAV_USERNAME is your Apple ID email
and that the password is an app-specific password (not your Apple ID password).
Create one at account.apple.com → Sign-In and Security → App-Specific Passwords.
```

**CalDAV — `recurrence rule not supported here`** (a warning, not a failure): the server returned a recurring event unexpanded and its rule is beyond the built-in expansion. Only the first occurrence is listed; mention that the series may have more.

**No events in range:**
"No events found between [start] and [end]."
Suggest: widen the window or verify the account has calendar events.

**Event detail fetch fails:**
Fall back to the summary data from `get-events` (subject, start, end, location). Note: "Full event description unavailable."

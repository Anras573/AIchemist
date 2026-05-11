#!/usr/bin/env bash
# Microsoft Graph calendar CLI via @pnp/cli-microsoft365 (m365).
# Requires MSGRAPH_APP_ID and MSGRAPH_TENANT_ID to be set in the environment.
#
# Usage:
#   msgraph.sh login                                        # authenticate via browser
#   msgraph.sh logout                                       # clear cached tokens
#   msgraph.sh list-calendars                               # list all calendars
#   msgraph.sh get-events [--start ISO8601] [--end ISO8601] [--calendar-id ID]
#   msgraph.sh get-event-detail EVENT_ID

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() { echo "Error: $*" >&2; exit 1; }

require_env() {
  [[ -n "${MSGRAPH_APP_ID:-}" ]]     || die "MSGRAPH_APP_ID is not set. Export it from your shell profile."
  [[ -n "${MSGRAPH_TENANT_ID:-}" ]]  || die "MSGRAPH_TENANT_ID is not set. Export it from your shell profile."
}

# Resolve m365 once: prefer global install, fall back to npx.
# npx requires --package to map the package name to the m365 binary.
if command -v m365 &>/dev/null; then
  m365_cmd() { m365 "$@"; }
elif command -v npx &>/dev/null; then
  m365_cmd() { npx --yes --package @pnp/cli-microsoft365 m365 "$@"; }
else
  die "Neither m365 nor npx is available. Install Node.js (https://nodejs.org) or run: npm install -g @pnp/cli-microsoft365"
fi

command -v python3 &>/dev/null || die "python3 is required but not found. Install Python 3 (https://python.org)."

# URL-encode a string for safe use in query parameters or path segments.
urlencode() {
  python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=''), end='')" "$1"
}

# Use UTC Z-suffix — accepted by Graph API on both macOS (BSD date) and Linux (GNU date).
# Avoids the +HHMM vs +HH:MM offset formatting difference between platforms.
iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

iso_days_from_now() {
  local days="$1"
  # GNU date uses -d; BSD date (macOS) uses -v
  date -u -v+"${days}d" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -d "+${days} days" +"%Y-%m-%dT%H:%M:%SZ"
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

cmd_login() {
  require_env
  m365_cmd login \
    --authType browser \
    --appId "$MSGRAPH_APP_ID" \
    --tenant "$MSGRAPH_TENANT_ID"
}

cmd_logout() {
  m365_cmd logout
}

cmd_list_calendars() {
  require_env
  m365_cmd request \
    --url "https://graph.microsoft.com/v1.0/me/calendars?\$select=id,name,isDefaultCalendar,canEdit,color" \
    --output json \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
if not isinstance(data, dict) or 'value' not in data:
    print('Error: unexpected response from Graph API:', json.dumps(data), file=sys.stderr)
    sys.exit(1)
items = data['value']
if not isinstance(items, list):
    print('Error: expected a list of calendars, got:', type(items).__name__, file=sys.stderr)
    sys.exit(1)
for c in items:
    default = ' (default)' if c.get('isDefaultCalendar') else ''
    editable = ' [read-only]' if not c.get('canEdit') else ''
    print(f\"{c['name']}{default}{editable}\")
    print(f\"  id: {c['id']}\")
"
}

cmd_get_events() {
  require_env
  local start end calendar_id=""
  start="$(iso_now)"
  end="$(iso_days_from_now 7)"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --start)       [[ $# -ge 2 ]] || die "--start requires a value";       start="$2";       shift 2 ;;
      --end)         [[ $# -ge 2 ]] || die "--end requires a value";         end="$2";         shift 2 ;;
      --calendar-id) [[ $# -ge 2 ]] || die "--calendar-id requires a value"; calendar_id="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  # Use calendarView (not /events) so recurring meetings are expanded into
  # individual occurrences within the window. /events filters by original
  # creation date, silently dropping recurring standups, 1:1s, etc.
  local base="https://graph.microsoft.com/v1.0/me"
  if [[ -n "$calendar_id" ]]; then
    base="https://graph.microsoft.com/v1.0/me/calendars/$(urlencode "$calendar_id")"
  fi
  local url="${base}/calendarView?startDateTime=$(urlencode "$start")&endDateTime=$(urlencode "$end")&\$select=id,subject,start,end,isOnlineMeeting,location,sensitivity,isCancelled,isAllDay&\$orderby=start/dateTime&\$top=50"

  # Follow @odata.nextLink until all pages are collected.
  # Graph caps each page at $top items, so a busy week may require multiple requests.
  local all_events="[]"
  local next_url="$url"
  while [[ -n "$next_url" ]]; do
    local page
    page="$(m365_cmd request --url "$next_url" --output json)"
    local result
    result="$(python3 -c "
import json, sys
page = json.loads(sys.argv[1])
if not isinstance(page, dict) or 'value' not in page:
    print('Error: unexpected response from Graph API:', json.dumps(page), file=sys.stderr)
    sys.exit(1)
acc = json.loads(sys.argv[2])
print(json.dumps({'events': acc + page['value'], 'next': page.get('@odata.nextLink', '')}))
" "$page" "$all_events")"
    all_events="$(python3 -c "import json,sys; print(json.dumps(json.loads(sys.argv[1])['events']))" "$result")"
    next_url="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['next'])" "$result")"
  done
  echo "$all_events"
}

cmd_get_event_detail() {
  require_env
  [[ $# -ge 1 ]] || die "Usage: $(basename "$0") get-event-detail EVENT_ID"
  local event_id="$1"

  m365_cmd outlook event get \
    --id "$event_id" \
    --userId "@meId" \
    --output json
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

[[ $# -ge 1 ]] || {
  echo "Usage: $(basename "$0") <command> [options]" >&2
  echo "" >&2
  echo "Commands:" >&2
  echo "  login                                        Authenticate via browser" >&2
  echo "  logout                                       Clear cached tokens" >&2
  echo "  list-calendars                               List all calendars" >&2
  echo "  get-events [--start ISO] [--end ISO]         List calendar events (default: next 7 days)" >&2
  echo "             [--calendar-id ID]                Scope to a specific calendar" >&2
  echo "  get-event-detail EVENT_ID                    Fetch full event including body/description" >&2
  exit 1
}

COMMAND="$1"; shift

case "$COMMAND" in
  login)            cmd_login ;;
  logout)           cmd_logout ;;
  list-calendars)   cmd_list_calendars ;;
  get-events)       cmd_get_events "$@" ;;
  get-event-detail) cmd_get_event_detail "$@" ;;
  *) die "Unknown command: $COMMAND. Run $(basename "$0") for usage." ;;
esac

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

require_python3() {
  command -v python3 &>/dev/null || die "python3 is required but not found. Install Python 3 (https://python.org)."
}

# Use Python for timestamp generation: produces local time with +HH:MM offset,
# which is DST-correct and accepted by the Graph API on all platforms.
iso_now() {
  python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).astimezone().isoformat(timespec='seconds'))"
}

iso_days_from_now() {
  python3 -c "from datetime import datetime, timezone, timedelta; print((datetime.now(timezone.utc).astimezone() + timedelta(days=$1)).isoformat(timespec='seconds'))"
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
  require_python3
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
  print(c['name'] + default + editable)
  print('  id: ' + c['id'])
"
}

cmd_get_events() {
  require_env
  require_python3
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
  local m365_prefix
  if command -v m365 &>/dev/null; then
    m365_prefix='["m365"]'
  else
    m365_prefix='["npx","--yes","--package","@pnp/cli-microsoft365","m365"]'
  fi

  M365_PREFIX="$m365_prefix" \
  GRAPH_START="$start" \
  GRAPH_END="$end" \
  GRAPH_CAL="$calendar_id" \
  python3 << 'PYEOF'
import json, os, subprocess, sys, urllib.parse

m365_cmd = json.loads(os.environ["M365_PREFIX"])
start    = os.environ["GRAPH_START"]
end      = os.environ["GRAPH_END"]
cal      = os.environ["GRAPH_CAL"]

base = "https://graph.microsoft.com/v1.0/me"
if cal:
    base += "/calendars/" + urllib.parse.quote(cal, safe="")

url = (base + "/calendarView"
    + "?startDateTime=" + urllib.parse.quote(start, safe="")
    + "&endDateTime="   + urllib.parse.quote(end, safe="")
    + "&$select=id,subject,start,end,isOnlineMeeting,location,sensitivity,isCancelled,isAllDay"
    + "&$orderby=start/dateTime"
    + "&$top=50")

events = []
while url:
    result = subprocess.run(
        m365_cmd + ["request", "--url", url, "--output", "json"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print("Error: m365 request failed:", result.stderr.strip(), file=sys.stderr)
        sys.exit(1)
    page = json.loads(result.stdout)
    if not isinstance(page, dict) or "value" not in page:
        print("Error: unexpected response from Graph API:", json.dumps(page), file=sys.stderr)
        sys.exit(1)
    events.extend(page["value"])
    url = page.get("@odata.nextLink", "")

print(json.dumps(events))
PYEOF
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

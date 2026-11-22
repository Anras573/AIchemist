#!/usr/bin/env bash
# Calendar entry point for the calendar skill and the calendar-status mod.
# Runs the configured backend with the same commands and the same output:
#   msgraph.sh  Microsoft 365 (MSGRAPH_APP_ID + MSGRAPH_TENANT_ID)
#   caldav.sh   CalDAV, iCloud by default (CALDAV_USERNAME + CALDAV_PASSWORD
#               or CALDAV_PASSWORD_CMD)
#
# CALENDAR_PROVIDER=msgraph|caldav picks one explicitly. Otherwise the first
# backend whose variables are set wins, Microsoft 365 first.
#
# Usage:
#   calendar.sh provider                          # print the backend in use
#   calendar.sh list-calendars
#   calendar.sh get-events [--start ISO] [--end ISO] [--calendar-id ID]
#   calendar.sh get-event-detail EVENT_ID
#   calendar.sh login | logout                    # Microsoft 365 only
#   calendar.sh check                             # CalDAV only: verify credentials

set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resolve_provider() {
  case "${CALENDAR_PROVIDER:-}" in
    msgraph|caldav) echo "$CALENDAR_PROVIDER"; return ;;
    "") ;;
    *) die "CALENDAR_PROVIDER must be msgraph or caldav (got: $CALENDAR_PROVIDER)" ;;
  esac
  if [[ -n "${MSGRAPH_APP_ID:-}" && -n "${MSGRAPH_TENANT_ID:-}" ]]; then
    echo msgraph
  elif [[ -n "${CALDAV_USERNAME:-}" ]]; then
    echo caldav
  else
    echo "Error: no calendar is configured. Export one of:" >&2
    echo "  Microsoft 365: MSGRAPH_APP_ID and MSGRAPH_TENANT_ID" >&2
    echo "  iCloud/CalDAV: CALDAV_USERNAME and CALDAV_PASSWORD (or CALDAV_PASSWORD_CMD)" >&2
    exit 2
  fi
}

[[ $# -ge 1 ]] || die "Usage: $(basename "$0") <provider|list-calendars|get-events|get-event-detail|login|logout|check> [options]"

provider=$(resolve_provider)

case "$1" in
  provider) echo "$provider"; exit 0 ;;
  login|logout) [[ "$provider" == msgraph ]] || die "$1 is only needed for Microsoft 365. CalDAV uses CALDAV_USERNAME and an app-specific password; run '$(basename "$0") check' to test them." ;;
  check) [[ "$provider" == caldav ]] || die "check is for CalDAV. For Microsoft 365, run '$(basename "$0") login' once." ;;
esac

exec bash "$SCRIPT_DIR/$provider.sh" "$@"

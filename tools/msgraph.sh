#!/usr/bin/env bash
# Microsoft Graph calendar CLI via @pnp/cli-microsoft365 (m365).
# Requires MSGRAPH_APP_ID and MSGRAPH_TENANT_ID to be set in the environment.
#
# Usage:
#   msgraph.sh login                              # authenticate via browser
#   msgraph.sh logout                             # clear cached tokens
#   msgraph.sh get-events [--start ISO8601] [--end ISO8601]
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
else
  m365_cmd() { npx --yes --package @pnp/cli-microsoft365 m365 "$@"; }
fi

# macOS-compatible ISO 8601 date arithmetic.
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

cmd_get_events() {
  require_env
  local start end
  start="$(iso_now)"
  end="$(iso_days_from_now 7)"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --start) start="$2"; shift 2 ;;
      --end)   end="$2";   shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  m365_cmd outlook event list \
    --userId "@meId" \
    --startDateTime "$start" \
    --endDateTime "$end" \
    --output json
}

cmd_get_event_detail() {
  require_env
  [[ $# -ge 1 ]] || die "Usage: msgraph.sh get-event-detail EVENT_ID"
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
  echo "Usage: $(basename "$0") <command> [options]"
  echo ""
  echo "Commands:"
  echo "  login                              Authenticate via browser"
  echo "  logout                             Clear cached tokens"
  echo "  get-events [--start ISO] [--end ISO]  List calendar events (default: next 7 days)"
  echo "  get-event-detail EVENT_ID          Fetch full event including body/description"
  exit 1
}

COMMAND="$1"; shift

case "$COMMAND" in
  login)            cmd_login ;;
  logout)           cmd_logout ;;
  get-events)       cmd_get_events "$@" ;;
  get-event-detail) cmd_get_event_detail "$@" ;;
  *) die "Unknown command: $COMMAND. Run $(basename "$0") for usage." ;;
esac

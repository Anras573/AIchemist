#!/usr/bin/env bash
# CalDAV calendar CLI (iCloud by default). Read-only. Prints the same output as
# msgraph.sh, so the calendar skill and the calendar-status mod can use either.
#
# Requires CALDAV_USERNAME and an app-specific password in CALDAV_PASSWORD, or
# a command that prints it in CALDAV_PASSWORD_CMD (e.g. a keychain lookup).
# CALDAV_URL defaults to iCloud (https://caldav.icloud.com/).
# Requires python3 (standard library only).
#
# Usage:
#   caldav.sh check                                        # verify credentials, list calendar count
#   caldav.sh list-calendars                               # list all event calendars
#   caldav.sh get-events [--start ISO8601] [--end ISO8601] [--calendar-id ID]
#   caldav.sh get-event-detail EVENT_ID
#
# Without --calendar-id, get-events reads every event calendar the account has.
# Recurring events are expanded by the server (CALDAV:expand). If a server
# returns them unexpanded, common rules are expanded here instead;
# CALDAV_EXPAND=client forces that.

set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }

require_python3() {
  command -v python3 &>/dev/null || die "python3 is required but not found. Install Python 3 (https://python.org)."
}

require_credentials() {
  [[ -n "${CALDAV_USERNAME:-}" ]] || die "CALDAV_USERNAME is not set. Export your Apple ID email (or CalDAV user name) from your shell profile."
  if [[ -z "${CALDAV_PASSWORD:-}" ]]; then
    [[ -n "${CALDAV_PASSWORD_CMD:-}" ]] || die "Set CALDAV_PASSWORD to an app-specific password, or CALDAV_PASSWORD_CMD to a command that prints it."
    CALDAV_PASSWORD=$(bash -c "$CALDAV_PASSWORD_CMD") || die "CALDAV_PASSWORD_CMD failed."
    [[ -n "$CALDAV_PASSWORD" ]] || die "CALDAV_PASSWORD_CMD printed nothing."
  fi
  export CALDAV_USERNAME CALDAV_PASSWORD
  export CALDAV_URL="${CALDAV_URL:-https://caldav.icloud.com/}"
  export CALDAV_EXPAND="${CALDAV_EXPAND:-server}"
}

usage() {
  echo "Usage: $(basename "$0") <command> [options]" >&2
  echo "" >&2
  echo "Commands:" >&2
  echo "  check                                        Verify credentials and calendar access" >&2
  echo "  list-calendars                               List all event calendars" >&2
  echo "  get-events [--start ISO] [--end ISO]         List calendar events (default: next 7 days)" >&2
  echo "             [--calendar-id ID]                Scope to one calendar (default: all)" >&2
  echo "  get-event-detail EVENT_ID                    Fetch full event including description" >&2
  exit 1
}

[[ $# -ge 1 ]] || usage
COMMAND="$1"; shift

case "$COMMAND" in
  check|list-calendars|get-events|get-event-detail) ;;
  -h|--help) usage ;;
  *) die "Unknown command: $COMMAND. Run $(basename "$0") for usage." ;;
esac

if [[ "$COMMAND" == "get-events" ]]; then
  args=("$@")
  i=0
  while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
      --start|--end|--calendar-id) [[ $((i + 1)) -lt ${#args[@]} ]] || die "${args[$i]} requires a value"; i=$((i + 2)) ;;
      *) die "Unknown option: ${args[$i]}" ;;
    esac
  done
elif [[ "$COMMAND" == "get-event-detail" ]]; then
  [[ $# -ge 1 ]] || die "Usage: $(basename "$0") get-event-detail EVENT_ID"
fi

require_python3
require_credentials

python3 - "$COMMAND" "$@" <<'PYEOF'
import base64, json, os, re, sys, urllib.error, urllib.parse, urllib.request
import xml.etree.ElementTree as ET
from datetime import date, datetime, time, timedelta, timezone

try:
    from zoneinfo import ZoneInfo  # Python 3.9+
except ImportError:  # older python3: TZID-local times are read as UTC
    ZoneInfo = None

NS = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav"}
BASE_URL = os.environ["CALDAV_URL"]
AUTH = "Basic " + base64.b64encode(
    (os.environ["CALDAV_USERNAME"] + ":" + os.environ["CALDAV_PASSWORD"]).encode()).decode()
CLIENT_EXPAND = os.environ.get("CALDAV_EXPAND") == "client"


def fail(message):
    print("Error: " + message, file=sys.stderr)
    sys.exit(1)


def warn(message):
    print("Warning: " + message, file=sys.stderr)


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

def request(method, url, body=None, depth=None):
    """Send a WebDAV request, following redirects for any method."""
    for _ in range(5):
        headers = {"Authorization": AUTH, "User-Agent": "aichemist-caldav/1"}
        if body is not None:
            headers["Content-Type"] = "application/xml; charset=utf-8"
        if depth is not None:
            headers["Depth"] = depth
        req = urllib.request.Request(url, data=body.encode() if body else None,
                                     headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return resp.status, resp.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as err:
            if err.code in (301, 302, 307, 308) and err.headers.get("Location"):
                url = urllib.parse.urljoin(url, err.headers["Location"])
                continue
            if err.code == 401:
                fail("CalDAV authentication failed (401). Check CALDAV_USERNAME and the app-specific password.")
            return err.code, err.read().decode("utf-8", "replace")
        except urllib.error.URLError as err:
            fail("could not reach " + url + ": " + str(err.reason))
    fail("too many redirects from " + url)


def multistatus(method, url, body, depth):
    status, text = request(method, url, body, depth)
    if status != 207:
        return None
    try:
        return ET.fromstring(text)
    except ET.ParseError as err:
        fail("unreadable response from " + url + ": " + str(err))


def first_href(root, path):
    node = root.find(".//" + path + "/d:href", NS) if root is not None else None
    return node.text.strip() if node is not None and node.text else None


# ---------------------------------------------------------------------------
# Discovery: principal -> calendar home -> calendars
# ---------------------------------------------------------------------------

def discover_calendars():
    principal_q = ('<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop>'
                   '<d:current-user-principal/></d:prop></d:propfind>')
    principal = None
    for candidate in (BASE_URL, urllib.parse.urljoin(BASE_URL, "/.well-known/caldav")):
        root = multistatus("PROPFIND", candidate, principal_q, "0")
        href = first_href(root, "d:current-user-principal")
        if href:
            principal = urllib.parse.urljoin(candidate, href)
            break
    if not principal:
        fail("no CalDAV principal found at " + BASE_URL + ". Check CALDAV_URL.")

    home_q = ('<?xml version="1.0"?><d:propfind xmlns:d="DAV:" '
              'xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><c:calendar-home-set/>'
              '</d:prop></d:propfind>')
    href = first_href(multistatus("PROPFIND", principal, home_q, "0"), "c:calendar-home-set")
    if not href:
        fail("the CalDAV server reported no calendar home for this account.")
    home = urllib.parse.urljoin(principal, href)

    list_q = ('<?xml version="1.0"?><d:propfind xmlns:d="DAV:" '
              'xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><d:resourcetype/>'
              '<d:displayname/><c:supported-calendar-component-set/>'
              '<d:current-user-privilege-set/></d:prop></d:propfind>')
    root = multistatus("PROPFIND", home, list_q, "1")
    if root is None:
        fail("could not list calendars at " + home + ".")

    calendars = []
    for response in root.findall("d:response", NS):
        href = response.findtext("d:href", default="", namespaces=NS).strip()
        prop = response.find(".//d:propstat/d:prop", NS)
        if not href or prop is None or prop.find("d:resourcetype/c:calendar", NS) is None:
            continue
        comps = [c.get("name") for c in prop.findall("c:supported-calendar-component-set/c:comp", NS)]
        if comps and "VEVENT" not in comps:
            continue  # reminders / task lists
        privileges = prop.find("d:current-user-privilege-set", NS)
        writable = privileges is None or any(
            privileges.find(".//d:" + p, NS) is not None for p in ("write", "write-content", "all"))
        name = prop.findtext("d:displayname", default="", namespaces=NS).strip()
        url = urllib.parse.urljoin(home, href)
        calendars.append({"id": url, "name": name or url.rstrip("/").rsplit("/", 1)[-1],
                          "canEdit": writable})
    return calendars


# ---------------------------------------------------------------------------
# iCalendar parsing
# ---------------------------------------------------------------------------

def split_outside_quotes(text, sep, maxsplit=-1):
    parts, buf, quoted = [], [], False
    for ch in text:
        if ch == '"':
            quoted = not quoted
        if ch == sep and not quoted and maxsplit != 0:
            parts.append("".join(buf)); buf = []; maxsplit -= 1
            continue
        buf.append(ch)
    parts.append("".join(buf))
    return parts


def parse_ics(text):
    """Return the VEVENT components as lists of (name, params, value)."""
    lines = []
    for raw in text.replace("\r\n", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        elif raw:
            lines.append(raw)
    events, current, depth = [], None, 0
    for line in lines:
        pieces = split_outside_quotes(line, ":", 1)
        head, value = pieces[0], pieces[1] if len(pieces) > 1 else ""
        name, *raw_params = split_outside_quotes(head, ";")
        name = name.upper()
        params = {}
        for p in raw_params:
            k, _, v = p.partition("=")
            params[k.upper()] = v.strip('"')
        if name == "BEGIN" and value.upper() == "VEVENT" and current is None:
            current, depth = [], 0
        elif current is not None and name == "BEGIN":
            depth += 1  # VALARM etc.
        elif current is not None and name == "END" and value.upper() == "VEVENT" and depth == 0:
            events.append(current); current = None
        elif current is not None and name == "END":
            depth -= 1
        elif current is not None and depth == 0:
            current.append((name, params, value))
    return events


def prop(event, name):
    for n, params, value in event:
        if n == name:
            return params, value
    return None, None


def props(event, name):
    return [(params, value) for n, params, value in event if n == name]


def unescape(text):
    return (text or "").replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",") \
        .replace("\\;", ";").replace("\\\\", "\\")


def parse_dt(params, value):
    """Return (aware UTC datetime, is_all_day)."""
    params = params or {}
    value = (value or "").strip()
    if params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", value):
        d = datetime.strptime(value[:8], "%Y%m%d")
        return d.replace(tzinfo=timezone.utc), True
    if value.endswith("Z"):
        return datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc), False
    local = datetime.strptime(value[:15], "%Y%m%dT%H%M%S")
    tzid = params.get("TZID")
    if tzid and ZoneInfo is not None:
        try:
            return local.replace(tzinfo=ZoneInfo(tzid)).astimezone(timezone.utc), False
        except Exception:
            warn("unknown time zone " + tzid + "; reading it as UTC")
    elif tzid:
        warn("python3 has no zoneinfo; reading " + tzid + " times as UTC")
        return local.replace(tzinfo=timezone.utc), False
    return local.astimezone().astimezone(timezone.utc), False  # floating: this machine's zone


def parse_duration(text):
    m = re.fullmatch(r"([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?", (text or "").strip())
    if not m:
        return None
    sign = -1 if m.group(1) == "-" else 1
    w, d, h, mi, s = (int(g or 0) for g in m.groups()[1:])
    return sign * timedelta(weeks=w, days=d, hours=h, minutes=mi, seconds=s)


def event_span(event):
    start, all_day = parse_dt(*prop(event, "DTSTART"))
    end_params, end_value = prop(event, "DTEND")
    if end_value:
        end, _ = parse_dt(end_params, end_value)
    else:
        duration = parse_duration(prop(event, "DURATION")[1])
        end = start + (duration if duration is not None else (timedelta(days=1) if all_day else timedelta()))
    return start, end, all_day


# ---------------------------------------------------------------------------
# Client-side recurrence expansion (fallback for servers without CALDAV:expand)
# ---------------------------------------------------------------------------

WEEKDAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]


def expand_rrule(event, range_start, range_end):
    """Yield occurrence start times (UTC) for FREQ=DAILY/WEEKLY/MONTHLY/YEARLY
    with INTERVAL, COUNT, UNTIL and weekly BYDAY. Other rule parts: None."""
    dt_params, dt_value = prop(event, "DTSTART")
    rule = dict(part.split("=", 1) for part in prop(event, "RRULE")[1].split(";") if "=" in part)
    unsupported = set(rule) - {"FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "WKST"}
    if unsupported or (rule.get("BYDAY") and rule.get("FREQ") != "WEEKLY"):
        return None
    tzid = (dt_params or {}).get("TZID")
    zone = ZoneInfo(tzid) if (tzid and ZoneInfo is not None) else timezone.utc
    first_utc, all_day = parse_dt(dt_params, dt_value)
    first = first_utc.astimezone(zone) if not all_day else first_utc
    interval = int(rule.get("INTERVAL", "1"))
    count = int(rule["COUNT"]) if "COUNT" in rule else None
    until = parse_dt({}, rule["UNTIL"])[0] if "UNTIL" in rule else None
    freq = rule["FREQ"]
    days = [WEEKDAYS.index(d[-2:]) for d in rule.get("BYDAY", "").split(",") if d[-2:] in WEEKDAYS]

    def candidates():
        n = 0
        while True:
            if freq == "DAILY":
                yield first + timedelta(days=n * interval)
            elif freq == "WEEKLY":
                week_start = first - timedelta(days=first.weekday()) + timedelta(weeks=n * interval)
                for wd in sorted(days or [first.weekday()]):
                    yield week_start + timedelta(days=wd)
            elif freq in ("MONTHLY", "YEARLY"):
                months = n * interval * (12 if freq == "YEARLY" else 1)
                y, m = divmod(first.month - 1 + months, 12)
                try:
                    yield first.replace(year=first.year + y, month=m + 1)
                except ValueError:
                    pass  # e.g. the 31st in a 30-day month: skipped, as RFC 5545 says
            else:
                return
            n += 1
            if n > 5000:
                return

    produced = 0
    for local in candidates():
        if local < first:
            continue
        occurrence = local.astimezone(timezone.utc) if not all_day else local
        if until is not None and occurrence > until:
            return
        produced += 1
        if count is not None and produced > count:
            return
        if occurrence >= range_end:
            return
        yield occurrence


def instances(events, range_start, range_end, expand_here):
    """(event, start, end, all_day, recurrence_id) per occurrence in range.
    With expand_here, RRULE masters are expanded on this side."""
    overrides = {}
    for ev in events:
        rid_params, rid = prop(ev, "RECURRENCE-ID")
        if rid:
            overrides[parse_dt(rid_params, rid)[0]] = ev
    out = []
    for ev in events:
        rid_params, rid = prop(ev, "RECURRENCE-ID")
        start, end, all_day = event_span(ev)
        if rid or not prop(ev, "RRULE")[1] or not expand_here:
            if end > range_start and start < range_end:
                out.append((ev, start, end, all_day, parse_dt(rid_params, rid)[0] if rid else None))
            continue
        excluded = set()
        for params, value in props(ev, "EXDATE"):
            for v in value.split(","):
                excluded.add(parse_dt(params, v)[0])
        occurrences = expand_rrule(ev, range_start, range_end)
        if occurrences is None:
            warn("recurrence rule not supported here (" + prop(ev, "RRULE")[1] + "); showing the first occurrence only")
            occurrences = [start]
        length = end - start
        for occ in occurrences:
            if occ in excluded or occ in overrides:
                continue
            if occ + length > range_start and occ < range_end:
                out.append((ev, occ, occ + length, all_day, occ if prop(ev, "RRULE")[1] else None))
    return out


# ---------------------------------------------------------------------------
# Output in msgraph.sh's shape
# ---------------------------------------------------------------------------

MEETING_URL = re.compile(
    r"https://[^\s<>\"']*(?:teams\.microsoft\.com/l/meetup-join|zoom\.us/j/|meet\.google\.com/|"
    r"webex\.com/|facetime\.apple\.com/join|whereby\.com/)[^\s<>\"']*", re.I)


def graph_time(moment):
    return {"dateTime": moment.strftime("%Y-%m-%dT%H:%M:%S") + ".0000000", "timeZone": "UTC"}


def encode_id(href, recurrence):
    raw = json.dumps({"h": href, "r": recurrence.strftime("%Y%m%dT%H%M%SZ") if recurrence else ""})
    return base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")


def decode_id(event_id):
    try:
        data = json.loads(base64.urlsafe_b64decode(event_id + "=" * (-len(event_id) % 4)))
        return data["h"], data.get("r") or ""
    except Exception:
        fail("not a CalDAV event id: " + event_id)


def summary(ev, href, start, end, all_day, recurrence):
    location = unescape(prop(ev, "LOCATION")[1])
    description = unescape(prop(ev, "DESCRIPTION")[1])
    url = (prop(ev, "URL")[1] or "").strip()
    match = MEETING_URL.search(" ".join([url, location, description]))
    klass = (prop(ev, "CLASS")[1] or "").upper()
    return {
        "id": encode_id(href, recurrence),
        "subject": unescape(prop(ev, "SUMMARY")[1]),
        "start": graph_time(start),
        "end": graph_time(end),
        "isOnlineMeeting": match is not None,
        "onlineMeetingUrl": match.group(0) if match else None,
        "location": {"displayName": location},
        "sensitivity": {"PRIVATE": "private", "CONFIDENTIAL": "confidential"}.get(klass, "normal"),
        "isCancelled": (prop(ev, "STATUS")[1] or "").upper() == "CANCELLED",
        "isAllDay": all_day,
    }


def person(params, value):
    address = re.sub(r"^mailto:", "", value or "", flags=re.I)
    return {"emailAddress": {"name": (params or {}).get("CN", address), "address": address}}


def to_utc_iso(text):
    return datetime.strptime(text, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc).isoformat()


def parse_range(text, default):
    if not text:
        return default
    try:
        moment = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        fail("not an ISO 8601 time: " + text)
    if moment.tzinfo is None:
        fail("time needs a UTC offset (e.g. +02:00): " + text)
    return moment.astimezone(timezone.utc)


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_check():
    calendars = discover_calendars()
    print("OK: signed in as " + os.environ["CALDAV_USERNAME"] + ", " + str(len(calendars)) + " event calendar(s)")


def cmd_list_calendars():
    for cal in discover_calendars():
        print(cal["name"] + ("" if cal["canEdit"] else " [read-only]"))
        print("  id: " + cal["id"])


def query_calendar(url, range_start, range_end, expand):
    fmt = "%Y%m%dT%H%M%SZ"
    span = 'start="' + range_start.strftime(fmt) + '" end="' + range_end.strftime(fmt) + '"'
    data = ("<c:calendar-data><c:expand " + span + "/></c:calendar-data>") if expand else "<c:calendar-data/>"
    body = ('<?xml version="1.0"?><c:calendar-query xmlns:d="DAV:" '
            'xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop>' + data + '</d:prop>'
            '<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">'
            '<c:time-range ' + span + '/></c:comp-filter></c:comp-filter></c:filter></c:calendar-query>')
    root = multistatus("REPORT", url, body, "1")
    if root is None:
        warn("could not read calendar " + url)
        return []
    out = []
    for response in root.findall("d:response", NS):
        href = urllib.parse.urljoin(url, response.findtext("d:href", default="", namespaces=NS).strip())
        ics = response.findtext(".//c:calendar-data", default="", namespaces=NS)
        if ics:
            out.append((href, ics))
    return out


def cmd_get_events(args):
    opts = dict(zip(args[::2], args[1::2]))
    now = datetime.now(timezone.utc).replace(microsecond=0)
    range_start = parse_range(opts.get("--start"), now)
    range_end = parse_range(opts.get("--end"), now + timedelta(days=7))
    if opts.get("--calendar-id"):
        urls = [opts["--calendar-id"]]
    else:
        urls = [cal["id"] for cal in discover_calendars()]

    results = []
    for url in urls:
        for href, ics in query_calendar(url, range_start, range_end, expand=not CLIENT_EXPAND):
            events = parse_ics(ics)
            # A master with an RRULE means the server did not expand: do it here.
            expand_here = CLIENT_EXPAND or any(
                prop(ev, "RRULE")[1] and not prop(ev, "RECURRENCE-ID")[1] for ev in events)
            for ev, start, end, all_day, rid in instances(events, range_start, range_end, expand_here):
                if rid is None and prop(ev, "RECURRENCE-ID")[1]:
                    rid = parse_dt(*prop(ev, "RECURRENCE-ID"))[0]
                results.append(summary(ev, href, start, end, all_day, rid))
    results.sort(key=lambda e: e["start"]["dateTime"])
    print(json.dumps(results))


def cmd_get_event_detail(args):
    href, recurrence = decode_id(args[0])
    status, ics = request("GET", href)
    if status != 200:
        fail("could not fetch the event (HTTP " + str(status) + ").")
    events = parse_ics(ics)
    if not events:
        fail("the event has no VEVENT.")
    chosen, start = None, None
    if recurrence:
        wanted = datetime.strptime(recurrence, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
        for ev in events:
            rid = prop(ev, "RECURRENCE-ID")
            if rid[1] and parse_dt(*rid)[0] == wanted:
                chosen = ev
        if chosen is None:  # an occurrence of the master
            chosen = next((ev for ev in events if prop(ev, "RRULE")[1]), events[0])
            start = wanted
    if chosen is None:
        chosen = next((ev for ev in events if not prop(ev, "RECURRENCE-ID")[1]), events[0])
    ev_start, ev_end, all_day = event_span(chosen)
    if start is not None:
        ev_start, ev_end = start, start + (ev_end - ev_start)
    detail = summary(chosen, href, ev_start, ev_end, all_day,
                     datetime.strptime(recurrence, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc) if recurrence else None)
    detail["body"] = {"contentType": "text", "content": unescape(prop(chosen, "DESCRIPTION")[1])}
    organizer = prop(chosen, "ORGANIZER")
    detail["organizer"] = person(*organizer) if organizer[1] else None
    detail["attendees"] = [
        dict(person(params, value),
             status={"response": (params.get("PARTSTAT") or "NEEDS-ACTION").lower()},
             type=(params.get("ROLE") or "REQ-PARTICIPANT").lower())
        for params, value in props(chosen, "ATTENDEE")]
    detail["webLink"] = (prop(chosen, "URL")[1] or "").strip() or None
    print(json.dumps(detail))


command, args = sys.argv[1], sys.argv[2:]
if command == "check":
    cmd_check()
elif command == "list-calendars":
    cmd_list_calendars()
elif command == "get-events":
    cmd_get_events(args)
elif command == "get-event-detail":
    cmd_get_event_detail(args)
PYEOF

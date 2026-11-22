#!/usr/bin/env python3
"""scratchpad - a local HTML scratchpad for agent/human collaboration.

The agent writes markdown pages into a pad folder and calls this CLI. A small
local server renders the pages as HTML, where the human leaves section
comments and answers decision blocks. Feedback is an append-only JSONL log
that the agent reads with `inbox` / `wait`.

Standard library only; keep the code Python 3.7 compatible.
"""

import argparse
import contextlib
import datetime
import html
import json
import os
import re
import signal
import subprocess
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULT_PORT = 4747
PORT_ATTEMPTS = 20
LOG_NAME = "comments.jsonl"
LOCK_NAME = ".lock"
SERVER_FILE = ".server.json"
SERVER_LOG = ".server.log"
START_LOCK = ".start.lock"
HEALTH_PREFIX = b"scratchpad-ok pid="
MAX_BODY = 64 * 1024
MAX_TEXT = 5000
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
DECISION_ID_RE = re.compile(r"^[A-Za-z0-9_-]+$")
ANCHOR_RE = re.compile(r"^[\w-]{0,120}$")
ANSWERS = ("proposal", "alternative")


class ScratchpadError(Exception):
    """A user-facing error; the CLI prints the message and exits non-zero."""


# --------------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------------

def pad_home():
    configured = os.environ.get("SCRATCHPAD_HOME")
    if configured:
        return os.path.abspath(os.path.expanduser(configured))
    return os.path.join(os.path.expanduser("~"), "scratchpads")


def natural_key(name):
    return [int(p) if p.isdigit() else p.lower() for p in re.split(r"(\d+)", name)]


def list_pads(home):
    if not os.path.isdir(home):
        return []
    pads = []
    for entry in os.listdir(home):
        if entry.startswith(".") or not NAME_RE.match(entry):
            continue
        pad_dir = os.path.join(home, entry)
        # A symlink that resolves outside SCRATCHPAD_HOME is not a pad.
        if os.path.isdir(pad_dir) and inside(home, pad_dir):
            pads.append(entry)
    return sorted(pads)


def list_pages(pad_dir):
    pages = []
    for entry in os.listdir(pad_dir):
        if entry.endswith(".md") and NAME_RE.match(entry) and inside(pad_dir, os.path.join(pad_dir, entry)):
            pages.append(entry[:-3])
    return sorted(pages, key=natural_key)


def pad_activity(pad_dir):
    """Newest mtime among the pad folder, its comment log and its pages.

    Appending a comment or editing a page changes that file's mtime but not the folder's.
    """
    newest = os.path.getmtime(pad_dir)
    for entry in os.listdir(pad_dir):
        if entry == LOG_NAME or entry.endswith(".md"):
            try:
                newest = max(newest, os.path.getmtime(os.path.join(pad_dir, entry)))
            except OSError:
                pass
    return newest


def resolve_pad(home, name=None):
    """Return the pad name. Existence is checked before any path resolution."""
    if name:
        if not NAME_RE.match(name):
            raise ScratchpadError("Invalid pad name: %s" % name)
        pad_dir = os.path.join(home, name)
        if not os.path.isdir(pad_dir):
            raise ScratchpadError("Pad not found: %s" % name)
        if not inside(home, pad_dir):
            raise ScratchpadError("Pad is outside SCRATCHPAD_HOME: %s" % name)
        return name
    pads = list_pads(home)
    if not pads:
        raise ScratchpadError("No pads found in %s (run `scratchpad new <topic>`)" % home)
    return max(pads, key=lambda p: (pad_activity(os.path.join(home, p)), p))


def inside(root, target):
    """True if target is inside root once symlinks are resolved."""
    root_real = os.path.realpath(root)
    target_real = os.path.realpath(target)
    try:
        return os.path.commonpath([root_real, target_real]) == root_real
    except ValueError:
        return False


# --------------------------------------------------------------------------
# Store: append-only JSONL event log
# --------------------------------------------------------------------------

@contextlib.contextmanager
def file_lock(path, timeout=10):
    handle = open(path, "a+b")
    try:
        if os.name == "nt":
            import msvcrt
            handle.seek(0)
            deadline = time.time() + timeout
            while True:
                try:
                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                    break
                except OSError:
                    if time.time() > deadline:
                        raise
                    time.sleep(0.05)
            try:
                yield
            finally:
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            fcntl.flock(handle, fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(handle, fcntl.LOCK_UN)
    finally:
        handle.close()


class Store(object):
    def __init__(self, pad_dir, clock=time.time):
        self.pad_dir = pad_dir
        self.log_path = os.path.join(pad_dir, LOG_NAME)
        self.lock_path = os.path.join(pad_dir, LOCK_NAME)
        self.clock = clock

    def read_events(self):
        """Return (events, bad_line_count). Bad and partial lines are skipped."""
        events = []
        bad = 0
        if not os.path.isfile(self.log_path):
            return events, bad
        with open(self.log_path, "rb") as handle:
            raw = handle.read()
        lines = raw.split(b"\n")
        unterminated = lines.pop()  # text after the last newline (b"" when clean)
        del unterminated  # a partial trailing line is ignored, not counted
        for line in lines:
            if not line.strip():
                continue
            try:
                event = json.loads(line.decode("utf-8"))
            except ValueError:
                bad += 1
                continue
            if isinstance(event, dict) and "type" in event:
                events.append(event)
            else:
                bad += 1
        return events, bad

    def append(self, event, id_prefix=None):
        """Append one event under the lock; assign an id when id_prefix is given."""
        with file_lock(self.lock_path):
            if id_prefix:
                events, _ = self.read_events()
                highest = 0
                for existing in events:
                    ident = str(existing.get("id", ""))
                    if ident.startswith(id_prefix + "-") and ident[len(id_prefix) + 1:].isdigit():
                        highest = max(highest, int(ident[len(id_prefix) + 1:]))
                event["id"] = "%s-%d" % (id_prefix, highest + 1)
            event["ts"] = self.clock()
            line = json.dumps(event, sort_keys=True).encode("utf-8") + b"\n"
            with open(self.log_path, "ab") as handle:
                handle.write(line)
                handle.flush()
                os.fsync(handle.fileno())
        return event

    def state(self):
        events, bad = self.read_events()
        return PadState(events, bad)

    # --- typed appends -----------------------------------------------------

    def add_comment(self, page, anchor, heading, text, author="human"):
        return self.append({"type": "comment", "page": page, "anchor": anchor,
                            "heading": heading, "text": text, "author": author}, "c")

    def add_decision_answer(self, page, decision, answer, author="human"):
        return self.append({"type": "decision_answer", "page": page, "decision": decision,
                            "answer": answer, "author": author}, "d")

    def add_reply(self, to, text, author="agent"):
        return self.append({"type": "reply", "to": to, "text": text, "author": author})

    def mark_handled(self, to, author="agent"):
        return self.append({"type": "handled", "to": to, "author": author})


class PadState(object):
    """State derived by replaying the event log."""

    def __init__(self, events, bad_lines=0):
        self.bad_lines = bad_lines
        self.items = {}
        self.order = []
        for event in events:
            kind = event.get("type")
            ident = event.get("id")
            if kind == "comment" and ident:
                self.items[ident] = {
                    "id": ident, "kind": "comment", "page": event.get("page", ""),
                    "anchor": event.get("anchor", ""), "heading": event.get("heading", ""),
                    "text": event.get("text", ""), "author": event.get("author", "human"),
                    "ts": event.get("ts", 0), "replies": [], "handled": False,
                }
                self.order.append(ident)
            elif kind == "decision_answer" and ident:
                self.items[ident] = {
                    "id": ident, "kind": "decision", "page": event.get("page", ""),
                    "decision": event.get("decision", ""), "answer": event.get("answer", ""),
                    "author": event.get("author", "human"), "ts": event.get("ts", 0),
                    "replies": [], "handled": False,
                }
                self.order.append(ident)
            elif kind == "reply":
                target = self.items.get(event.get("to"))
                if target is not None:
                    target["replies"].append({"author": event.get("author", "agent"),
                                              "text": event.get("text", ""),
                                              "ts": event.get("ts", 0)})
            elif kind == "handled":
                target = self.items.get(event.get("to"))
                if target is not None:
                    target["handled"] = True

    def get(self, ident):
        return self.items.get(ident)

    def all_items(self):
        return [self.items[i] for i in self.order]

    def unhandled(self):
        return [item for item in self.all_items() if not item["handled"]]

    def comments_for(self, page):
        return [i for i in self.all_items() if i["kind"] == "comment" and i["page"] == page]

    def decision_answer(self, page, decision):
        """The latest answer to a decision wins."""
        latest = None
        for item in self.all_items():
            if item["kind"] == "decision" and item["page"] == page and item["decision"] == decision:
                latest = item
        return latest


def wait_for_batch(store, quiet, timeout, clock=time.time, sleep=time.sleep, poll=0.5):
    """Block until unhandled items exist and the human has been quiet for `quiet` seconds.

    Returns the list of unhandled items, or [] on timeout.
    """
    deadline = clock() + timeout
    while True:
        pending = store.state().unhandled()
        if pending:
            newest = max(item["ts"] for item in pending)
            if clock() - newest >= quiet:
                return pending
        if clock() >= deadline:
            return []
        sleep(poll)


# --------------------------------------------------------------------------
# Renderer: a small markdown subset -> HTML
# --------------------------------------------------------------------------

def slugify(text):
    slug = re.sub(r"[^\w\s-]", "", text.strip().lower())
    slug = re.sub(r"[\s_]+", "-", slug).strip("-")
    return slug or "section"


def _safe_url(url):
    lowered = url.lower()
    if lowered.startswith(("http://", "https://", "mailto:", "#", "/")):
        return True
    return ":" not in url.split("/", 1)[0]


def render_inline(text):
    text = text.replace("\x00", "")
    codes = []

    def stash(match):
        codes.append(match.group(1))
        return "\x00%d\x00" % (len(codes) - 1)

    text = re.sub(r"`([^`]+)`", stash, text)
    text = html.escape(text, quote=True)

    def link(match):
        label, url = match.group(1), match.group(2)
        if not _safe_url(html.unescape(url)):
            return label
        return '<a href="%s">%s</a>' % (url, label)

    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", link, text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![*\w])\*([^*\n]+)\*(?![*\w])", r"<em>\1</em>", text)
    return re.sub(r"\x00(\d+)\x00",
                  lambda m: "<code>%s</code>" % html.escape(codes[int(m.group(1))]), text)


_HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
_LIST_RE = re.compile(r"^(\s*)([-*+]|\d+[.)])\s+(.*)$")
_TABLE_SEP_RE = re.compile(r"^\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$")
_HR_RE = re.compile(r"^\s*(-{3,}|\*{3,}|_{3,})\s*$")


def _split_row(line):
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [cell.strip() for cell in line.split("|")]


def _starts_block(line, next_line):
    if not line.strip():
        return True
    if (line.startswith("```") or line.startswith(":::") or line.startswith(">")
            or _HEADING_RE.match(line) or _LIST_RE.match(line) or _HR_RE.match(line)):
        return True
    return bool(line.lstrip().startswith("|") and next_line is not None
                and _TABLE_SEP_RE.match(next_line.strip()))


def _render_list(items):
    out = []
    stack = []
    for indent, ordered, text in items:
        tag = "ol" if ordered else "ul"
        while stack and indent < stack[-1][0]:
            out.append("</li></%s>" % stack.pop()[1])
        if stack and indent == stack[-1][0]:
            if stack[-1][1] != tag:
                # Same indent but the list type changed (- then 1.): close and reopen as the new type.
                out.append("</li></%s><%s>" % (stack[-1][1], tag))
                stack[-1] = (indent, tag)
            else:
                out.append("</li>")
        else:
            out.append("<%s>" % tag)
            stack.append((indent, tag))
        out.append("<li>" + render_inline(text))
    while stack:
        out.append("</li></%s>" % stack.pop()[1])
    return "".join(out)


def parse_decision(header, body_lines, terminated):
    """Parse a `:::decision <id>` block into a dict; `error` is set when malformed."""
    decision = {"id": "", "proposal": "", "alternative": "", "pick": "", "error": None}
    parts = header.split(None, 1)
    decision["id"] = parts[1].strip() if len(parts) > 1 else ""
    problems = []
    if not decision["id"] or not DECISION_ID_RE.match(decision["id"]):
        problems.append("decision needs an id of letters, digits, - or _")
    if not terminated:
        problems.append("missing closing :::")
    for line in body_lines:
        if not line.strip():
            continue
        key, sep, value = line.partition(":")
        key = key.strip().lower()
        if not sep or key not in ("proposal", "alternative", "pick"):
            problems.append("unknown line: %s" % line.strip())
            continue
        decision[key] = value.strip()
    if not decision["proposal"]:
        problems.append("missing proposal:")
    if not decision["alternative"]:
        problems.append("missing alternative:")
    if decision["pick"] and decision["pick"] not in ANSWERS:
        problems.append("pick must be 'proposal' or 'alternative'")
    if problems:
        decision["error"] = "; ".join(problems)
    return decision


def decision_card(decision, answer=None, resolved=False, pad=None, page=None):
    """HTML for one decision card. Buttons only appear when pad/page are given."""
    if decision["error"]:
        return ('<div class="sp-decision sp-error"><strong>Malformed decision</strong> '
                '(%s): %s</div>' % (html.escape(decision["id"] or "?"),
                                    html.escape(decision["error"])))
    chosen = answer["answer"] if answer else None
    rows = []
    for key, label in (("proposal", "Proposal"), ("alternative", "Alternative")):
        classes = ["sp-option"]
        badges = []
        if decision["pick"] == key:
            classes.append("sp-pick")
            badges.append("agent's pick")
        if chosen == key:
            classes.append("sp-chosen")
            badges.append("your answer")
        button = ""
        if pad and page and not resolved:
            button = ('<button class="sp-answer" data-decision="%s" data-answer="%s">'
                      'Choose %s</button>' % (html.escape(decision["id"]), key, label.lower()))
        rows.append('<div class="%s"><div class="sp-label">%s %s</div><div>%s</div>%s</div>' % (
            " ".join(classes), label,
            "".join('<span class="sp-badge">%s</span>' % b for b in badges),
            render_inline(decision[key]), button))
    status = ""
    if resolved and chosen:
        status = '<div class="sp-status">Resolved: %s</div>' % html.escape(chosen)
    elif chosen:
        status = '<div class="sp-status">Answered: %s (waiting for the agent)</div>' % html.escape(chosen)
    return ('<div class="sp-decision" data-page="%s"><div class="sp-dtitle">Decision: %s</div>%s%s</div>'
            % (html.escape(page or ""), html.escape(decision["id"]), "".join(rows), status))


class RenderResult(object):
    def __init__(self, body, headings, decisions):
        self.body = body
        self.headings = headings      # list of (level, text, slug)
        self.decisions = decisions    # list of decision dicts


def _is_table_start(line, next_line):
    return bool(line.lstrip().startswith("|") and next_line is not None
                and _TABLE_SEP_RE.match(next_line.strip()))


def _parse_fence(lines, i):
    code = []
    i += 1
    while i < len(lines) and not lines[i].startswith("```"):
        code.append(lines[i])
        i += 1
    return "<pre><code>%s</code></pre>" % html.escape("\n".join(code)), i + 1


def _parse_decision_block(lines, i):
    """Parse a `:::decision` block starting at lines[i]; returns (decision, next_index)."""
    header = lines[i][3:].strip()
    i += 1
    close = next((j for j in range(i, len(lines)) if lines[j].strip() == ":::"), None)
    if close is not None:
        return parse_decision(header, lines[i:close], True), close + 1
    # Unterminated: stop at the first blank line or heading so the rest of the page survives.
    body = []
    while i < len(lines) and lines[i].strip() and not _HEADING_RE.match(lines[i]):
        body.append(lines[i])
        i += 1
    return parse_decision(header, body, False), i


def _parse_quote(lines, i):
    quote = []
    while i < len(lines) and lines[i].startswith(">"):
        quote.append(lines[i].lstrip(">").strip())
        i += 1
    return "<blockquote>%s</blockquote>" % render_inline(" ".join(quote)), i


def _parse_table(lines, i):
    header_cells = _split_row(lines[i])
    i += 2  # skip the header and the separator row
    rows = []
    while i < len(lines) and lines[i].lstrip().startswith("|"):
        rows.append(_split_row(lines[i]))
        i += 1
    table = ["<table><thead><tr>"]
    table.extend("<th>%s</th>" % render_inline(c) for c in header_cells)
    table.append("</tr></thead><tbody>")
    for row in rows:
        table.append("<tr>" + "".join("<td>%s</td>" % render_inline(c) for c in row) + "</tr>")
    table.append("</tbody></table>")
    return "".join(table), i


def _parse_list(lines, i):
    items = []
    while i < len(lines):
        match = _LIST_RE.match(lines[i])
        if not match:
            break
        items.append((len(match.group(1).expandtabs(4)), match.group(2)[0].isdigit(), match.group(3)))
        i += 1
    return _render_list(items), i


def _parse_paragraph(lines, i):
    paragraph = [lines[i].strip()]
    i += 1
    while i < len(lines) and not _starts_block(lines[i], lines[i + 1] if i + 1 < len(lines) else None):
        paragraph.append(lines[i].strip())
        i += 1
    return "<p>%s</p>" % render_inline(" ".join(paragraph)), i


def _unique_slug(slugs, text):
    base = slugify(text)
    slugs[base] = slugs.get(base, 0) + 1
    return base if slugs[base] == 1 else "%s-%d" % (base, slugs[base])


def render_markdown(source, on_heading=None, on_decision=None):
    lines = source.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    out = []
    headings = []
    decisions = []
    slugs = {}
    seen_decisions = set()
    i = 0
    while i < len(lines):
        line = lines[i]
        nxt = lines[i + 1] if i + 1 < len(lines) else None
        heading = _HEADING_RE.match(line)
        if not line.strip():
            i += 1
        elif line.startswith("```"):
            block, i = _parse_fence(lines, i)
            out.append(block)
        elif line.startswith(":::decision"):
            decision, i = _parse_decision_block(lines, i)
            if not decision["error"] and decision["id"] in seen_decisions:
                decision["error"] = "duplicate decision id on this page"
            seen_decisions.add(decision["id"])
            decisions.append(decision)
            out.append(on_decision(decision) if on_decision else decision_card(decision))
        elif heading:
            level, text = len(heading.group(1)), heading.group(2)
            slug = _unique_slug(slugs, text)
            headings.append((level, text, slug))
            extra = on_heading(level, text, slug) if on_heading else ""
            out.append('<h%d id="%s">%s</h%d>%s' % (level, html.escape(slug),
                                                    render_inline(text), level, extra))
            i += 1
        elif _HR_RE.match(line):
            out.append("<hr>")
            i += 1
        elif line.startswith(">"):
            block, i = _parse_quote(lines, i)
            out.append(block)
        elif _is_table_start(line, nxt):
            block, i = _parse_table(lines, i)
            out.append(block)
        elif _LIST_RE.match(line):
            block, i = _parse_list(lines, i)
            out.append(block)
        else:
            block, i = _parse_paragraph(lines, i)
            out.append(block)
    return RenderResult("\n".join(out), headings, decisions)


# --------------------------------------------------------------------------
# Page layer: comments, decisions and the HTML shell
# --------------------------------------------------------------------------

CSS = """
:root { --bg:#fff; --fg:#1a1a1a; --muted:#666; --line:#ddd; --accent:#0b57d0; --soft:#f5f5f5; --warn:#b3261e; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#161616; --fg:#e6e6e6; --muted:#9a9a9a; --line:#333; --accent:#8ab4f8; --soft:#222; --warn:#f2b8b5; }
}
body { background:var(--bg); color:var(--fg); font:16px/1.6 system-ui,sans-serif; margin:0; }
main { max-width:50rem; margin:0 auto; padding:1rem 16px 4rem; }
nav { border-bottom:1px solid var(--line); padding:.6rem 16px; display:flex; flex-wrap:wrap; gap:.4rem 1rem; font-size:.9rem; }
nav a { color:var(--accent); text-decoration:none; } nav a.current { font-weight:700; color:var(--fg); }
a { color:var(--accent); }
code, pre { background:var(--soft); border-radius:4px; font-size:.9em; } code { padding:.1em .3em; }
pre { padding:.8rem; overflow-x:auto; } pre code { padding:0; }
table { border-collapse:collapse; display:block; overflow-x:auto; } td, th { border:1px solid var(--line); padding:.3rem .6rem; }
blockquote { border-left:3px solid var(--line); margin:1rem 0; padding:0 1rem; color:var(--muted); }
.sp-toggle, .sp-answer, .sp-send { font:inherit; font-size:.8rem; cursor:pointer; border:1px solid var(--line);
  background:var(--soft); color:var(--fg); border-radius:4px; padding:.15rem .6rem; }
.sp-toggle { margin-left:.6rem; vertical-align:middle; opacity:.7; }
.sp-form { display:none; margin:.4rem 0 1rem; } .sp-form.open { display:block; }
.sp-form textarea { width:100%; box-sizing:border-box; min-height:5rem; font:inherit; background:var(--bg); color:var(--fg);
  border:1px solid var(--line); border-radius:4px; padding:.5rem; }
.sp-msg { color:var(--warn); font-size:.85rem; margin-left:.5rem; }
.sp-thread { border-left:3px solid var(--accent); margin:.4rem 0 1rem; padding:.1rem .8rem; font-size:.92rem; }
.sp-thread.sp-done { opacity:.55; border-left-color:var(--line); }
.sp-meta { color:var(--muted); font-size:.78rem; } .sp-agent { color:var(--accent); }
.sp-decision { border:1px solid var(--line); border-radius:8px; padding:.8rem 1rem; margin:1rem 0; }
.sp-dtitle { font-weight:700; margin-bottom:.5rem; }
.sp-option { border:1px solid var(--line); border-radius:6px; padding:.5rem .8rem; margin:.4rem 0; }
.sp-option.sp-pick { border-color:var(--accent); } .sp-option.sp-chosen { background:var(--soft); }
.sp-label { font-size:.8rem; color:var(--muted); } .sp-badge { margin-left:.5rem; color:var(--accent); font-size:.75rem; }
.sp-status { color:var(--muted); font-size:.85rem; margin-top:.4rem; }
.sp-error { border-color:var(--warn); color:var(--warn); }
.sp-detached { margin-top:3rem; border-top:1px solid var(--line); }
"""

JS = """
(function () {
  var pad = document.body.dataset.pad, page = document.body.dataset.page;
  function post(path, payload, msgEl) {
    return fetch('/api/' + pad + '/' + path, {
      method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(payload)
    }).then(function (r) {
      if (!r.ok) { return r.text().then(function (t) { throw new Error(t || r.status); }); }
      location.reload();
    }).catch(function (e) {
      msgEl.textContent = 'Not saved (' + e.message + '). Is the scratchpad server still running? Your text is kept.';
    });
  }
  document.querySelectorAll('.sp-toggle').forEach(function (btn) {
    btn.addEventListener('click', function () {
      document.getElementById(btn.dataset.form).classList.toggle('open');
    });
  });
  document.querySelectorAll('.sp-send').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var form = btn.closest('.sp-form'), box = form.querySelector('textarea'), msg = form.querySelector('.sp-msg');
      if (!box.value.trim()) { msg.textContent = 'Write something first.'; return; }
      post('comments', {page: page, anchor: form.dataset.anchor, heading: form.dataset.heading, text: box.value}, msg);
    });
  });
  document.querySelectorAll('.sp-answer').forEach(function (btn) {
    btn.addEventListener('click', function () {
      post('decisions', {page: page, decision: btn.dataset.decision, answer: btn.dataset.answer}, btn);
    });
  });
})();
"""


def _format_time(ts):
    try:
        return datetime.datetime.fromtimestamp(float(ts)).strftime("%Y-%m-%d %H:%M")
    except (ValueError, OverflowError, OSError, TypeError):
        return ""


def _text_html(text):
    return html.escape(text).replace("\n", "<br>")


def thread_html(item):
    classes = "sp-thread sp-done" if item["handled"] else "sp-thread"
    parts = ['<div class="%s"><div class="sp-meta">%s &middot; %s &middot; %s%s</div><div>%s</div>' % (
        classes, html.escape(item["id"]), html.escape(item["author"]), _format_time(item["ts"]),
        " &middot; handled" if item["handled"] else "", _text_html(item["text"]))]
    for reply in item["replies"]:
        parts.append('<div class="sp-meta sp-agent">%s &middot; %s</div><div>%s</div>' % (
            html.escape(reply["author"]), _format_time(reply["ts"]), _text_html(reply["text"])))
    parts.append("</div>")
    return "".join(parts)


def _comment_form(form_id, anchor, heading):
    return ('<div class="sp-form" id="%s" data-anchor="%s" data-heading="%s">'
            '<textarea placeholder="Comment on this section"></textarea>'
            '<button class="sp-send">Send</button><span class="sp-msg"></span></div>' % (
                html.escape(form_id), html.escape(anchor), html.escape(heading)))


def page_shell(title, pad, page, nav, body):
    return ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            "<title>%s</title><style>%s</style></head>"
            "<body data-pad=\"%s\" data-page=\"%s\"><nav>%s</nav><main>%s</main>"
            "<script>%s</script></body></html>" % (
                html.escape(title), CSS, html.escape(pad or ""), html.escape(page or ""),
                nav, body, JS))


def render_page(pad, page, source, state, pages):
    comments = state.comments_for(page)
    by_anchor = {}
    for comment in comments:
        by_anchor.setdefault(comment["anchor"], []).append(comment)
    counter = {"n": 0}

    def on_heading(level, text, slug):
        counter["n"] += 1
        form_id = "form-%d" % counter["n"]
        threads = "".join(thread_html(c) for c in by_anchor.get(slug, []))
        return ('<button class="sp-toggle" data-form="%s" type="button">Comment</button>%s%s' % (
            form_id, threads, _comment_form(form_id, slug, text)))

    def on_decision(decision):
        answer = state.decision_answer(page, decision["id"])
        resolved = bool(answer and answer["handled"])
        return decision_card(decision, answer, resolved, pad, page)

    result = render_markdown(source, on_heading, on_decision)
    known = set(slug for _, _, slug in result.headings)
    detached = [c for c in comments if c["anchor"] not in known]
    body = result.body
    if detached:
        body += ('<section class="sp-detached"><h2>Detached comments</h2>'
                 '<p class="sp-meta">Their heading was renamed or removed.</p>%s</section>' % (
                     "".join(thread_html(c) for c in detached)))
    nav = nav_html(pad, pages, page)
    return page_shell("%s - %s" % (page, pad), pad, page, nav, body)


def nav_html(pad, pages, current=None):
    links = ['<a href="/">All pads</a>']
    for name in pages:
        css = ' class="current"' if name == current else ""
        links.append('<a%s href="/%s/%s">%s</a>' % (css, html.escape(pad), html.escape(name), html.escape(name)))
    return "".join(links)


# --------------------------------------------------------------------------
# Server
# --------------------------------------------------------------------------

class ScratchpadServer(ThreadingHTTPServer):
    allow_reuse_address = False  # on Windows SO_REUSEADDR would allow a second bind on the same port
    daemon_threads = True

    def __init__(self, address, home):
        ThreadingHTTPServer.__init__(self, address, Handler)
        self.home = home


class Handler(BaseHTTPRequestHandler):
    server_version = "scratchpad"

    def log_message(self, fmt, *args):
        pass

    # --- helpers -------------------------------------------------------------

    def _send(self, code, body, ctype="text/html; charset=utf-8", headers=None):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _error(self, code, message):
        self._send(code, message, "text/plain; charset=utf-8")

    def _host_ok(self):
        host = self.headers.get("Host", "")
        name = host.rsplit(":", 1)[0] if ":" in host else host
        return name in ("127.0.0.1", "localhost")

    def _origin_ok(self):
        origin = self.headers.get("Origin")
        if not origin:
            return True
        try:
            parsed = urllib.parse.urlparse(origin)
            return parsed.hostname in ("127.0.0.1", "localhost") and parsed.port == self.server.server_address[1]
        except ValueError:  # malformed Origin, e.g. a non-numeric port
            return False

    def _locate(self, pad, page=None):
        """Return (pad_dir, page_file) after name, existence and containment checks."""
        home = self.server.home
        if not NAME_RE.match(pad):
            return None, None
        pad_dir = os.path.join(home, pad)
        if not os.path.isdir(pad_dir) or not inside(home, pad_dir):
            return None, None
        if page is None:
            return pad_dir, None
        if not NAME_RE.match(page):
            return pad_dir, None
        page_file = os.path.join(pad_dir, page + ".md")
        if not os.path.isfile(page_file) or not inside(pad_dir, page_file):
            return pad_dir, None
        return pad_dir, page_file

    # --- GET -----------------------------------------------------------------

    def do_GET(self):
        if not self._host_ok():
            return self._error(403, "Forbidden host")
        path = urllib.parse.unquote(urllib.parse.urlparse(self.path).path)
        if path == "/health":
            return self._send(200, HEALTH_PREFIX + str(os.getpid()).encode("ascii"), "text/plain; charset=utf-8")
        if path == "/favicon.ico":
            return self._send(204, b"", "image/x-icon")
        parts = [p for p in path.split("/") if p]
        if not parts:
            return self._index()
        if len(parts) == 1:
            return self._pad_index(parts[0])
        if len(parts) == 2:
            return self._page(parts[0], parts[1])
        return self._error(404, "Not found")

    do_HEAD = do_GET

    def _index(self):
        pads = list_pads(self.server.home)
        items = "".join('<li><a href="/%s/">%s</a></li>' % (html.escape(p), html.escape(p))
                        for p in reversed(pads)) or "<li>No pads yet.</li>"
        self._send(200, page_shell("Scratchpads", None, None, '<a href="/">All pads</a>',
                                   "<h1>Scratchpads</h1><ul>%s</ul>" % items))

    def _pad_index(self, pad):
        pad_dir, _ = self._locate(pad)
        if not pad_dir:
            return self._error(404, "Pad not found")
        pages = list_pages(pad_dir)
        items = "".join('<li><a href="/%s/%s">%s</a></li>' % (html.escape(pad), html.escape(p), html.escape(p))
                        for p in pages) or "<li>No pages yet.</li>"
        self._send(200, page_shell(pad, pad, None, nav_html(pad, pages),
                                   "<h1>%s</h1><ul>%s</ul>" % (html.escape(pad), items)))

    def _page(self, pad, page):
        pad_dir, page_file = self._locate(pad, page)
        if not page_file:
            return self._error(404, "Page not found")
        with open(page_file, "rb") as handle:
            source = handle.read().decode("utf-8", "replace")
        state = Store(pad_dir).state()
        self._send(200, render_page(pad, page, source, state, list_pages(pad_dir)))

    # --- POST ----------------------------------------------------------------

    def _read_payload(self):
        """Validate a POST and return its JSON object; None after sending an error."""
        if not self._host_ok() or not self._origin_ok():
            self._error(403, "Forbidden origin")
            return None
        if not self.headers.get("Content-Type", "").startswith("application/json"):
            self._error(415, "JSON required")
            return None
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._error(400, "Bad Content-Length")
            return None
        if length <= 0 or length > MAX_BODY:
            self._error(413, "Body size not allowed")
            return None
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except ValueError:
            payload = None
        if not isinstance(payload, dict):
            self._error(400, "Invalid JSON")
            return None
        return payload

    def do_POST(self):
        payload = self._read_payload()
        if payload is None:
            return
        parts = [p for p in urllib.parse.urlparse(self.path).path.split("/") if p]
        if len(parts) != 3 or parts[0] != "api" or parts[2] not in POST_ROUTES:
            return self._error(404, "Not found")
        page = payload.get("page")
        if not isinstance(page, str):
            return self._error(400, "page required")
        pad_dir, page_file = self._locate(parts[1], page)
        if not page_file:
            return self._error(404, "Page not found")
        event, error = POST_ROUTES[parts[2]](Store(pad_dir), page, page_file, payload)
        if error:
            return self._error(*error)
        self._send(201, json.dumps({"id": event["id"]}), "application/json")


def comment_event(store, page, page_file, payload):
    """Validate a comment payload and append it. Returns (event, None) or (None, (code, message))."""
    text = payload.get("text")
    anchor = payload.get("anchor", "")
    heading = payload.get("heading", "")
    if not isinstance(text, str) or not text.strip() or len(text) > MAX_TEXT:
        return None, (400, "text required (max %d chars)" % MAX_TEXT)
    if not isinstance(anchor, str) or not ANCHOR_RE.match(anchor):
        return None, (400, "bad anchor")
    if not isinstance(heading, str) or len(heading) > 300:
        return None, (400, "bad heading")
    return store.add_comment(page, anchor, heading, text.strip()), None


def decision_event(store, page, page_file, payload):
    """Validate a decision answer against the page's decisions and append it."""
    decision = payload.get("decision")
    answer = payload.get("answer")
    if answer not in ANSWERS or not isinstance(decision, str) or not DECISION_ID_RE.match(decision):
        return None, (400, "bad decision answer")
    with open(page_file, "rb") as handle:
        parsed = render_markdown(handle.read().decode("utf-8", "replace"))
    if not [d for d in parsed.decisions if d["id"] == decision and not d["error"]]:
        return None, (404, "Decision not found on page")
    return store.add_decision_answer(page, decision, answer), None


POST_ROUTES = {"comments": comment_event, "decisions": decision_event}


def server_file(home):
    return os.path.join(home, SERVER_FILE)


def read_server_info(home):
    try:
        with open(server_file(home), "r") as handle:
            info = json.load(handle)
        if isinstance(info, dict) and isinstance(info.get("port"), int):
            return info
    except (OSError, ValueError):
        pass
    return None


def server_pid(port):
    """PID reported by the scratchpad server on `port`; None if nothing (or something else) answers."""
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/health" % port, timeout=1) as response:
            body = response.read()
    except Exception:
        return None
    digits = body[len(HEALTH_PREFIX):]
    if body.startswith(HEALTH_PREFIX) and digits.isdigit():
        return int(digits)
    return None


def server_healthy(port, pid=None):
    """True if a scratchpad server answers on `port` (and, when given, reports this `pid`)."""
    reported = server_pid(port)
    return reported is not None and (pid is None or reported == pid)


def remove_server_file(home, owner=None):
    """Remove the server record. With `owner=(pid, port)` only remove it if it still names that server,
    so a server shutting down never deletes the record of a newer one."""
    if owner is not None:
        info = read_server_info(home)
        if not info or (info.get("pid"), info.get("port")) != owner:
            return
    try:
        os.remove(server_file(home))
    except OSError:
        pass


def bind_server(home, first_port):
    last_error = None
    for port in range(first_port, first_port + PORT_ATTEMPTS):
        try:
            return ScratchpadServer(("127.0.0.1", port), home)
        except OSError as error:
            last_error = error
    raise ScratchpadError("No free port in %d-%d: %s" % (first_port, first_port + PORT_ATTEMPTS - 1, last_error))


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def pad_url(home, pad):
    info = read_server_info(home)
    if info and server_healthy(info["port"]):
        return "http://127.0.0.1:%d/%s/" % (info["port"], pad)
    return None


def open_store(args):
    home = pad_home()
    pad = resolve_pad(home, getattr(args, "pad", None))
    return home, pad, Store(os.path.join(home, pad))


def format_item(item):
    if item["kind"] == "comment":
        where = item["page"] + ("#" + item["anchor"] if item["anchor"] else "")
        head = "%s  %s  (%s)  %s" % (item["id"], where, item["heading"] or "no heading", item["author"])
        lines = [head] + ["  " + line for line in item["text"].splitlines()]
    else:
        head = "%s  %s  decision %s -> %s  %s" % (item["id"], item["page"], item["decision"],
                                                   item["answer"], item["author"])
        lines = [head]
    if item["handled"]:
        lines[0] += "  [handled]"
    for reply in item["replies"]:
        lines.append("  > %s: %s" % (reply["author"], reply["text"].replace("\n", " ")))
    return "\n".join(lines)


def print_batch(pad, items):
    print("pad: %s  unhandled: %d" % (pad, len([i for i in items if not i["handled"]])))
    for item in items:
        print(format_item(item))


_DANISH_LETTERS = {u"æ": "ae", u"ø": "oe", u"å": "aa"}


def pad_slug(topic):
    """ASCII-only slug for a pad folder name (pad names must match NAME_RE to be discoverable)."""
    text = topic.lower()
    for letter, replacement in _DANISH_LETTERS.items():
        text = text.replace(letter, replacement)
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^a-z0-9]+", "-", text).strip("-") or "pad"


def cmd_new(args):
    home = pad_home()
    name = "%s-%s" % (datetime.date.today().isoformat(), pad_slug(args.topic))
    pad_dir = os.path.join(home, name)
    if os.path.lexists(pad_dir):
        if not os.path.isdir(pad_dir):
            raise ScratchpadError("Pad path exists but is not a directory: %s" % pad_dir)
        if not inside(home, pad_dir):
            raise ScratchpadError("Pad is outside SCRATCHPAD_HOME: %s" % name)
    existed = os.path.isdir(pad_dir)
    os.makedirs(pad_dir, exist_ok=True)
    print("pad: %s%s" % (name, " (already existed)" if existed else ""))
    print("path: %s" % pad_dir)
    url = pad_url(home, name)
    print("url: %s" % (url or "(server not running; run `scratchpad start`)"))
    return 0


def log_tail(path, lines=8):
    try:
        with open(path, "rb") as handle:
            text = handle.read()[-4000:].decode("utf-8", "replace")
    except OSError:
        return "(no log)"
    return "\n".join(text.strip().splitlines()[-lines:]) or "(log is empty)"


def cmd_start(args):
    home = pad_home()
    os.makedirs(home, exist_ok=True)
    # Serialise concurrent starts: otherwise two callers can each spawn a server and the
    # loser's record is overwritten, leaving an orphan that `stop` can never reach.
    with file_lock(os.path.join(home, START_LOCK), timeout=30):
        return _start_server(args, home)


def _start_server(args, home):
    info = read_server_info(home)
    if info and server_healthy(info["port"]):
        print("running: http://127.0.0.1:%d/" % info["port"])
        return 0
    remove_server_file(home)
    os.makedirs(home, exist_ok=True)
    command = [sys.executable, os.path.abspath(__file__), "serve", "--port", str(args.port)]
    log_path = os.path.join(home, SERVER_LOG)
    # The server outlives this process, so its output goes to a log file, not a pipe nobody reads.
    with open(log_path, "ab") as log:
        options = {"stdin": subprocess.DEVNULL, "stdout": log, "stderr": log}
        if os.name == "nt":
            # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_NO_WINDOW
            options["creationflags"] = 0x00000008 | 0x00000200 | 0x08000000
        else:
            options["start_new_session"] = True
        subprocess.Popen(command, **options)
    deadline = time.time() + 8
    while time.time() < deadline:
        info = read_server_info(home)
        if info and server_healthy(info["port"]):
            print("started: http://127.0.0.1:%d/" % info["port"])
            return 0
        time.sleep(0.2)
    raise ScratchpadError("Server did not become healthy. Last log lines (%s):\n%s"
                          % (log_path, log_tail(log_path)))


def cmd_stop(args):
    home = pad_home()
    info = read_server_info(home)
    if not info:
        print("not running")
        return 0
    if not isinstance(info.get("pid"), int) or not server_healthy(info["port"], info["pid"]):
        # Stale record: the PID (and port) may since have been reused, so the PID is never signalled
        # unless the scratchpad server on the recorded port reports that same PID.
        remove_server_file(home)
        print("not running (removed stale server record)")
        return 0
    try:
        os.kill(info["pid"], signal.SIGTERM)
    except OSError:
        pass
    remove_server_file(home)
    print("stopped")
    return 0


def cmd_status(args):
    home = pad_home()
    info = read_server_info(home)
    if info and server_healthy(info["port"]):
        print("running: http://127.0.0.1:%d/ (pid %s)" % (info["port"], info.get("pid")))
    else:
        print("not running")
    print("home: %s" % home)
    return 0


def cmd_serve(args):
    home = pad_home()
    os.makedirs(home, exist_ok=True)
    running = read_server_info(home)
    if running and server_healthy(running["port"]):
        raise ScratchpadError("A scratchpad server is already running at http://127.0.0.1:%d/"
                              % running["port"])
    server = bind_server(home, args.port)
    port = server.server_address[1]
    with open(server_file(home), "w") as handle:
        json.dump({"pid": os.getpid(), "port": port}, handle)
    print("serving %s on http://127.0.0.1:%d/" % (home, port))
    sys.stdout.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        remove_server_file(home, (os.getpid(), port))
        server.server_close()
    return 0


def cmd_pages(args):
    home = pad_home()
    pad = resolve_pad(home, args.pad)
    url = pad_url(home, pad)
    print("pad: %s" % pad)
    for page in list_pages(os.path.join(home, pad)):
        print("%s  %s" % (page, (url + page) if url else page + ".md"))
    return 0


def cmd_inbox(args):
    _, pad, store = open_store(args)
    state = store.state()
    items = state.all_items() if args.all else state.unhandled()
    print_batch(pad, items)
    return 0


def cmd_wait(args):
    _, pad, store = open_store(args)
    items = wait_for_batch(store, args.quiet, args.timeout)
    if not items:
        print("pad: %s  no items (timeout after %ds)" % (pad, args.timeout))
        return 0
    print_batch(pad, items)
    return 0


def read_text_arg(words):
    if words == ["-"]:
        # Decode as UTF-8 ourselves: sys.stdin would use the Windows console code page.
        text = sys.stdin.buffer.read().decode("utf-8", "replace")
    else:
        text = " ".join(words)
    text = text.strip()
    if not text:
        raise ScratchpadError("Reply text is empty")
    return text


def cmd_reply(args):
    _, pad, store = open_store(args)
    if store.state().get(args.id) is None:
        raise ScratchpadError("Unknown item %s" % args.id)
    store.add_reply(args.id, read_text_arg(args.text))
    print("replied to %s" % args.id)
    return 0


def cmd_done(args):
    _, pad, store = open_store(args)
    state = store.state()
    for ident in args.ids:
        if state.get(ident) is None:
            raise ScratchpadError("Unknown item %s" % ident)
    for ident in args.ids:
        store.mark_handled(ident)
        print("handled %s" % ident)
    return 0


def cmd_check(args):
    home = pad_home()
    pads = [resolve_pad(home, args.pad)] if args.pad else list_pads(home)
    problems = 0
    for pad in pads:
        pad_dir = os.path.join(home, pad)
        state = Store(pad_dir).state()
        if state.bad_lines:
            print("%s: %d unreadable line(s) in %s (skipped)" % (pad, state.bad_lines, LOG_NAME))
            problems += 1
        for page in list_pages(pad_dir):
            with open(os.path.join(pad_dir, page + ".md"), "rb") as handle:
                result = render_markdown(handle.read().decode("utf-8", "replace"))
            for decision in result.decisions:
                if decision["error"]:
                    print("%s/%s: decision '%s': %s" % (pad, page, decision["id"] or "?", decision["error"]))
                    problems += 1
            known = set(slug for _, _, slug in result.headings)
            for comment in state.comments_for(page):
                if comment["anchor"] not in known and not comment["handled"]:
                    print("%s/%s: %s is detached (heading '%s' not found)" % (
                        pad, page, comment["id"], comment["anchor"]))
                    problems += 1
    print("ok" if not problems else "%d problem(s)" % problems)
    return 1 if problems else 0


def build_parser():
    parser = argparse.ArgumentParser(prog="scratchpad", description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command")
    sub.required = True

    def add(name, func, help_text):
        p = sub.add_parser(name, help=help_text)
        p.set_defaults(func=func)
        return p

    p = add("new", cmd_new, "create a pad folder for a topic")
    p.add_argument("topic")
    p = add("start", cmd_start, "start the local server if it is not running")
    p.add_argument("--port", type=int, default=DEFAULT_PORT)
    add("stop", cmd_stop, "stop the local server")
    add("status", cmd_status, "show server status")
    p = add("serve", cmd_serve, "run the server in the foreground")
    p.add_argument("--port", type=int, default=DEFAULT_PORT)
    p = add("pages", cmd_pages, "list the pad's pages")
    p.add_argument("--pad")
    p = add("inbox", cmd_inbox, "show unhandled comments and decision answers")
    p.add_argument("--pad")
    p.add_argument("--all", action="store_true", help="include handled items")
    p = add("wait", cmd_wait, "block until the human has been quiet, then print the batch")
    p.add_argument("--pad")
    p.add_argument("--quiet", type=int, default=10, help="seconds of quiet before returning (default 10)")
    p.add_argument("--timeout", type=int, default=600, help="give up after this many seconds (default 600)")
    p = add("reply", cmd_reply, "reply to an item (use - to read the text from stdin)")
    p.add_argument("--pad")
    p.add_argument("id")
    p.add_argument("text", nargs="+")
    p = add("done", cmd_done, "mark items handled")
    p.add_argument("--pad")
    p.add_argument("ids", nargs="+")
    p = add("check", cmd_check, "report malformed decisions, detached comments and bad log lines")
    p.add_argument("--pad")
    return parser


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except (ScratchpadError, OSError) as error:  # OSError: bad SCRATCHPAD_HOME, permissions, full disk
        sys.stderr.write("scratchpad: %s\n" % error)
        return 1


if __name__ == "__main__":
    sys.exit(main())

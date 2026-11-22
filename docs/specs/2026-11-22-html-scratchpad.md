# HTML Scratchpad

## Problem

Chat windows and plain markdown files are poor surfaces for non-trivial agent/human collaboration. Conversations branch, answers get buried in linear back-and-forth, and a markdown file has no way to take structured feedback (section comments, decision answers) back to the agent.

Nick Tune's post "Moving to HTML-based collaboration with agents" (2026-11-21) describes a workflow that addresses this: the agent writes markdown pages, a local tool renders them as HTML, and the human gives feedback in the browser. His tool (`NTCoding/wip-skillz`, `scratch-pad`) has no license, needs Node 24 + pnpm + a React UI, and is macOS-oriented, so it is not a fit as a fork or a dependency. We take the design ideas only and write our own implementation and our own SKILL.md wording; no code is copied.

## Approach

One background local server with plain files as the source of truth (chosen over a static HTML export, which cannot take feedback, and over a SQLite-backed server, which is opaque to the agent and Obsidian and is more code than v1 needs).

- **Runtime:** Python 3, standard library only. One script, no install step, works on Windows and macOS. Code must stay 3.7-compatible (older macOS Python).
- **Storage:** global home folder, `~/scratchpads/<yyyy-mm-dd>-<topic>/`, overridable with `SCRATCHPAD_HOME`. Pads are not tied to a repo, need no git-ignoring, and a folder can be opened in Obsidian as a passive viewer.
- **v1 features:** section comments with replies, decision blocks, inbox with batched `wait`.
- **Agent contract:** the agent writes markdown and calls CLI commands. It never writes HTML and never edits `comments.jsonl` by hand.

## Design

### Components and layout

```
tools/scratchpad.py            single-file tool: CLI + server + renderer
tools/scratchpad.sh            thin bash launcher (python3 -> python, version check)
tools/scratchpad.ps1           thin Windows launcher (python3 -> python -> py -3)
tools/tests/                   unittest suite
skills/scratchpad/SKILL.md     agent instructions, trigger phrases, command table

~/scratchpads/<yyyy-mm-dd>-<topic>/
  1-overview.md, 2-options.md, ...    agent-written pages
  comments.jsonl                      append-only event log
```

| Unit | Responsibility |
|------|----------------|
| Renderer | Markdown to HTML. Supported subset only: headings, lists, code, tables, links, `:::decision` blocks. HTML-escapes all text; no raw HTML passthrough. |
| Store | Reads and appends `comments.jsonl`; replays events to derive state. |
| Server | Serves pages and a small POST API, backed by the store. |
| CLI | `new`, `start`, `stop`, `inbox`, `wait`, `reply`, `done`, `pages`, `check`. Reads and writes through the store and does not need the server, except `start`/`stop`. |

`comments.jsonl` event types: `comment` (page, heading anchor, text), `reply`, `decision_answer`, `handled`. Item ids are incrementing: `c-N` for comments, `d-N` for decisions. Each event carries a timestamp and an author (`human` or `agent`). State is derived by replaying the log, so there is no mutable file for two processes to corrupt. Rewriting a page never touches the log, so feedback cannot be lost by an edit.

### Data flow

**Session start**
1. `scratchpad new <topic>` creates the pad folder and prints its path and URL.
2. `scratchpad start` is idempotent: it checks a pidfile and a health endpoint, and spawns a detached server only if neither responds. The server binds to `127.0.0.1:4747`, falling back to the next free port; the port is recorded in the pidfile and the CLI always reads it from there.
3. The agent writes pages and posts a short chat message linking to the pad.

**Feedback loop**
1. The renderer adds a comment control to every heading and answer buttons to every decision card.
2. A comment sends `POST /api/<pad>/comments` with `{page, anchor, text}`. The anchor is the heading slug, with the heading text kept as a fallback.
3. The server appends a `comment` event to the log.
4. The agent runs `scratchpad wait` in the background. It polls the log's mtime and returns once the human has been quiet for N seconds (`--quiet`, default 10), printing every unhandled item as one batch. `--timeout` (default 10 minutes) makes it exit with an empty batch, so a stalled wait cannot hang the agent.
5. The agent edits the markdown, then runs `scratchpad reply <id> "text"` per comment and `scratchpad done <id>` per handled item. Both append events; earlier lines are never edited.
6. The page re-renders on the next load, with threads under each heading and handled items collapsed.

**Decisions**

```
:::decision retry-limit
proposal: Cap retries at 3
alternative: Unlimited with backoff
pick: proposal
:::
```

Rendered as a card with the agent's pick highlighted and two answer buttons. A click posts a `decision_answer` event, which appears in `inbox` as `d-N`. After the agent rewrites the page to reflect the answer and runs `done d-N`, the card renders as resolved with the human's choice.

**State rules**
- An item is unhandled if no later `handled` event references it.
- If a heading is renamed or removed, its comments no longer match an anchor. They appear in a "Detached" list at the bottom of the page and stay in the inbox until handled.
- The server and the CLI both append to the log. Each append is one `write` of one complete line to a file opened in append mode, under a short advisory lock (`msvcrt.locking` on Windows, `fcntl.flock` elsewhere). Readers ignore a trailing partial line.

## Error Handling

| Failure | Behaviour |
|---|---|
| Server dies mid-session | The POST fails; the UI shows "not saved, server stopped" and keeps the draft in the textarea. |
| Stale pidfile | `start` checks the health endpoint, not just the pid. If unreachable, remove the pidfile and spawn a new server. |
| Port 4747 taken | Fall back to the next free port; record it in the pidfile. |
| Python missing | Launchers check `command -v python3`, then `python` (and `py -3` on Windows), and fail fast with an install message. |
| Python older than 3.7 | Launcher checks the version and exits with a clear message. |
| Corrupt or partial JSONL line | The store skips it, `check` warns, `inbox` and `wait` carry on. |
| `wait` hangs | `--timeout` exits with an empty batch; SKILL.md tells the agent to re-run it in the background. |
| Unknown pad, page or item id | Exit non-zero with "Pad not found" / "Unknown item c-9". Existence is checked before the path is resolved (repo review lesson). |
| Path traversal | Requested paths are resolved and must stay inside `SCRATCHPAD_HOME`. Only `.md` files and API routes are served. |
| Unsafe markdown or cross-site POST | All text is HTML-escaped; no raw HTML passthrough. The server binds only to 127.0.0.1 and checks `Origin`/`Host` on POSTs against localhost to block drive-by requests from other sites. |
| Malformed `:::decision` block | Renders as a visible error card and is reported by `check`; the page still loads. |

## Testing

- **Unit tests** (`unittest`, stdlib only, in `tools/tests/`, runnable on Windows and a POSIX shell):
  - Renderer: supported subset, escaping, decision blocks, malformed input.
  - Store: append, replay, handled state, partial last line, detached anchors.
  - `wait` quiet-window logic with an injected clock.
- **Integration test:** start the server on a random port against a temp `SCRATCHPAD_HOME`; POST a comment and a decision answer; verify `inbox` shows them; `reply` and `done` them; verify the rendered page reflects the thread.
- **Pre-PR checklist (CLAUDE.md):** run the tool end-to-end locally (Windows, ideally also macOS/Linux); run every shell snippet in SKILL.md; use `stdout=subprocess.PIPE, stderr=subprocess.PIPE` rather than `capture_output=True`; `export` any env var a child process reads; place option flags before `--`; default to `$repo_root` rather than `.` where a repo default applies; sync SKILL.md in the same commit.

## Repo Changes

- Add `skills/scratchpad/SKILL.md` (lowercase kebab-case name; description lists explicit trigger phrases).
- Add the matching row to `docs/skills.md`, kept in sync with the operations table in SKILL.md.
- Update the `tools/` line in `.github/copilot-instructions.md` if it needs to mention the new tool.
- Commit scopes derived from the files actually changed (`skills`, `tools`, `docs`).

## Out of Scope

- Text-selection anchors (v1 anchors to headings).
- Progress tracker, goal and task commands (the agent can keep a plain markdown page).
- Grammar and improvement notes, and export snapshots.
- Multi-user access and authentication beyond the localhost binding.
- Obsidian integration beyond opening the pad folder as a passive viewer. Promoting finished pages into the vault stays with the `capture` skill.

# AIchemist – Claude Code Instructions

See `.github/copilot-instructions.md` for full repository structure, component schemas, and commit conventions.

## Pre-PR Checklist for Shell Tools (`tools/`)

Before opening a PR that touches a file in `tools/`:

1. **Run the script end-to-end locally.** Don't rely on static review alone — a missing `export`, a wrong Python flag, or an API field gap will only surface at runtime.

2. **Sync the companion SKILL.md in the same commit.** If a tool's interface changes (new subcommand, new flag, new dependency), update `skills/<name>/SKILL.md` before opening the PR — not after Copilot points it out.

3. **Check `$select` against what downstream consumers reference.** Read the SKILL.md workflow sections and verify every field they mention (e.g. `onlineMeetingUrl`) is included in the API query's `$select`.

4. **Run every shell snippet in the SKILL.md docs.** Copy-paste each example into a terminal. Nested-quote issues and missing `)` in `$()` substitutions won't show up in a text diff.

5. **Use `stdout=subprocess.PIPE, stderr=subprocess.PIPE` in Python subprocesses** — not `capture_output=True` (Python 3.7+). macOS ships with older Python on some versions.

6. **Verify `export` on variables read by child processes.** Any shell variable passed to a Python heredoc via `os.environ` must be `export`ed, not just assigned.

## Pre-PR Checklist for Mods (`mods/`)

1. **Keep the mod additive.** It may call a skill's tool, but it must not move logic out of the skill. Copilot CLI shares the skills and never runs mods.
2. **Run `claude plugin validate mods/<name>` and `claude plugin test mods/<name>`**, plus `claude plugin validate .` for the marketplace entry.
3. **Symlink shared scripts, don't copy them.** Check that `bash mods/<name>/tools/<script>.sh` still resolves.

## Code Review Lessons

- Skill `name` field must be lowercase kebab-case — matches the directory name and the slash-command trigger (e.g. `name: pr-review-loop`, not `name: PR Review Loop`)
- Skill `description` must enumerate explicit trigger phrases so the model knows when to auto-activate the skill
- New skills must be registered in `docs/skills.md`; the operations table in SKILL.md and the matching rows in docs/skills.md must be kept in sync
- Commit message scopes must be derived from the actual files changed — not hardcoded; for repo-root files use `repo`, for skills use `skills`, etc.
- GraphQL `comments(first: N)` — only fetch as many comments as you will consume; if only `nodes[0]` is used, request `first: 1`
- PR description must accurately reflect code changes — do not describe a change (e.g. `first: 10`) that wasn't actually applied
- Shell path validation order: check existence (`[[ ! -e "$target" ]]`) before resolving with `realpath`/`python3` — resolving a missing path produces a misleading "must be within repo" error instead of "Path not found"
- Shell tool availability: always guard with `command -v realpath` → `command -v python3` → fail-fast with install message; never assume either is present on macOS
- `git log` pathspecs must be repo-relative — use `${absolute#$repo_root/}` to derive; special-case `target == repo_root` → use `.` (prefix-strip is a no-op when there is no trailing `/`)
- `git rev-parse --show-toplevel` must be wrapped in `if ! ... 2>/dev/null` to fail fast with a clear error when run outside a git repository
- CLI flags after `--` are treated as positional arguments — always place option flags (e.g. `--csv`) before `--` in command invocations
- No-arg default targets in shell skills should use `$repo_root`, not `.` — CWD varies when invoked from a subdirectory
- Structured agent output tokens that bypass the validation step (e.g. `HOTSPOT_FINDING`) need an explicit exemption note in the consuming skill's Step 6
- Always include a `location: <file>:<line>` field in structured finding tokens so the code-review skill can anchor inline PR comments
- Names validated by an ASCII-only regex (e.g. pad or folder names) must be built from an ASCII-only slug — transliterate (`æ`→`ae`, `ø`→`oe`, `å`→`aa`) and fall back to a default when nothing survives; otherwise a non-ASCII topic creates a folder that discovery then cannot see
- A detached, long-lived subprocess (a local server) must send its output to a log file, not a pipe nobody reads — the `stdout=PIPE, stderr=PIPE` rule is for capturing output you consume; show the log tail when startup fails
- Never signal a PID read from a state file unless the process is confirmed to be yours (e.g. its health endpoint answers on the recorded port) — PIDs get reused; treat an unreachable server as a stale record and remove it
- `urlparse(...).port` raises `ValueError` on a malformed port — wrap it when parsing untrusted headers such as `Origin`, and answer 403/400 instead of letting the handler crash
- Containment checks apply to discovery as well as access: filter listed entries with a resolved-path `inside(root, path)` check so a symlink pointing outside the root is never listed or resolved
- Split parsers and request handlers into per-block / per-step helpers up front; a hotspot scan on the first draft flagged `render_markdown` (CCN 38) and `do_POST` (CCN 31)

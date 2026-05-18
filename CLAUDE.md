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

## Code Review Lessons

- Skill `name` field must be lowercase kebab-case — matches the directory name and the slash-command trigger (e.g. `name: pr-review-loop`, not `name: PR Review Loop`)
- Skill `description` must enumerate explicit trigger phrases so the model knows when to auto-activate the skill
- New skills must be registered in `docs/skills.md`; the operations table in SKILL.md and the matching rows in docs/skills.md must be kept in sync
- Commit message scopes must be derived from the actual files changed — not hardcoded; for repo-root files use `repo`, for skills use `skills`, etc.
- GraphQL `comments(first: N)` — only fetch as many comments as you will consume; if only `nodes[0]` is used, request `first: 1`
- PR description must accurately reflect code changes — do not describe a change (e.g. `first: 10`) that wasn't actually applied

# Mods (Claude Code only)

[Mods](https://claude.com/blog/claude-code-mods) are small TypeScript hook modules that change how Claude Code behaves or looks: a status line entry, a toast, a pane, a rule on a tool call. AIchemist ships them as **separate plugins** under `mods/`, listed only in the Claude marketplace (`.claude-plugin/marketplace.json`).

The core `aichemist` plugin (skills, agents, tools, hooks) is shared with GitHub Copilot CLI, so mods follow one rule:

> **A mod adds a layer on top of a skill or tool. It never takes its place.**

- Skills and `tools/*.sh` stay the source of truth. A mod calls them and does not reimplement them in TypeScript.
- Uninstall the mod, and Claude Code behaves exactly as Copilot CLI does.
- Logic is never moved out of a skill into a mod, so Copilot doesn't quietly fall behind.

## Available Mods

### Calendar Status

Shows your current and next Microsoft 365 meeting in the status line, e.g. `📅 Now: Planning (ends in 20m) · Next: 1:1 in 45m`. A toast appears shortly before each meeting starts.

**Source:** [`mods/calendar-status/`](../mods/calendar-status/)

**Install:**
```bash
claude plugin install aichemist-calendar-status@aichemist
```

**Requirements:** the same setup as the [Calendar skill](skills.md#calendar-skill): `MSGRAPH_APP_ID` and `MSGRAPH_TENANT_ID` exported, `python3` on `PATH`, and a one-time `msgraph.sh login`. Without the two variables, the mod does nothing.

**How it works:** on session start the mod runs `tools/msgraph.sh get-events` (the calendar skill's script, symlinked into the mod) every few minutes and redraws the countdown every minute. Cancelled and all-day events are skipped, and events marked private show as "Private event". If a fetch fails (expired login, offline), the last good list is kept. The mod skips non-interactive sessions, so `claude -p` runs are unaffected.

**Options** (`/plugin configure aichemist-calendar-status@aichemist`, or `/config`):

| Option | Default | Description |
|--------|---------|-------------|
| `refreshMinutes` | `5` | How often to fetch events from Microsoft Graph |
| `lookaheadHours` | `8` | How far ahead to look for the next meeting |
| `reminderMinutes` | `2` | Toast this many minutes before a meeting starts; `0` turns reminders off |

### PR Review Pane

A read-only pane showing what the [PR Review Loop skill](skills.md#pr-review-loop-skill) works on, for the current branch's PR:
- the loop's state (`WAITING`, `REVIEWING` or `DONE`, by the skill's rule)
- when Copilot last reviewed, and on which commit, next to the head commit
- CI totals, naming the failing checks
- every unresolved thread, Copilot's apart from people's, with its location and first line

**Source:** [`mods/pr-review-pane/`](../mods/pr-review-pane/)

**Install:**
```bash
claude plugin install aichemist-pr-review-pane@aichemist
```

**Use:** `/pr-pane` opens it for the current branch; `/pr-pane 123` pins it to PR #123. In the pane, `r` refreshes and `q` closes it. When Copilot has reviewed and threads are open, `l` (**Run review loop**) asks Claude to run the skill for that PR.

**Requirements:** [`gh`](https://cli.github.com/) installed and authenticated (`gh auth status`), run from a repository with an open PR.

**How it works:** the pane runs `gh pr view` and one `gh api graphql` query for the review threads, with the same fields and the same Copilot login (`copilot-pull-request-reviewer`) as the skill. It refreshes while open and does nothing while closed. It never writes to GitHub: fixing, replying and resolving stay with the skill. Review comment text is only displayed. It never goes into the prompt the button sends.

Like the skill, the pane counts Copilot as having reviewed the latest push when its latest review was made on the PR's head commit.

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `refreshSeconds` | `60` | How often the open pane re-reads the PR (minimum 15) |

## Developing a Mod

Each mod is its own plugin folder:

```
mods/<name>/
  .claude-plugin/plugin.json   Manifest (name: aichemist-<name>), version kept by release-please
  hooks/hooks.json             { "modules": ["./register.ts"] }
  hooks/register.ts            export const register: Register = (on, options) => { ... }
  tests/*.test.ts              Run with claude plugin test
  tools/<script>.sh            Symlink to ../../../tools/<script>.sh when reusing a shared tool
```

To reuse a shared script, symlink it into the mod rather than copying it. When Claude Code copies a marketplace plugin into its cache, a symlink to another file in the same marketplace is replaced by the file's content, so the installed mod gets the current script. A mod can't reach `../../tools` at runtime.

Before opening a PR:

```bash
claude plugin validate mods/<name>         # manifest + hooks module
claude plugin test mods/<name>             # *.test.ts
claude plugin validate .                   # marketplace entry
claude --plugin-dir mods/<name>            # try it in a real session
```

Then:

1. Add the mod to `.claude-plugin/marketplace.json`. Don't add it to `.github/plugin/marketplace.json`.
2. Add its `plugin.json` to `extra-files` in `release-please-config.json`.
3. Document it in this file.

Mods run with the same access to your machine as Claude Code itself. They aren't sandboxed.

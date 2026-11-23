---
name: setup
description: |
  This skill should be used when the user asks to "set up aichemist", "setup aichemist", "configure aichemist", "configure the plugin", "set up this plugin", "aichemist doctor", "check my aichemist setup", "what do I need to install", "what environment variables does aichemist need", "why isn't the calendar working", "fix my plugin setup", or when another skill fails because a dependency, environment variable or MCP server is missing. Diagnoses missing tools, env vars and MCP servers, then installs and configures them with confirmation.
version: 1.0.0
---

# Setup Skill

Gets the plugin working on a machine: finds what is missing, explains what each piece is for, and fixes it — **after the user confirms each change**. Most integrations are optional, so ask which ones the user wants before checking them.

This skill orchestrates; it does not duplicate. `tools/bootstrap/bootstrap-machine.{sh,ps1}` owns dependency installation, and each skill's `SKILL.md` owns its own usage. This skill adds the per-user configuration those do not cover.

## Operations

| Request | What happens |
|---------|--------------|
| "check my aichemist setup", "aichemist doctor" | **Diagnose** — read-only report of what is ready and what is missing |
| "set up aichemist", "configure the plugin" | **Guided setup** — pick integrations, diagnose, then fix each gap with confirmation |
| "set up the calendar", "configure postgres" | **Single integration** — run the same flow for one row of the table below |
| A skill failed on a missing tool or variable | **Targeted fix** — jump to the matching integration |

## Operation Types

| Type | Operations | Behavior |
|------|------------|----------|
| **Read** | Run `doctor`, `command -v`, check whether a variable is *set* (never print its value), read `settings.json`, `git config` | Automatic — no confirmation needed |
| **Write** | Run `bootstrap-machine.sh install`, install a tool, `docker pull`, `mempalace init` | Requires explicit user confirmation |
| **Write** | Add or change a variable under `env` in `settings.json`, edit a shell profile, `git config` | Requires explicit user confirmation — show the exact change first |
| **Write** | Write `obsidian.preferredVault` to `${CLAUDE_PLUGIN_ROOT}/config.json` | Requires explicit user confirmation |
| **Interactive** | `calendar.sh login` (opens a browser), `gh`/`m365` auth | Tell the user what will happen, then run only after they confirm |

### Confirmation Prompts

| Action | Prompt |
|--------|--------|
| Run installer | "Run `bootstrap-machine.sh install`? It installs: <list from the Brewfile/winget set>. (yes/no)" |
| Install one tool | "Install `<tool>` with `<command>`? (yes/no)" |
| Set an env var in `settings.json` | "Add `<NAME>=<value>` under `env` in `<path>`? Applies to <all projects / this project>. (yes/no)" |
| Edit a shell profile | "Append `export <NAME>=<value>` to `<profile>`? (yes/no)" |
| Enable the commit gate | "Enable the commit gate <everywhere via env / for this repo via git config>? It runs the repo's build, test and format commands before `git commit` and `git push`. (yes/no)" |
| Save the Obsidian vault | "Save `<vault>` as `obsidian.preferredVault` in `config.json`? (yes/no)" |

Show the change, wait for an answer, apply it, then re-run the integration's verify command. Batch related changes into one prompt rather than asking per variable.

## Workflow

### Step 1 — Choose integrations

Ask which integrations the user wants (multi-select). Skip the rest silently. Core tools (`jq`, `python3`, `node`, `uv`) are checked regardless.

### Step 2 — Diagnose

Run the existing doctor first, and reuse its output rather than re-deriving it:

```bash
"${CLAUDE_PLUGIN_ROOT}/tools/bootstrap/bootstrap-machine.sh" doctor        # macOS
pwsh "${CLAUDE_PLUGIN_ROOT}/tools/bootstrap/bootstrap-machine.ps1" doctor  # Windows
```

It reports `READY:` / `MISSING:` lines with an `ACTION:` fix for each. The bash script is **macOS only** — it exits with an error on Linux. On Linux, check each row of the table below by hand with `command -v <tool>`.

Then check variables for the chosen integrations. Test that they are *set*, never print them — several hold credentials:

```bash
for v in POSTGRES_URL MSGRAPH_APP_ID MSGRAPH_TENANT_ID CALDAV_USERNAME OBSIDIAN_VAULT; do
  if [ -n "${!v:-}" ]; then echo "set:   $v"; else echo "unset: $v"; fi
done
```

Also check whether the `.mcp.json` servers connected (`/mcp`). `markitdown` needs a running Docker daemon; `mempalace` needs `uv`.

Report a single summary table (integration · status · what is missing) before changing anything.

### Step 3 — Fix, with confirmation

Work through the gaps one integration at a time, in the order below. For each: explain what it is for in one line, propose the exact commands/changes, confirm, apply, verify.

If the user wants everything installed on a fresh machine, offer `bootstrap-machine.sh install` once (confirmed) instead of installing tools one by one.

### Step 4 — Summarize

List what was changed (files edited, variables set, tools installed), what still needs the user (browser logins, restarting Claude Code so `settings.json` `env` takes effect, reopening the shell), and what was skipped.

## Integrations

| Integration | Skills | Tools needed | Variables / config | Verify |
|-------------|--------|--------------|--------------------|--------|
| **Core** | all | `jq`, `python3` (3.7+), `node`, `uv` | – | `command -v jq python3 node uv` |
| **Obsidian** | `obsidian`, `daily-note`, `capture`, `research` | Obsidian desktop app v1.5.0+ (running) | Vault saved as `obsidian.preferredVault` in `config.json`; `OBSIDIAN_VAULT` is read only by the skill-suggester hook — exporting it alone does **not** configure the Obsidian skills, so always save the vault to `config.json` | `obsidian vaults` |
| **Calendar — Microsoft 365** | `calendar` | `python3`, `m365` (`npm i -g @pnp/cli-microsoft365`) | `MSGRAPH_APP_ID`, `MSGRAPH_TENANT_ID`; one-time `calendar.sh login` | `tools/calendar/calendar.sh provider` |
| **Calendar — iCloud/CalDAV** | `calendar` | `python3` | `CALDAV_USERNAME`; `CALDAV_PASSWORD_CMD` (preferred) or `CALDAV_PASSWORD`; `CALDAV_URL` for non-iCloud servers | `tools/calendar/calendar.sh check` |
| **PostgreSQL** | `postgresql` | `psql` | `POSTGRES_URL` | `psql "$POSTGRES_URL" --no-password -c 'SELECT 1'` |
| **Beads** | `beads` | `bd` (`brew install beads`) | optional `AICHEMIST_BEADS_HOME` | `bd --version` |
| **MemPalace** | `mempalace` | `uv`, `mempalace` (`uv tool install mempalace`) | optional `MEMPALACE_HOME` (default `~/.mempalace`); `mempalace init` once | `mempalace status` (as in `docs/configuration.md`), or the `mempalace_status` MCP tool |
| **Markitdown** | `markitdown` | Docker (daemon running), pinned `mcp/markitdown` image | – | `tools/markitdown/markitdown.sh <file>` |
| **Jira** | `jira`, `ticket-flow`, `code-review` | Atlassian MCP server (official integration, via `/mcp`) | – (user info is auto-fetched into `config.json`) | ask Claude to run `atlassian/atlassianUserInfo` |
| **Hotspot** | `hotspot`, `code-review` | `lizard` | – | `lizard --version` |
| **Playwright** | `playwright` | `playwright-cli` (`npm i -g @playwright/cli`) | – | `playwright-cli --version` |
| **Excalidraw** | `excalidraw` | A running canvas server, MCP server added by the user | `EXPRESS_SERVER_URL` on the MCP server entry | `/mcp` shows `excalidraw` connected |
| **Commit gate** | hook | `python3` | `AICHEMIST_GATE=1` (or `git config aichemist.gate true`); optional `AICHEMIST_GATE_BUILD/_TEST/_FORMAT`, `AICHEMIST_GATE_SKIP` | `git config --get aichemist.gate` |
| **Scratchpad** | `scratchpad` | `python3` | optional `SCRATCHPAD_HOME` (default `~/scratchpads`) | `tools/scratchpad/scratchpad.sh status` |

Source of truth for details: each skill's `SKILL.md`, [`docs/configuration.md`](../../docs/configuration.md) and [`docs/installation.md`](../../docs/installation.md). If this table and a skill disagree, the skill wins — fix the table.

## Where to Put Configuration

| Kind of setting | Put it in | Why |
|-----------------|-----------|-----|
| Variable Claude Code and its hooks need (`AICHEMIST_GATE*`, `POSTGRES_URL`, `CALDAV_*`, `MSGRAPH_*`, `AICHEMIST_BEADS_HOME`) | `env` in `~/.claude/settings.json` (all projects) or `.claude/settings.local.json` (one project, not committed) | Reaches the agent's shell and hooks without a shell profile; takes effect after a restart |
| Variable also needed outside Claude Code (shell, Copilot CLI) | Shell profile (`~/.zshrc`, `~/.bash_profile`) | Shared with every terminal |
| Obsidian vault choice | `${CLAUDE_PLUGIN_ROOT}/config.json` (`obsidian.preferredVault`) | Where the Obsidian skills already read it; the file is git-ignored |
| Per-repo opt-in (commit gate) | `git config aichemist.gate true` | Never a marker file in the repo — an untrusted clone could ship one |

To edit `settings.json`, defer to the `update-config` skill when available: it merges rather than overwrites and validates the result. Never replace the whole file. Read it first and change only the keys being added.

## Security Rules

- **Never put a secret value in `settings.json`, `.claude/settings.local.json` or a committed file** — these can end up in version control or backups. Use a command that prints the secret: `CALDAV_PASSWORD_CMD='security find-generic-password -s icloud-caldav -w'`. For `POSTGRES_URL`, prefer a read-only role and keep the password in `~/.pgpass` (leave it out of the URL). If the password must be in the URL, tell the user it will be stored in plain text in that file and let them decide.
- **Never ask the user to paste a secret into the chat.** Give the command for them to run themselves (for example `security add-generic-password …`), or have them export it in their own shell.
- **Never print a variable's value** when checking. Report `set` / `unset` only.
- **The commit gate runs repository-controlled commands.** Recommend `git config aichemist.gate true` per trusted repo over enabling it globally, and say so.
- **Pin what is pinned.** The markitdown image is pinned by digest in `.mcp.json`; use that digest rather than `latest`.

## Error Handling

| Situation | Action |
|-----------|--------|
| `bootstrap-machine.sh` exits with "supports macOS only" | Switch to manual per-tool checks (Linux) or the `.ps1` script (Windows) |
| `brew`, `winget` or `npm` not available | Report it as the blocker and link its install page; do not guess an alternative package manager |
| Docker installed but daemon not running | Ask the user to start Docker Desktop, then re-run the check |
| Variable set in `settings.json` but still reads `unset` | It applies only to new sessions — tell the user to restart Claude Code |
| `calendar.sh provider` reports no backend | Ask which provider they use; if both variable sets exist, set `CALENDAR_PROVIDER` explicitly |
| Obsidian CLI not found | Confirm the app is installed and running, then use the platform path from the `obsidian` skill's Prerequisites |
| User declines a change | Skip it, note it in the summary, continue with the next integration |

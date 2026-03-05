---
name: Beads Task Tracking
description: |
  This skill should be used when the user asks to "track tasks with beads", "use bd", "add a beads task", "show ready tasks", "claim a task", "list bd tasks", "create a bd issue", "show my tasks", "what's ready to work on", "update task status", or mentions beads task IDs like "bd-a1b2". Provides beads (bd) integration for AI-native task tracking with automatic sidecar storage outside the repo by default.
version: 1.0.0
---

# Beads Task Tracking Skill

This skill integrates Claude Code with [Beads](https://github.com/steveyegge/beads) (`bd`), a distributed, git-backed graph issue tracker built for AI coding agents. It handles task creation, dependency tracking, and status management — with storage defaulting **outside** the working repo using the `--db` flag.

---

## Prerequisites

Before any operation, check if `bd` is installed:

```bash
which bd
```

**If not found:**

---
**Beads (`bd`) is not installed.**

Install with one of:

```bash
brew install beads          # macOS/Linux — recommended (verified checksums)
npm install -g @beads/bd    # npm
go install github.com/steveyegge/beads/cmd/bd@latest  # Go
```

After installing, retry your request.

---

Dolt (the database backend) is bundled with beads and its server is auto-started transparently — no separate installation or server management needed. After resolving `BD_DB` using the steps below, use `bd dolt status --db "$BD_DB"` to inspect it if something seems wrong, and `bd doctor --db "$BD_DB"` for a full health check.

---

## Storage Mode Detection

Run this logic **once per session** to determine where the beads database lives. Store the resolved `$BD_DB` path for use in all subsequent `bd --db "$BD_DB"` calls.

### Step 1 — Get repo info

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
REPO_NAME=$(basename "$REPO_ROOT")
```

### Step 2 — In-repo mode

Check if this repo has already initialized beads:

```bash
ls "$REPO_ROOT/.beads/"*.db 2>/dev/null
```

**If a `.db` file exists → use in-repo mode.** Set:

```bash
BD_DB=$(ls "$REPO_ROOT/.beads/"*.db | head -1)
```

Inform the user:
> "Using in-repo beads storage (this repo has beads initialized)."

Skip the remaining steps and proceed to [Running Commands](#running-commands). Even though `bd` can auto-discover `.beads/` when run from the repo root, `--db "$BD_DB"` is still passed explicitly for consistency and to ensure commands work regardless of the current working directory.

### Step 3 — Sidecar mode (default)

Build the sidecar path keyed by repo name:

```bash
SIDECAR_DIR="$HOME/.beads/$REPO_NAME"
MARKER="$SIDECAR_DIR/.beads-repo-path"
```

#### Collision detection

If `$SIDECAR_DIR` already exists, check whether it belongs to this repo:

```bash
cat "$MARKER" 2>/dev/null
```

- **Matches `$REPO_ROOT`** → use `$SIDECAR_DIR` as-is
- **Marker missing or mismatch** → the sidecar belongs to another (or unknown) repo. Use a fallback:

```bash
# Suffix = parent directory name, e.g. /Users/alice/work/my-app → "work"
SUFFIX=$(basename "$(dirname "$REPO_ROOT")")
SIDECAR_DIR="$HOME/.beads/$REPO_NAME-$SUFFIX"
```

Inform the user:
> "Note: Another repo named `my-app` has a beads sidecar. Using `~/.beads/my-app-work/` for this one (disambiguated by parent directory)."

#### Initialize if new

If `$SIDECAR_DIR/.beads/` does not exist:

```bash
if [ ! -d "$SIDECAR_DIR/.beads" ]; then
  mkdir -p "$SIDECAR_DIR"
  if cd "$SIDECAR_DIR" && bd init -p "$REPO_NAME" -q; then
    # Write the repo path marker for future collision detection
    echo "$REPO_ROOT" > "$SIDECAR_DIR/.beads-repo-path"
  else
    echo "Error: failed to initialize beads sidecar at '$SIDECAR_DIR'." >&2
    # Do not proceed to resolve BD_DB if initialization failed
    return 1  # Intended for use inside a shell function or script
  fi
fi
```

Inform the user:
> "Initialized beads sidecar at `~/.beads/my-app/`."

#### Resolve the db path

```bash
BD_DB=$(ls "$SIDECAR_DIR/.beads/"*.db | head -1)
```

Store `$BD_DB` for the session — use it in every `bd --db "$BD_DB" ...` call.

---

## Running Commands

**Always pass `--db "$BD_DB"` to every `bd` invocation.** This ensures commands target the correct database without changing the working directory.

```bash
bd --db "$BD_DB" <command> [flags]
```

### Session Start

At the start of a session, call `bd prime` to load the beads workflow context:

```bash
bd --db "$BD_DB" prime
```

This outputs AI-optimized workflow instructions. Read and follow them.

---

## Core Workflows

### Show Ready Tasks (Unblocked Work)

```bash
bd --db "$BD_DB" ready --json
```

Lists open tasks with no active blockers. Use `--json` for structured output.
Present as a table: ID, title, priority.

### List All Tasks

```bash
bd --db "$BD_DB" list --json
```

### Create a Task

```bash
bd --db "$BD_DB" create "Task title"
bd --db "$BD_DB" create "Task title" -p 1             # with priority (0 = highest)
bd --db "$BD_DB" create "Task title" -d "Description" # with description
```

For quick capture (returns only the ID — useful for scripting):

```bash
bd --db "$BD_DB" q "Task title"
```

### View Task Details

```bash
bd --db "$BD_DB" show bd-a1b2 --json
```

### Claim a Task (Atomic)

Atomically sets assignee + marks in-progress:

```bash
bd --db "$BD_DB" update bd-a1b2 --claim
```

### Update Status

```bash
bd --db "$BD_DB" update bd-a1b2 --status done
bd --db "$BD_DB" update bd-a1b2 --status in_progress
bd --db "$BD_DB" update bd-a1b2 --status open
```

### Close a Task

```bash
bd --db "$BD_DB" close bd-a1b2
```

### Reopen a Task

```bash
bd --db "$BD_DB" reopen bd-a1b2
```

### Add Dependencies

```bash
# child-id is blocked by parent-id
bd --db "$BD_DB" dep add bd-a1b2 bd-c3d4
```

### Search

```bash
bd --db "$BD_DB" search "auth" --json
```

### Show Database Location

```bash
bd --db "$BD_DB" where
```

---

## Output Formatting

Use `--json` for all listing commands. When presenting to the user, format as a markdown table:

```markdown
| ID | Title | Priority | Status |
|----|-------|----------|--------|
| bd-a1b2 | Implement auth flow | 1 | open |
| bd-c3d4 | Write tests | 2 | in_progress |
```

For `bd ready`, note that these are unblocked and immediately actionable.

---

## Write Operations

All state-modifying operations (create, update, close, dep add) execute directly — no confirmation needed.

**Destructive operations require confirmation before execution:**

| Command | What it does |
|---------|-------------|
| `bd delete bd-a1b2` | Permanently deletes a task |
| `bd gc` | Decays old issues, compacts Dolt commits, runs Dolt GC |
| `bd purge` | Deletes closed ephemeral tasks |
| `bd compact` | Squashes old Dolt commits |

For any of the above, use `AskUserQuestion` to confirm before running.

---

## Setup (One-Time, Optional)

To integrate beads workflow instructions into the repo's `CLAUDE.md`:

```bash
# From within the repo root
bd --db "$BD_DB" setup claude --stealth
```

This writes beads workflow reminders into the project's Claude configuration without committing beads data to the repo.

---

## Error Handling

**`bd: command not found`** → see Prerequisites.

**Dolt connection issues** → bd manages the Dolt server automatically, but if something is wrong:
```bash
bd --db "$BD_DB" dolt status    # check server state
bd --db "$BD_DB" dolt start     # start it explicitly if needed
bd --db "$BD_DB" doctor         # full health check
```

**`bd where` shows wrong location** → verify `$BD_DB` resolves to the expected path.

**`No .db file found in sidecar`** → the sidecar directory exists but `bd init` may not have completed. Re-run:
```bash
cd "$SIDECAR_DIR" && bd init -p "$REPO_NAME"
```

**Two repos with same name** → the collision fallback appends the parent directory. Check `cat ~/.beads/<name>/.beads-repo-path` to see which repo owns which sidecar. A missing marker is treated as an unknown owner — the fallback path will be used rather than risking a collision.

---

## Additional Resources

For all `bd` CLI flags and subcommands, see `references/cli-commands.md`.
For storage mode details and multi-repo patterns, see `references/storage-modes.md`.

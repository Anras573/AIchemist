# Beads Storage Modes

## Overview

The beads skill finds its database once per session with [`tools/beads-db.sh`](../../../tools/beads-db.sh), which prints the `.beads` directory to pass as `bd --db`. The beads-band mod reads through the same script, so both always pick the same database.

The script checks, in order: in-repo, sidecar, legacy sidecar. `--init` creates a sidecar when none of them exists; without it the script never writes anything (exit status 3 means "no database yet").

## Mode 1: In-Repo (repo owns beads)

**When:** `<repo-root>/.beads/` holds an initialized database: `metadata.json` (bd 1.x) or a `.db` file (older bd).

**Storage:** `<repo-root>/.beads/`

**Behavior:** Run all `bd` commands with `--db "$BD_DB"`. `bd` could auto-discover `.beads/` from the repo root, but passing `--db` keeps commands working from any directory and removes any doubt about which database is used. The repo has explicitly opted in to beads, so respect that.

---

## Mode 2: Sidecar (default)

**When:** The repo has no `.beads/` database of its own.

**Storage:** `$AICHEMIST_BEADS_HOME/<repo-name>/`, by default `${XDG_DATA_HOME:-~/.local/share}/aichemist/beads/<repo-name>/`

**Purpose:** Track tasks for any repo without adding beads files to it. Equivalent to beads "Stealth Mode" / "Contributor Mode".

### Sidecar Layout

```
~/.local/share/aichemist/beads/
  my-awesome-repo/           ← primary sidecar
    .beads/                  ← beads data (the path passed to --db)
    .beads-repo-path         ← marker: absolute path of the owning repo
  my-awesome-repo-work/      ← collision fallback (same repo name, parent dir = "work")
    .beads/
    .beads-repo-path
```

The sidecar is initialized with `bd init --skip-agents --skip-hooks --non-interactive`, so bd doesn't write `AGENTS.md`, `CLAUDE.md` or git hooks there.

### Collision Fallback Logic

```
REPO_NAME = basename of git root
SIDECAR   = <sidecar root>/$REPO_NAME

IF sidecar exists AND (.beads-repo-path is missing OR .beads-repo-path != current repo absolute path):
    SUFFIX  = parent directory name of the repo
              e.g. /Users/alice/work/my-awesome-repo → "work"
    SIDECAR = <sidecar root>/$REPO_NAME-$SUFFIX  # e.g. my-awesome-repo-work
```

### Marker File

Written when the sidecar is initialized, to enable collision detection:

```
<sidecar>/.beads-repo-path   ← contains the output of `git rev-parse --show-toplevel`
```

---

## Mode 3: Legacy Sidecar

**When:** No in-repo or new-style sidecar exists, but `~/.beads/<repo-name>/.beads/` does (same collision rules, under `~/.beads`).

**Why it's legacy:** bd 1.x keeps its own state in `~/.beads` (`machine-id`, `eventsData/`, `shared-server/`), refuses to `bd init` inside a `.beads` directory, and stores data in `.beads/embeddeddolt/` instead of a `.db` file. New sidecars are therefore never created there. Existing ones are still used, so no tasks go missing.

---

## Multi-Repo Scenarios

| Scenario | Result |
|----------|--------|
| Single repo `my-app` | `~/.local/share/aichemist/beads/my-app/` |
| Two repos both named `api` in different parent dirs | `…/beads/api/` and `…/beads/api-work/` |
| Repo with its own initialized `.beads/` | In-repo mode, sidecar ignored |
| Sidecar from an older setup under `~/.beads/my-app/` | Legacy mode, until a new sidecar exists |
| Not in a git repo | Use `basename $PWD` as project name |

---

## Switching Modes

If a repo later adopts beads officially (`bd init` run inside the repo), the script detects its `.beads/` and switches to in-repo mode. The sidecar is not deleted, so its tasks stay reachable with `bd --db <sidecar>/.beads`.

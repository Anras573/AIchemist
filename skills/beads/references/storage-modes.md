# Beads Storage Modes

## Overview

The beads skill operates in one of two storage modes, auto-detected on each invocation.

## Mode 1: In-Repo (repo owns beads)

**When:** A `.db` file exists under `.beads/` at the repo root.

**Storage:** `<repo-root>/.beads/`

**How to detect:**
```bash
ls "$(git rev-parse --show-toplevel)/.beads/"*.db 2>/dev/null
```

**Behavior:** Run all `bd` commands with `--db "$BD_DB"` where `BD_DB` is the resolved `.db` path. While `bd` can auto-discover `.beads/` when run from the repo root, always passing `--db "$BD_DB"` is required for consistency — it ensures commands work regardless of the current working directory and removes any ambiguity about which database is being targeted. The repo has explicitly opted in to beads — respect that.

---

## Mode 2: Sidecar (default)

**When:** No `.beads/` in the repo root.

**Storage:** `~/.beads/<repo-name>/`

**Purpose:** Track tasks for any repo without polluting it with beads files. Equivalent to beads "Stealth Mode" / "Contributor Mode".

### Sidecar Path Resolution

```
~/.beads/
  my-awesome-repo/           ← primary sidecar
    .beads/                  ← beads data
    .beads-repo-path         ← marker: absolute path of the owning repo
  my-awesome-repo-work/      ← collision fallback (same repo name, parent dir = "work")
    .beads/
    .beads-repo-path
```

### Collision Fallback Logic

```
REPO_NAME = basename of git root
SIDECAR   = ~/.beads/$REPO_NAME

IF sidecar exists AND (.beads-repo-path is missing OR .beads-repo-path != current repo absolute path):
    SUFFIX  = parent directory name of the repo
              e.g. /Users/alice/work/my-awesome-repo → "work"
    SIDECAR = ~/.beads/$REPO_NAME-$SUFFIX  # e.g. ~/.beads/my-awesome-repo-work
```

### Marker File

Written at sidecar init time to enable collision detection:

```bash
git rev-parse --show-toplevel > ~/.beads/<repo-name>/.beads-repo-path
```

---

## Multi-Repo Scenarios

| Scenario | Result |
|----------|--------|
| Single repo `my-app` | `~/.beads/my-app/` |
| Two repos both named `api` in different orgs | `~/.beads/api/` and `~/.beads/api-other-org/` |
| Repo with `.beads/*.db` already present | In-repo mode, sidecar ignored |
| Not in a git repo | Use `basename $PWD` as project name |

---

## Switching Modes

If a repo later adopts beads officially (`bd init` run inside the repo), the skill will auto-detect the `.db` file under `.beads/` and switch to in-repo mode. The sidecar at `~/.beads/<repo-name>/` is not deleted — tasks there remain accessible by temporarily `cd`-ing to the sidecar directory and running `bd` manually.

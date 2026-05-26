# Hotspot Skill

## Problem

Identifying whether a file is worth refactoring requires two signals: how complex it is, and how often it changes. High complexity in code that's never touched is low risk; high complexity in code that changes every sprint is where bugs cluster. This skill surfaces that intersection — a CodeScene-style hotspot score — both as a standalone refactor-decision aid and as a parallel agent inside the code-review flow.

## Approach

Compute `score = avg_cyclomatic_complexity × git_churn_count` per file, using `lizard` for complexity and a single `git log` call for churn. Keep scoring simple — no LSP coupling, no configurable weights. Deliver as:

1. A standalone `hotspot` skill the user or an agent can invoke directly
2. A `hotspot.agent.md` launched in parallel by the code-review skill, which appends a Risk Context section and promotes hotspot files to review findings

## Design

### Files

```
skills/hotspot/
  SKILL.md

agents/
  hotspot.agent.md

docs/skills.md               — new entry
docs/agents.md               — new Hotspot Agent section
skills/code-review/SKILL.md  — one row added to parallel agent table
```

### Skill (`skills/hotspot/SKILL.md`)

**Trigger phrases:** `/hotspot`, "should I refactor this", "is this a hotspot", "hotspot analysis", "complexity risk", "churn analysis", "is this worth refactoring", "what's the riskiest file", "cyclomatic complexity", "which files are most complex", "what should I refactor first"

**Optional target argument:**
- `/hotspot` — full repo, top 10 by score
- `/hotspot <file>` — single file, function-level breakdown
- `/hotspot <dir>` — directory, file-level ranking

**Workflow (all read-only, runs automatically):**

1. Check `lizard` is installed; fail fast with platform-aware message if not (macOS: `brew install lizard-analyzer`, other: `pip install lizard`)
2. Validate target path using `realpath` + repo root prefix check (trailing slash to avoid sibling-dir matches)
3. Compute churn: single `git log --since="90 days ago" --name-only --format=""` call; parse with first-whitespace split to handle paths containing spaces
4. Compute complexity: `lizard -- "<target>" --csv` (quoted, no `shell=True`)
5. Score: `avg_CCN × churn_count` per file
6. Threshold: top 20% of scanned set; fallback for < 5 files: `score > 2 × median`
7. Present ranked table + function-level drill-down for hotspot files + refactor guidance

### Agent (`agents/hotspot.agent.md`)

**Invoked by:** code-review skill, in parallel with other review agents  
**Model:** haiku (data-gathering task, not reasoning-heavy)  
**Input:** list of changed files passed by the code-review skill

**Workflow:**
1. Single batch `git log` churn call across all input files; first-whitespace split on `uniq -c` output
2. `lizard` complexity scoped to input files
3. Score and threshold against top 20% of input files (not repo-wide)
4. Small-N fallback (< 5 scoreable files):
   - 1 file: flag if `avg_CCN ≥ 10`
   - 2–4 files: flag highest-scoring file if lowest score > 0 AND highest ≥ 3× lowest
5. Return `Risk Context` block (always) and `HOTSPOT_FINDING` entries (one per file exceeding threshold)

**Dynamic confidence:**
- Top 10% of input files → confidence 90 (Blocker)
- Top 10–20% → confidence 85 (Warning)

**If lizard is unavailable:** return bare `HOTSPOT_SKIPPED` token — the calling skill owns the user-facing install message.

### Code-review integration

One row added to the "Core Agents" table in `skills/code-review/SKILL.md`:

> Hotspot Agent | haiku | Complexity risk | Run `agents/hotspot.agent.md` on the changed files. Append returned Risk Context block to review output. Merge any `HOTSPOT_FINDING` entries into the findings list (confidence 90 → Blocker, confidence 85 → Warning). If `HOTSPOT_SKIPPED` is returned, add to Review Stats: "Hotspot analysis skipped — lizard not installed (macOS: `brew install lizard-analyzer`, other: `pip install lizard`)."

### Data flow

```
Standalone (/hotspot [target])
  validate target (realpath + repo root check)
  git log → churn_count per file  (single call, first-ws split)
  lizard  → avg_CCN per file      (quoted args, no shell=True)
  score   = avg_CCN × churn_count
  threshold = top 20% of scanned set
  output: ranked table + drill-down + refactor guidance

Code-review integration
  code-review skill passes changed files to Hotspot Agent
  Agent: git log + lizard scoped to changed files
  Agent returns: Risk Context block + HOTSPOT_FINDING entries
  code-review skill: appends Risk Context, merges findings
```

## Error Handling

| Situation | Behavior |
|---|---|
| `lizard` not installed (standalone) | Fail fast with platform-aware message |
| `lizard` not installed (agent) | Return bare `HOTSPOT_SKIPPED` token; skill owns error message |
| Target outside repo root | Fail: "Error: target must be within the repository" |
| Target not found | Fail: "Path not found: `<target>`" |
| No git history for target | Warn: churn = 0, proceed with complexity-only output |
| 0 commits in 90-day window | Warn: "No commits in the last 90 days — churn scores are 0." |
| Unsupported file types | Note "X files skipped (unsupported language)" — do not fail |
| Symlinked target | Passes repo root check — document limitation; no fix |

## Testing

| Test | How |
|---|---|
| Standalone on a file | `/hotspot src/some-file.ts` — verify table, CCN + churn columns present |
| Standalone on a dir | `/hotspot src/` — verify top-10 ranking, hotspot flags on high scorers |
| Standalone no args | `/hotspot` — verify full repo scan |
| Code-review integration (Risk Context) | PR touching a known-complex file — verify Risk Context section in output |
| Code-review integration (finding) | PR touching a confirmed hotspot — verify HOTSPOT_FINDING appears |
| `lizard` missing | Uninstall lizard, run `/hotspot` — verify error message, not stack trace |
| Agent missing lizard | Remove lizard, run `/code-review` — verify review completes, hotspot skipped note present |
| No git history in window | Freshly-added file — verify churn=0 warning appears |
| Path with spaces | Target containing spaces — verify uniq-c parse correct |
| Sibling directory | `/hotspot ../sibling-repo` — verify "must be within the repository" error |

## Out of Scope

- Configurable scoring weights per repo
- LSP coupling signals (fan-out, inbound references)
- Historical trend tracking (score over time)
- CI pipeline integration
- Class or method-level churn (git churn is file-level only)

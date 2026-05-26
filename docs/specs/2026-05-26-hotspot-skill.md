# Hotspot Skill

## Problem

Identifying whether a file, class, or method is worth refactoring requires two signals at once: how complex it is, and how often it changes. High complexity in code that's never touched is low risk; high complexity in code that changes every sprint is where bugs cluster. This skill surfaces that intersection — a CodeScene-style hotspot score — both as a standalone refactor-decision aid and as an enrichment layer inside the existing code-review flow.

## Approach

Compute `score = avg_cyclomatic_complexity × git_churn_count` per file, using `lizard` for complexity and `git log` for churn. Keep scoring simple (no LSP coupling, no configurable weights). Deliver as:

1. A standalone `hotspot` skill the user or an agent can invoke directly
2. A `hotspot.agent.md` launched in parallel by the code-review skill, which appends a Risk Context section and can return hotspot files as confidence-85 findings

## Design

### Files

```
skills/hotspot/
  SKILL.md

agents/
  hotspot.agent.md

docs/skills.md          — new entry
skills/code-review/SKILL.md — one-line addition to parallel agent table
```

### Skill (`skills/hotspot/SKILL.md`)

**Trigger phrases:** `/hotspot`, "should I refactor this", "is this a hotspot", "hotspot analysis", "complexity risk", "churn analysis"

**Optional target argument:**
- `/hotspot` — full repo, top 10 by score
- `/hotspot <file>` — single file, function-level breakdown
- `/hotspot <dir>` — directory, file-level ranking

**Workflow (all read-only, runs automatically):**

1. Compute churn per file:
   ```bash
   git log --follow --format="%H" --since=90.days -- <target> | wc -l
   ```
2. Compute cyclomatic complexity per file:
   ```bash
   lizard <target> --csv
   ```
3. Score: `avg_CCN × churn_count` per file
4. Rank; flag files in top 20% of repo score distribution as hotspots
5. Present ranked table with columns: File, Avg CCN, Churn (90d), Score, Flag

**Output format:**

```
## Hotspot Analysis

| File | Avg CCN | Churn (90d) | Score | |
|------|---------|-------------|-------|-|
| src/services/OrderService.ts | 12.4 | 34 | 421 | 🔥 Hotspot |
| src/utils/validation.ts      |  4.1 |  8 |  33 |            |

Top 20% threshold: score ≥ 200

### Drill-down: src/services/OrderService.ts
| Function | CCN | Line |
|----------|-----|------|
| processOrder | 18 | 42 |
| validateCart | 14 | 98 |
```

### Agent (`agents/hotspot.agent.md`)

**Invoked by:** code-review skill, in parallel with other review agents

**Input:** list of changed files (passed by code-review skill)

**Workflow:**
1. Same git log + lizard computation, scoped to changed files only
2. Compare each file's score against the repo-wide top-20% threshold
3. Return:
   - **Risk Context block** — always appended to review output
   - **Hotspot findings** — one finding per file that exceeds threshold, confidence 85

**Risk Context block format:**

```
## Risk Context

| File | Avg CCN | Churn (90d) | Score | Risk |
|------|---------|-------------|-------|------|
| src/services/OrderService.ts | 12.4 | 34 | 421 | 🔥 High |
| src/utils/validation.ts      |  4.1 |  8 |  33 | ✅ Low  |
```

**Hotspot finding format (when threshold exceeded):**

```
File: src/services/OrderService.ts
Issue: This file is a confirmed hotspot (score 421, top 20% of repo).
       Changes here carry elevated defect risk — consider breaking up
       processOrder (CCN 18) before extending it further.
Confidence: 85
```

### Code-review integration

Add one row to the "Core Agents" table in `skills/code-review/SKILL.md`:

| Agent | Model | Focus | Additional Instructions |
|-------|-------|-------|------------------------|
| Hotspot Agent | haiku | Complexity risk | Run `hotspot.agent.md` on changed files. Return Risk Context block and any hotspot findings. |

`haiku` is appropriate — this is a data-gathering task, not reasoning-heavy analysis.

### Scoring

| Score | Label | Action |
|---|---|---|
| Top 20% of repo | Hotspot | 🔥 flag in output |
| Top 20% AND in diff | Hotspot finding | Confidence-85 finding in code-review |
| Below threshold | Healthy | Listed, no flag |

### Data flow

```
Standalone (/hotspot [target])
  git log → churn_count per file
  lizard  → avg_CCN per file
  score   = avg_CCN × churn_count
  rank → table output

Code-review integration
  code-review skill passes changed files to Hotspot Agent
  Agent: git log + lizard scoped to changed files
  Agent returns: Risk Context block + hotspot findings
  code-review skill: appends Risk Context, merges findings
```

## Error Handling

| Situation | Behavior |
|---|---|
| `lizard` not installed | Fail fast: "Hotspot analysis requires `lizard`. Install with `pip install lizard`." |
| Target file/dir doesn't exist | Fail fast with clear path error |
| No git history for target | Warn: "No git history found for `<target>` — churn score will be 0. Results may be incomplete." |
| 0 commits in 90-day window | Warn and show complexity-only table; churn = 0 |
| Agent called but lizard missing | Return degraded output: "Hotspot analysis skipped — `lizard` not installed." Code-review continues. |
| Unsupported file types | Note "X files skipped (unsupported language)" — do not fail |

The code-review skill must never fail because the hotspot agent fails.

## Testing

| Test | How |
|---|---|
| Standalone on a file | `/hotspot src/some-file.ts` — verify table, CCN + churn columns present |
| Standalone on a dir | `/hotspot src/` — verify top-10 ranking, hotspot flags on high scorers |
| Standalone no args | `/hotspot` — verify full repo scan |
| Code-review integration (Risk Context) | PR touching a known-complex file — verify Risk Context section in output |
| Code-review integration (finding) | PR touching a confirmed hotspot — verify confidence-85 finding appears |
| `lizard` missing | Uninstall lizard, run `/hotspot` — verify error message, not stack trace |
| Agent missing lizard | Remove lizard, run `/code-review` — verify review completes, hotspot skipped note present |
| No git history in window | Freshly-added file — verify churn=0 warning appears |

## Out of Scope

- Configurable scoring weights per repo
- LSP coupling signals (fan-out, inbound references)
- Historical trend tracking (score over time)
- CI pipeline integration
- Class or method-level churn (git churn is file-level only)

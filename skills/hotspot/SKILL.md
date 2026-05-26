---
name: hotspot
description: |
  Trigger this skill when the user asks about code complexity, refactoring candidates, or risk areas. Exact trigger phrases: "/hotspot", "should I refactor this", "is this a hotspot", "hotspot analysis", "complexity risk", "churn analysis", "is this worth refactoring", "what's the riskiest file", "cyclomatic complexity", "which files are most complex", "what should I refactor first".
version: 1.0.0
---

# Hotspot Skill

Identifies high-risk code by combining cyclomatic complexity (via `lizard`) with git churn. Files that are both complex and frequently changed are hotspots — the intersection where bugs cluster.

Score formula: `avg_cyclomatic_complexity × git_churn_count (90 days)`

## Read vs Write Operations

| Type | Operations | Behavior |
|------|------------|----------|
| **Read** | git log, lizard analysis, file reads | Automatic — no confirmation needed |

## Usage

```
/hotspot                    — full repo, top 10 by score
/hotspot <file>             — single file, function-level breakdown
/hotspot <dir>              — directory, file-level ranking
```

## Workflow

### Step 1 — Check lizard is installed

```bash
lizard --version 2>/dev/null
```

If not found, fail fast with a platform-aware message:

```bash
if [[ "$(uname)" == "Darwin" ]]; then
  echo "Hotspot analysis requires lizard. Install with: brew install lizard-analyzer"
else
  echo "Hotspot analysis requires lizard. Install with: pip install lizard"
fi
```

Do not proceed.

### Step 2 — Determine target

- If argument provided: use it as the target path
- If no argument: use the repo root (`.`)

Verify the target exists. If not, fail with: "Path not found: `<target>`"

### Step 3 — Compute churn per file

```bash
# For each file in target, count commits in the last 90 days
git log --since="90 days ago" --name-only --format="" -- <target> \
  | grep -v '^$' \
  | sort | uniq -c \
  | sort -rn
```

This produces `churn_count` per file path.

### Step 4 — Compute cyclomatic complexity

```bash
lizard <target> --csv
```

Parse CSV output. Fields used:
- `CCN` — cyclomatic complexity number per function
- `file_name` — join key with churn data
- `function_name`, `line` — for function-level drill-down

Compute `avg_CCN` per file by averaging CCN across all functions in that file.

### Step 5 — Score and rank

For each file with both churn and complexity data:

```
score = avg_CCN × churn_count
```

Files with churn data but no lizard output (unsupported language): note count, exclude from ranking.

Files with lizard output but 0 churn: include with score = avg_CCN × 0 = 0.

Determine hotspot threshold: top 20% of scores in the scanned set. If fewer than 5 files have scores, flag files where `score > 2 × median` instead.

### Step 6 — Present output

**File-level table** (always shown):

```markdown
## Hotspot Analysis

Scanned: <N> files | Window: 90 days | Hotspot threshold (top 20%): score ≥ <X>

| File | Avg CCN | Churn (90d) | Score |    |
|------|---------|-------------|-------|----|
| src/services/OrderService.ts | 12.4 | 34 | 421 | 🔥 |
| src/utils/validation.ts      |  4.1 |  8 |  33 |    |

_X files skipped (unsupported language)_  ← only if applicable
_No commits in the last 90 days — churn scores are 0._  ← only if applicable
```

**Function-level drill-down** (shown when target is a single file, or when any hotspot file is in the result):

```markdown
### src/services/OrderService.ts (score: 421 🔥)

| Function | CCN | Line |
|----------|-----|------|
| processOrder | 18 | 42 |
| validateCart | 14 | 98 |
| applyDiscounts | 8 | 134 |
```

**Refactor guidance** (shown for each hotspot file):

> `processOrder` (CCN 18, line 42) — high complexity in a frequently-changed file. Consider extracting sub-steps into named functions to reduce branch depth before the next change.

## Error Handling

| Situation | Behavior |
|-----------|----------|
| `lizard` not installed | Fail fast with platform-aware install instruction (see Step 1) |
| Target not found | Fail fast: "Path not found: `<target>`" |
| No git history for target | Warn: "No git history found for `<target>` — churn scores will be 0. Results may be incomplete." Proceed with complexity-only output. |
| 0 commits in 90-day window | Warn: "No commits in the last 90 days — churn scores are 0." Show complexity table with churn = 0. |
| Unsupported file types | Note "X files skipped (unsupported language)" — do not fail |
| Empty target (no files) | Report: "No files found at `<target>`" |

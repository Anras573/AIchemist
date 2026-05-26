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

Verify the target exists and resolves within the repo root:

```bash
repo_root=$(git rev-parse --show-toplevel)

# Check existence before resolving, so missing paths produce the right error.
[[ ! -e "<target>" ]] && echo "Path not found: \`<target>\`" && exit 1

# Resolve symlinks for an accurate prefix check. Prefer realpath (GNU coreutils);
# fall back to python3. If neither is available, fail fast with install guidance.
if command -v realpath >/dev/null 2>&1; then
  _resolve() { realpath "$1"; }
elif command -v python3 >/dev/null 2>&1; then
  _resolve() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
else
  echo "Error: /hotspot requires either realpath or python3 to validate paths."
  echo "macOS: install coreutils via Homebrew (brew install coreutils) or Xcode Command Line Tools."
  exit 1
fi

target_real=$(_resolve "<target>")
repo_root=$(_resolve "$repo_root")

# The trailing slash prevents matching sibling directories with a common prefix.
# Symlinks are resolved above, so a symlink pointing outside the repo correctly fails.
[[ "$target_real" != "$repo_root/"* && "$target_real" != "$repo_root" ]] && echo "Error: target must be within the repository" && exit 1

# Derive a repo-relative path for git pathspecs (git resolves paths relative to
# the repo root; absolute paths produce zero matches). Use the absolute path for
# lizard, which accepts and prefers absolute paths.
target_rel="${target_real#$repo_root/}"
```

### Step 3 — Compute churn per file

```bash
# For each file in target, count commits in the last 90 days.
# Use the repo-relative path — git pathspecs are relative to the repo root.
git log --since="90 days ago" --name-only --format="" -- "$target_rel" \
  | grep -v '^$' \
  | sort | uniq -c \
  | sort -rn
```

This produces `churn_count` per file path. When parsing `uniq -c` output, split on the **first** whitespace only (count is the leftmost token; the remainder is the full path, which may contain spaces). Do not split on all whitespace.

### Step 4 — Compute cyclomatic complexity

```bash
lizard --csv -- "$target_real"
```

Place `--csv` before `--` so it is parsed as an option flag, not a filename. Always pass the path as a separate quoted argument after `--` and invoke `lizard` without `shell=True` (or its equivalent in any subprocess API) to prevent shell injection.

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

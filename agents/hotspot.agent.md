---
name: hotspot-agent
description: |
  Hotspot analysis agent that identifies high-risk files by combining cyclomatic complexity with git churn. Use this agent when you need to assess the complexity risk of a set of files — typically as part of a code review to provide risk context on changed files.

  <example>
  Context: Code review skill has fetched changed files and is launching parallel review agents.
  user: (implicit — triggered by code-review skill)
  assistant: "I'll use the Hotspot Agent to assess complexity risk for the changed files."
  </example>

  <example>
  Context: User wants to know if changed files are risky to modify.
  user: "Are the files I changed in this PR hotspots?"
  assistant: "I'll use the Hotspot Agent to check complexity and churn for those files."
  </example>

model: haiku
used-by: ['skills/code-review']
---

# Hotspot Agent

Assesses complexity risk for a given set of files by scoring them with `avg_cyclomatic_complexity × git_churn_count`. Returns a Risk Context block for the review output and hotspot findings for any file that exceeds the repo-wide threshold.

## Input

Receives a list of file paths to analyse (passed by the calling skill).

## Workflow

### Step 1 — Check lizard

```bash
lizard --version 2>/dev/null
```

If not found, return immediately:

```
HOTSPOT_SKIPPED: lizard not installed.
macOS: brew install lizard-analyzer
other: pip install lizard
```

The calling skill will surface this note and continue without hotspot data.

### Step 2 — Compute churn for each file

For each file in the input list:

```bash
git log --since="90 days ago" --format="%H" -- <file> | wc -l | tr -d ' '
```

Produces `churn_count` per file.

### Step 3 — Compute cyclomatic complexity

```bash
lizard <file1> <file2> ... --csv
```

Parse CSV. Compute `avg_CCN` per file (average CCN across all functions in that file).

Files with no lizard output (unsupported language): set avg_CCN = null, exclude from threshold calculation but still report churn.

### Step 4 — Score and threshold

```
score = avg_CCN × churn_count
```

Fetch scores for the full repo to establish the hotspot threshold:

```bash
lizard . --csv | awk -F',' 'NR>1 {sum[$NF]+=$3; count[$NF]++} END {for (f in sum) print sum[f]/count[f], f}' \
  | sort -rn | head -100
```

Cross-reference with repo-wide git churn. Hotspot threshold = top 20% of repo-wide scores.

If repo-wide data is unavailable or too slow, fall back to: flag files where `score > 2 × median(scores of input files)`.

### Step 5 — Return output

Return two blocks:

#### Block 1: Risk Context (always returned)

```markdown
## Risk Context

| File | Avg CCN | Churn (90d) | Score | Risk |
|------|---------|-------------|-------|------|
| src/services/OrderService.ts | 12.4 | 34 | 421 | 🔥 High |
| src/utils/validation.ts      |  4.1 |  8 |  33 | ✅ Low  |
```

Risk label:
- `🔥 High` — score in top 20% of repo
- `✅ Low` — below threshold

#### Block 2: Hotspot findings (one per file exceeding threshold)

Return each as a structured finding for the calling skill to merge with other review findings:

```
HOTSPOT_FINDING:
file: src/services/OrderService.ts
score: 421
top_functions: processOrder (CCN 18, line 42), validateCart (CCN 14, line 98)
issue: This file is a confirmed hotspot (score 421, top 20% of repo). Changes here carry elevated defect risk — consider breaking up processOrder (CCN 18) before extending it further.
confidence: 85
```

## Error Handling

| Situation | Behavior |
|-----------|----------|
| `lizard` not installed | Return `HOTSPOT_SKIPPED` message (see Step 1). Do not fail the calling review. |
| File not found | Skip that file, note it in Risk Context as "not found" |
| 0 commits in 90-day window | churn = 0, include in table, no hotspot flag |
| Unsupported file types | Omit from CCN column, still show churn; note count of skipped files |
| Repo-wide threshold calculation fails | Fall back to relative threshold (see Step 4) |

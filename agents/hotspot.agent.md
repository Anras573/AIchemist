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

Assesses complexity risk for a given set of files by scoring them with `avg_cyclomatic_complexity × git_churn_count`. Returns a Risk Context block for the review output and hotspot findings for any file that exceeds the threshold.

Assumes `lizard` is installed — the calling skill gates on this before invoking the agent.

## Input

Receives a list of file paths to analyse (passed by the calling skill).

## Workflow

### Step 1 — Compute churn for all input files (single git call)

```bash
git log --since="90 days ago" --name-only --format="" -- <file1> <file2> ... \
  | grep -v '^$' \
  | sort | uniq -c
```

Filter the output to only files present in the input list. This gives `churn_count` per file in one process.

### Step 2 — Compute cyclomatic complexity

```bash
lizard <file1> <file2> ... --csv
```

Parse CSV. Compute `avg_CCN` per file (average CCN across all functions in that file).

Files with no lizard output (unsupported language): set avg_CCN = null, exclude from threshold calculation but still show churn.

### Step 3 — Score and threshold

```
score = avg_CCN × churn_count
```

Threshold = top 20% of scores among the input files. If fewer than 5 files have scores, flag files where `score > 2 × median(scores of input files)` instead.

### Step 4 — Return output

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
- `🔥 High` — score in top 20% of input files
- `✅ Low` — below threshold

#### Block 2: Hotspot findings (one per file exceeding threshold)

Confidence is dynamic based on how far the score exceeds the threshold:
- Score in top 10% of input files → confidence 90 (Blocker)
- Score in top 10–20% → confidence 85 (Warning)

```
HOTSPOT_FINDING:
file: src/services/OrderService.ts
score: 421
top_functions: processOrder (CCN 18, line 42), validateCart (CCN 14, line 98)
issue: This file is a confirmed hotspot (score 421, top 20% of changed files). Changes here carry elevated defect risk — consider breaking up processOrder (CCN 18) before extending it further.
confidence: 90
```

If `lizard` is not installed (the calling skill should have caught this, but as a safeguard):

```
HOTSPOT_SKIPPED
```

Return only this token — no install instructions. The calling skill owns the user-facing error message.

## Error Handling

| Situation | Behavior |
|-----------|----------|
| `lizard` not installed | Return `HOTSPOT_SKIPPED` (bare token only). Do not fail the calling review. |
| File not found | Skip that file, note it in Risk Context as "not found" |
| 0 commits in 90-day window | churn = 0, include in table, no hotspot flag |
| Unsupported file types | Omit from CCN column, still show churn; note count of skipped files |
| Fewer than 5 scoreable files | Use 2× median threshold instead of top-20% percentile |

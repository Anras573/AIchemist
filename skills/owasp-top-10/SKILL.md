---
name: owasp-top-10
description: |
  Trigger this skill when the user asks about the OWASP Top 10, wants a security review scoped to it, or asks whether code is compliant with it. Exact trigger phrases: "OWASP top 10", "owasp top ten", "check against owasp top 10", "review for owasp vulnerabilities", "what's the current owasp top 10", "latest owasp top 10", "owasp compliance check", "is this owasp compliant", "security review owasp".
version: 1.0.0
---

# OWASP Top 10 Skill

Answers questions about the OWASP Top 10 and reviews code against it, always using a **live fetch** from owasp.org rather than a list baked into this file. The Top 10 is revised every few years (2013, 2017, 2021, 2025) — hardcoding the categories here would silently go stale the next time OWASP publishes a new edition. Fetching on every invocation means this skill never needs to be updated when that happens.

## Read vs Write Operations

| Type | Operations | Behavior |
|------|------------|----------|
| **Read** | `WebFetch` against owasp.org | Automatic — no confirmation needed |

No write operations. This skill only reads from owasp.org and reports findings; it never edits files on its own beyond what a code-review workflow it feeds into would already do.

## Workflow

### Step 1 — Discover the current edition

Fetch the project landing page:

```
WebFetch(url: "https://owasp.org/www-project-top-ten/", prompt: "What is the most recent OWASP Top 10 edition year stated on this page, and what is the URL of that edition's page?")
```

Extract the edition year (e.g. `2025`) and its page URL (pattern: `https://owasp.org/Top10/<year>/`). This step exists specifically so a future edition is picked up automatically — never assume the year from training knowledge or from a previous run in this conversation.

If the landing page's structure has changed enough that no clear "most recent edition" statement or link can be found, say so explicitly and ask the user to confirm the current edition's URL rather than guessing.

### Step 2 — Fetch the ranked category list

```
WebFetch(url: "https://owasp.org/Top10/<year>/", prompt: "List the 10 OWASP Top 10 categories in rank order with their ID (e.g. A01:<year>), title, and the link to each category's detail page.")
```

This returns rank, ID, title, and a relative link per category (e.g. `A01_<year>-Broken_Access_Control/`). Resolve relative links against `https://owasp.org/Top10/<year>/`.

### Step 3 — Present or drill in, depending on the request

**"What's the current OWASP Top 10?"** — present the ranked table from Step 2 as-is:

```markdown
## OWASP Top 10:<year>

| Rank | ID | Title |
|------|----|----|
| 1 | A01:<year> | Broken Access Control |
| ... | ... | ... |

Source: https://owasp.org/Top10/<year>/
```

**"Review this code/PR against the OWASP Top 10"** — for each category plausibly relevant to the code under review (skip categories that clearly don't apply, e.g. skip Software Supply Chain Failures for a change with no dependency edits), fetch that category's detail page for prevention guidance:

```
WebFetch(url: "<category detail URL from Step 2>", prompt: "Summarize the description, how to prevent this risk, and any example attack scenarios.")
```

Cross-reference the "how to prevent" guidance against the code/diff being reviewed. Report findings grouped by category ID, each with the relevant OWASP guidance line and the specific code location it maps to.

### Step 4 — Cite the source and freshness

Always cite the edition and URL fetched (e.g. "per OWASP Top 10:2025, https://owasp.org/Top10/2025/"). Never present the list without attribution — the whole point of fetching live is that the reader can trust it's current, and that only holds if the source is visible.

## Error Handling

| Situation | Behavior |
|-----------|----------|
| `WebFetch` to the landing page fails (network/timeout) | Report the fetch failure plainly. Do **not** fall back to a hardcoded or training-data list presented as current — offer to retry, or ask the user for a URL. |
| Landing page structure changed, edition unclear | Say what was found and ask the user to confirm the current edition's URL. |
| Category detail page fetch fails during a code review | Note that category's guidance is unavailable and continue with the remaining categories rather than aborting the whole review. |

## Integration with Other Skills

This skill supplies live OWASP Top 10 data; it doesn't scan code itself. When a request needs both, pair it with:

- **`security-review`** — for a full security pass on pending changes, use this skill to fetch current category definitions and prevention guidance, then apply `security-review` for the actual scan.
- **`code-review`** — the security review agent within `code-review` can consult this skill's fetched categories as ground truth when flagging findings, instead of relying on its own training knowledge of the Top 10.

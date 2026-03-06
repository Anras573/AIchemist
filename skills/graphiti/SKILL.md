---
name: Graphiti Graph Memory
description: |
  This skill should be used to interact with the Graphiti knowledge graph memory. Use it when the user says "remember this", "store in memory", "what do you know about X", "search memory", "forget this", or "clear memory". Also activates automatically to store and retrieve context during tasks — see Auto-Trigger Behaviour below.
version: 1.0.0
---

# Graphiti Graph Memory Skill

Graphiti is a persistent knowledge graph memory for AI agents. Information is stored as **episodes** (raw content), automatically decomposed into **nodes** (entities) and **facts** (relationships between entities). All data is namespaced by `group_id`.

For the full tool reference, see `references/tools.md`.

---

## Two-Layer Memory Architecture

Every operation must target the correct `group_id` layer:

| Layer | `group_id` | Stores |
|------|------|------|
| **Global** | `aichemist` | User preferences, recurring patterns, personal conventions, cross-project decisions |
| **Project** | `<repo-name>` | Codebase-specific knowledge, architectural decisions, discovered patterns, file locations |

### Resolving the Project `group_id`

When working inside a git repository, derive the repo name:

```bash
basename $(git rev-parse --show-toplevel)
```

If not in a git repo, fall back to `aichemist` (global layer only).

### Which Layer to Use

**Store in `aichemist` (global) when the information is:**
- A user preference (tool choices, code style, communication style)
- A recurring pattern observed across multiple projects
- A personal convention the user has stated explicitly
- A correction the user made to the agent's behaviour

**Store in `<repo-name>` (project) when the information is:**
- An architectural decision specific to this codebase
- A discovered pattern or convention in this repo
- A file location or module responsibility
- A technology choice or dependency rationale
- A known quirk or gotcha in this codebase

**Search both layers** when fetching context at the start of a task.

---

## Auto-Trigger Behaviour

### Auto-Fetch (search before acting)

Search both `aichemist` and `<repo-name>` layers automatically when:

- **Starting any non-trivial task** — before implementing a feature, fixing a bug, or refactoring, search for relevant prior decisions and preferences
- **About to make a recommendation** — before suggesting a library, pattern, or approach, check if the user has a stored preference
- **Encountering an unfamiliar file or module** — search for stored context about its responsibility or quirks
- **Discussing a technology, tool, or concept** — search for stored opinions or prior decisions involving it
- **Seeing an error or bug** — search for stored notes about similar issues or known gotchas
- **User asks "what do you know about X"** — always search before answering

When results are found, silently incorporate them into your reasoning. Only surface them explicitly if they materially affect the response.

### Auto-Store (save without asking)

Add to memory automatically — without confirmation — when any of the following is observed:

- **User states a preference** — any phrase like "I prefer", "I always use", "I never want", "I like", "use X not Y"
- **User corrects the agent** — any correction is a signal worth persisting so the same mistake does not recur
- **An architectural decision is made** — technology choices, design patterns adopted, approaches explicitly rejected
- **A codebase discovery is made** — file responsibilities, module boundaries, non-obvious conventions, known quirks
- **A task is completed that revealed something new** — e.g. a bug fix that exposed a pattern, a refactor that clarified structure
- **User explicitly says "remember this"** — store immediately, no confirmation
- **A new convention is established** — any time the user and agent agree on "we do it this way"

Apply the **two-layer rule** automatically: personal preferences and corrections go to `aichemist`; code, architecture, and codebase discoveries go to `<repo-name>`.

When auto-storing, keep the episode name descriptive and the body concise. Do not store trivial or ephemeral facts (e.g. what file was open, what command was run).

---

## Core Workflows

### Searching Memory

Always search both layers for relevant context:

```
1. search_nodes(query, group_ids=["aichemist", "<repo-name>"])
2. search_memory_facts(query, group_ids=["aichemist", "<repo-name>"])
3. Synthesise results — prefer project-layer facts for code decisions,
   global-layer facts for preferences and style
```

Present results clearly: what was found, which layer it came from, when it was stored.

### Storing a Memory

**Auto-store triggers** (see Auto-Trigger Behaviour): call `add_memory` directly — no confirmation needed.

**Explicit user request** (e.g. "store this", "save this to memory"): use `AskUserQuestion` before calling `add_memory`:

```
Question: "Store this in memory?"
Show: the name, content summary, target group_id, and source type
Options:
  - "Yes, store it" — proceed
  - "Store in global layer instead" / "Store in project layer instead" — adjust group_id
  - "Cancel" — abort
```

### Deleting an Episode or Fact (Confirmation Required)

Before calling `delete_episode` or `delete_entity_edge`:

```
Question: "Delete this from memory?"
Show: the name/UUID and group_id it belongs to
Options:
  - "Yes, delete it" — proceed
  - "Cancel" — abort
```

### Clearing a Group (Strong Confirmation Required)

`clear_graph` is irreversible. Always:

1. Fetch and show the user a sample of what will be lost (`get_episodes`)
2. Explicitly name the `group_id`(s) being cleared
3. Use `AskUserQuestion`:

```
Question: "This will permanently delete all memory in '<group_id>'. Are you sure?"
Options:
  - "Yes, clear it permanently" — proceed
  - "Cancel" — abort
```

Never call `clear_graph` without an explicit user request.

---

## Write Operation Confirmation Pattern

For all write operations **initiated by an explicit user request** (i.e. not auto-store triggers):

1. **Prepare** — determine the right layer, source type, and episode name
2. **Preview** — show the user what will be stored/deleted
3. **Confirm** — use `AskUserQuestion`
4. **Execute** — only if confirmed
5. **Report** — confirm success or explain failure

---

## Error Handling

**Server unreachable:** Call `graphiti/get_status` to diagnose. Remind user the Docker container must be running and `GRAPHITI_MCP_URL` must be set.

**Empty search results:** Broaden the query or remove `group_ids` filter. Mention that the graph may not have relevant data yet.

**Add memory returns error:** Check that `episode_body` is a valid JSON string when `source='json'`. For other sources, verify the content is non-empty.

**UUID not found:** The episode or edge may have already been deleted. Search for it first to confirm.

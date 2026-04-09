---
name: MemPalace Memory
description: |
  Use this skill to interact with the MemPalace memory system. Activates when the user says "remember this", "store in memory", "what do you know about X", "search memory", "forget this", or "clear memory". Also auto-triggers to store and retrieve context during tasks — see Auto-Trigger Behavior below.
version: 1.0.0
---

# MemPalace Memory Skill

MemPalace is a persistent local memory system backed by ChromaDB (vector search) and a SQLite knowledge graph. Content is stored in **drawers**, organised into **rooms** (topics) within **wings** (domains).

For the full tool reference, see `references/tools.md`.

---

## Wing/Room Architecture

Memory is organised spatially — wings are broad domains, rooms are specific topics within them.

| Wing | Purpose |
|------|---------|
| `wing_user` | User preferences, corrections, personal conventions |
| `wing_code` | Codebase-specific discoveries, architectural decisions |
| `wing_agent` | Agent observations and diary entries |
| `wing_team` | Team and project context |

### Naming conventions

- **Wings**: `wing_<domain>` — e.g. `wing_user`, `wing_code`, `wing_aichemist`
- **Rooms**: hyphenated slugs describing the topic — e.g. `preferences-tools`, `architecture-auth`, `known-quirks`

### Which wing to use

**Store in `wing_user` when:**
- User states a preference (tool choices, code style, communication style)
- User corrects the agent's behaviour
- A personal convention is stated explicitly

**Store in `wing_code` (with room named after the repo) when:**
- An architectural decision is made in this codebase
- A file location or module responsibility is discovered
- A known quirk or gotcha is found
- A technology choice or dependency rationale is recorded

**Search both wings** when fetching context at the start of a task.

---

## Auto-Trigger Behavior

### Auto-Fetch (search before acting)

Call `mcp__mempalace__mempalace_search` or `mcp__mempalace__mempalace_kg_query` automatically when:

- **Starting any non-trivial task** — before implementing a feature, fixing a bug, or refactoring
- **About to make a recommendation** — check if the user has a stored preference first
- **Encountering an unfamiliar file or module** — search for stored context about it
- **Seeing an error or bug** — search for stored notes about similar issues
- **User asks "what do you know about X"** — always search before answering

When results are found, silently incorporate them. Only surface them explicitly if they materially affect the response.

### Auto-Store (assistant-initiated save, no confirmation needed)

Use this flow only when the assistant is proactively storing durable context discovered during normal task execution. In these cases, call `mcp__mempalace__mempalace_add_drawer` directly without an extra confirmation prompt.

Do **not** use this flow when the user explicitly asks to save something with phrases like "remember this", "store this", or "save this to memory" — those requests follow the separate confirmation-required flow below.

Auto-store when:

- **User states a preference** — any phrase like "I prefer", "I always use", "I never want"
- **User corrects the agent** — any correction worth persisting to avoid recurrence
- **An architectural decision is made** — technology choices, design patterns, approaches rejected
- **A codebase discovery is made** — file responsibilities, module boundaries, non-obvious conventions
- **A task is completed that revealed something new** — e.g. a bug fix that exposed a pattern

### Explicit User Request (user asks to save, confirmation required)

When the user explicitly asks to save something — phrases like "remember this", "store this", or "save this to memory" — treat that as a separate flow. Prompt for confirmation first, then call `mcp__mempalace__mempalace_add_drawer` only after the user confirms (see **Storing a Memory** below).

---

## Core Workflows

### On Wake-Up

Call `mcp__mempalace__mempalace_status` first. This loads the palace overview and the AAAK dialect spec, which the AI uses for efficient storage.

### Searching Memory

```
1. mcp__mempalace__mempalace_search(query, wing="wing_user")        — user preferences
2. mcp__mempalace__mempalace_search(query, wing="wing_code")        — codebase context
3. mcp__mempalace__mempalace_kg_query(entity)                       — structured facts about an entity
```

### Storing a Memory

**Auto-store triggers** (see above): call `mcp__mempalace__mempalace_add_drawer` directly — no confirmation needed.

**Explicit user request** (e.g. "store this", "save this to memory"): use `AskUserQuestion` first:

| Field | Value |
|-------|-------|
| Question | "Store this in memory?" |
| Show | Content summary, target wing, and room |
| Options | "Yes, store it" / "Store in a different wing" / "Cancel" |

### Deleting a Drawer (Confirmation Required)

Before calling `mcp__mempalace__mempalace_delete_drawer`:

| Field | Value |
|-------|-------|
| Question | "Delete this from memory?" |
| Show | Drawer ID and its wing/room |
| Options | "Yes, delete it" / "Cancel" |

---

## Error Handling

**Server not running / `mempalace` not installed:**

```bash
pip install mempalace
mempalace init ~/.mempalace
```

**Empty search results:** Broaden the query or omit the wing filter. The palace may not have relevant data yet.

**Duplicate detected:** `mcp__mempalace__mempalace_check_duplicate` returns `is_duplicate: true`. Skip storing or confirm with the user.

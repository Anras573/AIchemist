---
name: brainstorming
description: |
  Use this BEFORE any creative work — creating features, building components, adding functionality, or modifying existing behavior. Explores user intent, requirements, and design through structured dialogue before any implementation begins.

  Trigger phrases: "I want to build", "let's add", "how should I implement", "I'm thinking of", "new feature", "let's create", "design this", "help me plan", "should I use X or Y".
version: 1.0.0
---

# Brainstorming Skill

Help turn ideas into fully-formed designs through structured dialogue. Understand what's being built, explore the right approach, then document the design before any implementation begins.

<HARD-GATE>
Do NOT write any code, scaffold any project, invoke any implementation agent, or take any implementation action until you have presented a design and the user has explicitly approved it. This applies regardless of perceived simplicity.
</HARD-GATE>

## Anti-Pattern: "This Is Too Simple To Need A Design"

Every request goes through this process. A single utility function, a config change, a small refactor — all of them. "Simple" projects are where unexamined assumptions cause the most wasted work. The design can be short (a few sentences for truly simple things), but you must present it and get approval before touching code.

## Checklist

Complete these steps in order:

1. **Explore project context** — read relevant files, docs, recent commits before asking anything
2. **Check scope** — if the request covers multiple independent subsystems, flag it and decompose before proceeding
3. **Ask clarifying questions** — one at a time until you understand purpose, constraints, and success criteria
4. **Propose 2–3 approaches** — with trade-offs and a clear recommendation
5. **Present design** — section by section, get approval after each
6. **Write and commit spec** — create `docs/specs/` if needed, save to `docs/specs/YYYY-MM-DD-<topic>.md`, commit to git
7. **Transition to implementation** — hand off to the appropriate agent(s)

## Process

### 1. Explore Project Context

Before asking any questions, understand what exists:
- Read relevant source files and any project instruction files that are present: `CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`, `README.md`
- Check recent commits for context on current direction
- Identify existing patterns and conventions to follow

### 2. Check Scope

Before asking detailed questions, assess whether the request is appropriately scoped.

If the request covers multiple independent subsystems (e.g. "build a platform with auth, billing, notifications, and a dashboard"), flag it immediately:

> "This covers several independent pieces. Let's decompose before diving into any one part. The main components I see are: [list]. What order should we tackle them?"

Each sub-project then gets its own brainstorm → spec → implementation cycle.

### 3. Ask Clarifying Questions

Ask **one question at a time**. Prefer multiple choice where possible — easier to answer than open-ended.

Focus on:
- **Purpose** — what problem does this solve, and for whom?
- **Constraints** — performance, compatibility, existing patterns to follow
- **Success criteria** — how will you know it's working?
- **Scope edges** — what is explicitly out of scope?

### 4. Propose Approaches

Present 2–3 distinct approaches with honest trade-offs. Lead with your recommendation and explain why.

Example structure:
> **Option A (recommended):** [description]. Pro: [X]. Con: [Y].
> **Option B:** [description]. Pro: [X]. Con: [Y].
> **Option C:** [description]. Pro: [X]. Con: [Y].
>
> I'd go with A because [reasoning]. What do you think?

### 5. Present Design

Once you have enough to design, present it section by section. After each section, ask if it looks right before continuing.

Scale each section to its complexity — a few sentences for simple things, more detail for nuanced areas.

Cover:
- **Architecture** — how it fits into the existing system
- **Components** — what units exist, what each does, how they communicate
- **Data flow** — how data moves through the system
- **Error handling** — what can go wrong, how it's handled
- **Testing** — what to test and how

**Design for isolation:**
Each unit should have one clear purpose and communicate through well-defined interfaces. Ask yourself: can someone understand what this unit does without reading its internals? Can you change the internals without breaking consumers? If not, the boundaries need work. Smaller, well-bounded units are also easier to reason about and implement correctly.

**Working in existing codebases:**
Follow existing patterns. Where the existing code has problems that affect this work (a file that's grown too large, tangled responsibilities), include targeted improvements as part of the design. Don't propose unrelated refactoring.

### 6. Write and Commit Spec

After the user approves the design, confirm before writing anything:

**Write operations (confirmation required):**

| Operation | Confirmation prompt |
|-----------|-------------------|
| Write spec file | "Ready to write the spec to `docs/specs/YYYY-MM-DD-<topic>.md`. Shall I proceed?" |
| Git commit | "Commit the spec with message `docs: add <topic> design spec`?" |

Only proceed with each operation after receiving explicit confirmation.

**Path:** `docs/specs/YYYY-MM-DD-<topic>.md`

**Spec structure:**
```markdown
# <Topic>

## Problem
[What are we solving and why]

## Approach
[The chosen approach and rationale]

## Design
[Architecture, components, data flow]

## Error Handling
[What can go wrong and how it's handled]

## Testing
[What to test and how]

## Out of Scope
[What was explicitly excluded]
```

Commit the spec:
```bash
mkdir -p docs/specs
git add docs/specs/YYYY-MM-DD-<topic>.md
git commit -m "docs: add <topic> design spec"
```

Then ask the user to review the committed file before proceeding:

> "Spec committed to `docs/specs/YYYY-MM-DD-<topic>.md`. Take a look and let me know if anything needs changing before we start implementing."

### 7. Transition to Implementation

Once the user approves the spec, proceed to implementation using the appropriate agents for the work ahead (e.g. `.NET Agent` for C# work, `TypeScript/React Agent` for frontend, `DDD Agent` for domain modelling). For general tasks with no specialized agent, continue in the current conversation.

Do NOT start implementation before reaching this step.

## Key Principles

- **One question at a time** — don't stack multiple questions in one message
- **Multiple choice preferred** — easier to answer than open-ended when options are predictable
- **YAGNI ruthlessly** — cut anything not explicitly requested from all designs
- **Always explore alternatives** — propose 2–3 approaches before settling on one
- **Incremental validation** — present design section by section, not all at once
- **Spec is the artifact** — the written spec is the output of brainstorming; implementation follows from it

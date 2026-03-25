# Skills

Skills are context-aware capabilities that load into the main conversation when triggered by relevant user requests. Unlike agents (which run as subprocesses via Task tool), skills extend the current conversation with specialized knowledge and workflows.

## MermaidJS Diagrams Skill

Generates MermaidJS diagrams as fenced code blocks in Markdown. Diagrams render natively in GitHub, VS Code, Obsidian, and most modern Markdown viewers — no external tooling required.

**Trigger phrases:** "create a diagram", "draw a flowchart", "sequence diagram", "architecture diagram", "visualise this", "add a mermaid diagram", "diagram this flow", "draw a class diagram", "ER diagram", "state machine diagram", "C4 diagram".

### Supported Diagram Types

| Type | Use case |
|------|----------|
| Flowchart | Logic flows, decision trees, process maps |
| Sequence diagram | API calls, service interactions, message flows |
| Class diagram | Domain models, OOP structures |
| Entity-relationship | Database schemas |
| State diagram | State machines, lifecycles |
| C4 context | System architecture overviews |

### Behavior

1. Asks one clarifying question at a time (skipped if the request is already specific)
2. Selects the most appropriate diagram type
3. Generates the diagram with a syntax validation pass before presenting
4. Offers to embed in an existing file or save to `docs/diagrams/<topic>.md`

### Operations

| Type | Behavior |
|------|----------|
| Generate & preview | Automatic — shown inline in the conversation |
| Embed in file / save to `docs/diagrams/` | Requires explicit confirmation |

Integrates with the Brainstorming skill — offers to generate diagrams for architecture, data model, interaction flow, and state lifecycle sections of a spec.

---

## Brainstorming Skill

Structured design dialogue that ensures intent, requirements, and approach are understood before any implementation begins. Enforces a hard gate — no code is written until a design is approved.

**Trigger phrases:** "I want to build", "let's add", "how should I implement", "I'm thinking of", "new feature", "let's create", "design this", "help me plan", "should I use X or Y".

### Behavior

| Phase | What Happens |
|-------|-------------|
| **Explore** | Reads project context (files, docs, commits) before asking anything |
| **Clarify** | Asks one question at a time to understand purpose, constraints, and success criteria |
| **Approaches** | Proposes 2–3 options with trade-offs and a recommendation |
| **Design** | Presents design section by section, gets approval after each |
| **Spec** | Writes and commits the approved design to `docs/specs/YYYY-MM-DD-<topic>.md` |
| **Handoff** | Transitions to the appropriate implementation agent |

The spec written to disk is the primary artifact. Implementation follows from it.

### Key Principles

- **One question at a time** — never stacks multiple questions
- **YAGNI ruthlessly** — cuts anything not explicitly requested
- **Hard gate** — no implementation until the spec is written and the user approves it

---

## Beads Task Tracking Skill

AI-native task tracking using [Beads](https://github.com/steveyegge/beads) (`bd`), a distributed, git-backed graph issue tracker. Storage defaults to a sidecar directory outside the repo so no beads files are committed unless the repo has explicitly initialized beads.

**Trigger phrases:** "track tasks with beads", "use bd", "add a beads task", "show ready tasks", "claim a task", "list bd tasks", "create a bd issue", "show my tasks", "what's ready to work on", "update task status", or beads task IDs like `bd-a1b2`.

### Prerequisites

1. **`bd` CLI:** Install via one of:
   - `brew install beads` (macOS/Linux — recommended)
   - `npm install -g @beads/bd`
   - `go install github.com/steveyegge/beads/cmd/bd@latest`

2. **Dolt:** Bundled with beads — no separate installation needed.

### Storage Modes

| Mode | When | Storage Location |
|------|------|-----------------|
| **In-repo** | `.db` file exists under `<repo-root>/.beads/` | `<repo-root>/.beads/` |
| **Sidecar** (default) | No `.beads/*.db` in repo root | `~/.beads/<repo-name>/` |

Sidecar mode keeps beads data out of your repo entirely. If two repos share the same name, a collision fallback appends the parent directory (e.g. `~/.beads/my-app-work/`). See `skills/beads/references/storage-modes.md` for full details.

### Core Operations

| Operation | Command |
|-----------|---------|
| Show unblocked tasks | `bd ready --json` |
| List all tasks | `bd list --json` |
| Create a task | `bd create "title"` |
| View task details | `bd show bd-a1b2 --json` |
| Claim a task (atomic) | `bd update bd-a1b2 --claim` |
| Update status | `bd update bd-a1b2 --status done` |
| Add dependency | `bd dep add bd-child bd-parent` |
| Search | `bd search "query" --json` |

All commands require `--db "$BD_DB"` to target the correct database regardless of working directory. The table above omits it for brevity.

### Write Operations

Non-destructive writes (create, update, dep add) execute directly. Destructive operations (`bd delete`, `bd gc`, `bd purge`, `bd compact`) require explicit confirmation before execution.

### Configuration

No configuration file needed. Storage is auto-detected each session. To integrate beads workflow reminders into a project's `CLAUDE.md`:

```bash
bd --db "$BD_DB" setup claude --stealth
```

---

## Jira Skill

Jira integration for searching, viewing, creating, and managing issues.

**Trigger phrases:** "search Jira tickets", "get ticket details", "check ticket status", "find my tickets", "what am I working on", "create a Jira issue", "update a ticket", "add a comment", "move ticket to done", or Jira issue keys like `PROJ-123`.

### Read vs Write Operations

| Type | Operations | Behavior |
|------|------------|----------|
| **Read** | Search, view details, list projects, get transitions | Automatic — no confirmation needed |
| **Write** | Create, update, transition, comment, log work | Requires explicit user confirmation |

### Read Operations

- Search issues using JQL
- Fetch issue details by key
- List accessible projects
- Get available status transitions
- Look up user account IDs

### Write Operations (Confirmation Required)

Before any write operation, you'll see a confirmation prompt:

| Operation | Confirmation |
|-----------|--------------|
| Create issue | "Create this Jira issue?" with details shown |
| Update issue | "Update [ISSUE-KEY]?" with changes shown |
| Transition | "Move [ISSUE-KEY] from '[current]' to '[new]'?" |
| Add comment | "Add comment to [ISSUE-KEY]?" with text shown |
| Log work | "Log [time] on [ISSUE-KEY]?" |

### Configuration

On first use, the skill prompts to fetch and cache your Atlassian user info. This enables faster queries using `currentUser()` in JQL.

Config is stored at `${CLAUDE_PLUGIN_ROOT}/config.json` and excluded from version control.

## Playwright Skill

Browser automation and web testing using `playwright-cli` — token-efficient alternative to Playwright MCP.

**Trigger phrases:** "test this page", "automate the browser", "take a screenshot of", "check this UI", "fill out this form", "test the flow on", "click through", "scrape this page", "use playwright", "browser test", "open a browser", "navigate to".

### Why CLI over MCP

`playwright-cli` avoids loading large tool schemas and accessibility trees into the model context. Use Playwright MCP only for exploratory automation or long-running autonomous workflows where persistent state matters more than token cost.

### Prerequisites

```bash
npm install -g @playwright/cli@latest
```

### Operations

| Type | Operation | Behavior | Confirmation Prompt |
|------|-----------|----------|---------------------|
| **Read** | snapshot, screenshot, console, network | Automatic | — |
| **Write** | open, goto, click, fill, type, upload | Automatic for automation flows | — |
| **Destructive** | close-all | Requires explicit confirmation | "Close all browser sessions? This discards all in-memory state." |
| **Destructive** | cookie-clear | Requires explicit confirmation | "Clear all cookies for the current session?" |
| **Destructive** | localstorage-clear | Requires explicit confirmation | "Clear all localStorage for the current session?" |
| **Destructive** | kill-all | Requires explicit confirmation | "Kill all browser processes?" |

### Sessions

playwright-cli keeps the browser in memory by default. Use named sessions (`-s=name`) for project isolation or parallel automation. Set `PLAYWRIGHT_CLI_SESSION` env var to default a session for the current workspace.

---

## PostgreSQL Query Skill

PostgreSQL database querying with safe defaults that block write operations.

**Trigger phrases:** "query postgres", "run SQL", "check database", "show tables", "describe table", "query database", "execute SQL query", "list tables", "show indexes", "database schema".

### Prerequisites

1. **Environment variable:** `POSTGRES_URL` must be set with connection string
   ```
   postgresql://user:password@host:port/database
   ```

2. **psql client:** Must be installed
   - macOS: `brew install postgresql` or `brew install libpq`
   - Linux: `apt-get install postgresql-client`

### Read vs Write Operations

| Type | Operations | Behavior |
|------|------------|----------|
| **Read** | SELECT, EXPLAIN (without ANALYZE on writes), \d commands | Automatic — no confirmation needed |
| **Write** | INSERT, UPDATE, DELETE, DROP, TRUNCATE, ALTER, CREATE, COPY, GRANT, REVOKE, REFRESH, CALL, DO | **BLOCKED by default** |
| **Admin** | pg_cancel_backend, pg_terminate_backend, VACUUM, REINDEX, CLUSTER | Requires confirmation |

### Read Operations

- Run SELECT queries
- Explain query plans (EXPLAIN without ANALYZE)
- Describe tables (`\d table_name`)
- List tables, indexes, views (`\dt`, `\di`, `\dv`)
- List schemas, functions, roles

**Note:** `EXPLAIN ANALYZE` actually executes the query. `EXPLAIN ANALYZE DELETE...` will delete rows! Treat as write operation.

### Write Operations (Blocked by Default)

Write operations are blocked for safety. To enable writes, explicitly say:
- "enable writes"
- "I want to modify data"
- "allow write operations"

When enabled, write operations still require confirmation before execution.

### Output Formats

- **Default:** Markdown tables
- **On request:** JSON output

### Configuration

No configuration file needed — uses `POSTGRES_URL` environment variable directly.

## Code Review Skill

Comprehensive code review using parallel specialized agents, confidence-based filtering, Jira integration, and optional inline PR comments.

**Trigger phrases:** "review my code", "do a code review", "review this PR", "review this pull request", "check my changes", "review changes against main", "review against develop", "post review comments", "review and comment on PR", "code review with Jira context", "review my branch".

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--comment` | Post findings as inline PR comments | Off (local output only) |
| `--base <branch>` | Base branch for comparison (ignored when PR exists) | `main` |
| `--ticket <KEY>` | Manually specify Jira ticket | Auto-detect from branch/PR |

### Features

**Parallel Review Agents:**
- Guidelines agents (×2) — check code style and project conventions
- Bugs agent — identifies logic errors and potential bugs
- Security agent — scans for security vulnerabilities

**File-Triggered Agents:**
- .NET agent — invoked for C#/F# files
- DDD agent — invoked when domain model files are detected

**Confidence Scoring:**
- Each finding includes a confidence score (0–100)
- Default threshold: 80 — findings below this are filtered out
- Reduces false positives and noise

**Jira Integration:**
- Auto-detects Jira tickets from branch name or PR description
- Links review context to ticket acceptance criteria

**Inline PR Comments:**
- With `--comment`, posts findings directly to the PR
- Includes committable code suggestions where applicable

### Behavior

| Type | Operations | Behavior |
|------|------------|----------|
| **Read** | Fetch diff, gather guidelines, read PR details, fetch Jira ticket | Automatic |
| **Write** | Post inline PR comments, post summary comment | Requires explicit confirmation (or `--comment` flag) |

---

## Tool Preferences Skill

Guidance for selecting between equivalent tools when multiple options exist (e.g., `gh` CLI vs GitHub MCP tools).

**Purpose:** Ensures consistent, efficient tool selection across all agents.

### Key Preferences

| Domain | Preference |
|--------|------------|
| GitHub operations | Prefer `gh` CLI over GitHub MCP tools |
| Git operations | Prefer native `git` commands |
| Jira/Confluence | Use Atlassian MCP tools |
| Documentation | Use MCP tools (Context7, Microsoft Learn) |
| Browser automation | Prefer `playwright-cli` over Playwright MCP |

### Why These Preferences?

- **`gh` CLI:** Already authenticated, uses local repo state, predictable output, better error messages
- **Native git:** Respects local hooks (pre-commit, pre-push), maintains local/remote sync
- **MCP for docs:** Curated, up-to-date content more reliable than web searches
- **`playwright-cli`:** Token-efficient — avoids loading large tool schemas and accessibility trees into context

### Exceptions

Use GitHub MCP tools when CLI lacks functionality:
- Inline PR review comments (line-specific)
- Pending review management
- File contents at specific ref without cloning

Use Playwright MCP for:
- Exploratory automation requiring persistent state and rich introspection
- Long-running autonomous workflows where continuous browser context outweighs token cost

## Graphiti Graph Memory Skill

Persistent knowledge graph memory for AI agents. Automatically stores and retrieves context across sessions using a two-layer architecture.

**Trigger phrases:** "remember this", "store in memory", "what do you know about X", "search memory", "forget this", "clear memory". Also activates automatically during tasks — see below.

### Prerequisites

1. **Docker** installed and running
2. **Graphiti container** running locally
3. **`GRAPHITI_MCP_URL`** environment variable set:
   ```bash
   export GRAPHITI_MCP_URL=http://localhost:8123/mcp
   ```

### Two-Layer Memory Architecture

| Layer | `group_id` | Stores |
|-------|-----------|--------|
| **Global** | `aichemist` | User preferences, corrections, recurring patterns, cross-project conventions |
| **Project** | `<repo-name>` | Architectural decisions, codebase patterns, file responsibilities, known quirks |

The project `group_id` is derived automatically from the current git repo name. Both layers are always searched together.

### Auto-Fetch Behavior

The skill searches memory automatically — without being asked — before any non-trivial task, before making recommendations, when encountering unfamiliar files or modules, and when discussing technologies or debugging errors. Results are silently incorporated into reasoning.

### Auto-Store Behavior

The skill stores to memory automatically — without confirmation — when the user states a preference, corrects the agent, makes an architectural decision, or when a codebase discovery is made. The guiding principle is: save too much rather than too little.

### Operations

| Type | Operations | Behavior |
|------|------------|----------|
| **Read** | `search_nodes`, `search_memory_facts`, `get_entity_edge`, `get_episodes`, `get_status` | Automatic |
| **Write** | `add_memory` | Auto-store: no confirmation; explicit user request: confirmation required |
| **Destructive** | `delete_episode`, `delete_entity_edge` | Confirmation required |
| **Destructive** | `clear_graph` | Strong confirmation with preview of data to be lost |

---

## Daily Note Skill

Interact with your Obsidian daily note for journaling, task tracking, and session logging.

**Trigger phrases:** "show my daily note", "open daily note", "check daily note", "create daily note", "create today's note", "view today's note", "add to daily note", "append to daily note", "what's in my daily note".

### Operations

| Request | Action |
|---------|--------|
| "show today's daily note" | Retrieve and display today's note |
| "create today's daily note" | Create today's note |
| "add 'content' to my daily note" | Append content with timestamp |
| "check daily note for 2024-01-15" | Access a specific date's note |

### Behavior

| Type | Behavior |
|------|----------|
| Read | Automatic — no confirmation needed |
| Append/prepend | Automatic |
| Create | Automatic if note doesn't exist; confirms before overwriting |

---

## Capture Skill

Quick capture of thoughts, code snippets, and insights to Obsidian without leaving the coding flow.

**Trigger phrases:** "capture this", "save this to obsidian", "add to obsidian", "quick capture", "capture this thought", "capture this insight", "capture this code", "save this insight", "jot this down".

### Operations

| Request | Action |
|---------|--------|
| "capture this thought" | Append to today's daily note (default) |
| "save this to my 'Note Name' note" | Capture to a specific note |
| "capture this with tag #tag" | Capture with tags |
| "capture the current code context" | Capture with code context |

Captures are formatted with a timestamp header, content, optional tags, and project context.

### Behavior

| Type | Behavior |
|------|----------|
| Append to existing note | Automatic |
| Create note (target doesn't exist) | Automatic |
| Overwrite existing content | Requires explicit confirmation |

---

## Research Skill

Search your Obsidian vault for relevant context during coding sessions. Quickly surface past notes, decisions, and knowledge without leaving your workflow.

**Trigger phrases:** "research in vault", "search my notes", "search obsidian", "find in obsidian", "look up notes", "find notes about", "what do I have on", "search my vault for".

### Operations

| Request | Action |
|---------|--------|
| "research authentication patterns" | Full-text search across vault |
| "search in Projects/ for caching" | Search within a specific folder |
| "find top 10 results for error handling" | Return more results (default: 5) |

Results show title, path, and a matching excerpt. Follow up with "read 1" to open the full note.

### Behavior

Search operations are read-only — no confirmation needed. Exception: on first use, the skill prompts you to select a vault and saves the preference to `${CLAUDE_PLUGIN_ROOT}/config.json`.

---

## Obsidian Prerequisites (all three skills)

1. **Obsidian desktop app:** Version 1.5.0 or later (CLI included)
2. **Obsidian running:** The CLI communicates with the running application
3. **At least one vault:** Created and configured in Obsidian

Vault preference is stored in `${CLAUDE_PLUGIN_ROOT}/config.json` on first use. All three skills read from the same config key (`obsidian.preferredVault`).

### AGENT.md (Recommended)

Create an `AGENT.md` file at your vault root to give Claude context about your vault conventions — folder structure, daily note patterns, tagging taxonomy, capture preferences, etc. The skills read this file automatically on first vault interaction.

```markdown
# Vault Context for AI Assistants

## Folder Structure
- `Daily Notes/` - Daily journal entries (YYYY-MM-DD.md format)
- `Projects/` - Active project notes, one folder per project
- `Captures/` - Quick captures, inbox for processing

## Daily Note Conventions
- Path: `Daily Notes/YYYY-MM-DD.md`
- Sections: Tasks, Log, Reflections

## Tagging System
- `#status/active`, `#status/archived`
- `#type/meeting`, `#type/decision`
```

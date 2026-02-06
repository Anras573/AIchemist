# Skills

Skills are context-aware capabilities that load into the main conversation when triggered by relevant user requests. Unlike agents (which run as subprocesses via Task tool), skills extend the current conversation with specialized knowledge and workflows.

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

### Why These Preferences?

- **`gh` CLI:** Already authenticated, uses local repo state, predictable output, better error messages
- **Native git:** Respects local hooks (pre-commit, pre-push), maintains local/remote sync
- **MCP for docs:** Curated, up-to-date content more reliable than web searches

### Exceptions

Use GitHub MCP tools when CLI lacks functionality:
- Inline PR review comments (line-specific)
- Pending review management
- File contents at specific ref without cloning

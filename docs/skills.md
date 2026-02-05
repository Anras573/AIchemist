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

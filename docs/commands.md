# Commands

Slash commands are action-oriented operations invoked with `/command-name`.

## /jira-my-tickets

Show all Jira tickets where you are the assignee or creator since a specified date.

### Usage

```
/jira-my-tickets [date]
```

### Examples

```bash
/jira-my-tickets 2025-01-01
/jira-my-tickets last week
/jira-my-tickets yesterday
```

### First Run

The command will prompt to fetch and cache your Atlassian user info for faster queries.

### Output

Lists tickets grouped by your role:
- Tickets assigned to you
- Tickets you created (reported)

Each ticket shows: key, summary, status, and updated date.

## /code-review

Comprehensive code review with parallel agents, Jira integration, and confidence-based filtering.

### Usage

```
/code-review [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--base <branch>` | Base branch to compare against (default: `origin/main`) |
| `--comment` | Post findings as inline PR comments |
| `--ticket <key>` | Override Jira ticket detection with specific key |

### Examples

```bash
# Review current branch against origin/main
/code-review

# Review against a different base branch
/code-review --base develop

# Review and post comments to PR
/code-review --comment

# Specify Jira ticket explicitly
/code-review --ticket PROJ-123

# Combine options
/code-review --base develop --comment --ticket PROJ-456
```

### Features

**Parallel Review Agents:**
- Guidelines agent — checks code style and project conventions
- Bugs agent — identifies logic errors and potential bugs
- Security agent — scans for security vulnerabilities

**File-Triggered Agents:**
- DDD agent — invoked when domain model files are detected
- .NET agent — invoked for C# files
- TypeScript/React agent — invoked for TS/TSX files

**Confidence Scoring:**
- Each finding includes a confidence score (0-100)
- Default threshold: 80 — findings below this are filtered out
- Reduces false positives and noise

**Jira Integration:**
- Auto-detects Jira tickets from branch name (e.g., `feature/PROJ-123-description`)
- Can also detect from PR description
- Links review context to ticket requirements

**Inline PR Comments:**
- With `--comment`, posts findings directly to the PR
- Includes committable code suggestions where applicable
- Groups related findings by file

## /daily-note

Interact with your Obsidian daily note — retrieve, create, or append content.

### Usage

```
/daily-note [operation] [options]
```

### Operations

| Operation | Description |
|-----------|-------------|
| (none) | Retrieve and display today's note |
| `create` | Create today's daily note |
| `add <text>` | Append text to today's note |

### Options

| Option | Description |
|--------|-------------|
| `--date YYYY-MM-DD` | Target a specific date instead of today |

### Examples

```bash
# Show today's note
/daily-note

# Create today's note
/daily-note create

# Add content
/daily-note add "Discovered JWT refresh token issue"

# Check yesterday
/daily-note --date 2024-01-14
```

### First Run

Prompts for your daily note path pattern (e.g., `Daily Notes/YYYY-MM-DD.md`) and saves it for future use.

## /capture

Quick capture of thoughts, code snippets, or insights to Obsidian.

### Usage

```
/capture <text> [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--note <name>` | Capture to a specific note instead of daily note |
| `--tag #tag` | Add tag(s) to the capture (repeatable) |
| `--code` | Include current file context |

### Examples

```bash
# Quick capture to daily note
/capture This auth pattern works well for SPAs

# Capture to specific note
/capture --note "Architecture Decisions" Using event sourcing for audit

# Capture with tags
/capture --tag #security Found XSS in form handling

# Multiple tags
/capture --tag #bug --tag #priority Race condition in checkout
```

### Behavior

- Default: appends to today's daily note with timestamp
- Includes project context (current directory)
- Creates target note if it doesn't exist

## /research

Search your Obsidian vault for relevant context and past knowledge.

### Usage

```
/research <query> [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--folder <path>` | Limit search to specific folder |
| `--limit <n>` | Maximum results (default: 5) |

### Examples

```bash
# Basic search
/research authentication patterns

# Search within folder
/research --folder Projects/ caching strategy

# More results
/research --limit 10 error handling

# Combined
/research --folder Architecture/ --limit 3 database design
```

### Output

Returns matching notes with:
- Note title and path
- Relevant excerpt showing the match
- Option to "read N" to see full note content

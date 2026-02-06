---
name: PostgreSQL Query
description: |
  This skill should be used when the user asks to "query postgres", "run SQL", "check database", "show tables", "describe table", "query database", "execute SQL query", "list tables", "show indexes", "database schema", or mentions PostgreSQL/Postgres operations. Provides PostgreSQL database querying with automatic read operations and blocked write operations by default.
version: 1.0.0
---

# PostgreSQL Query Skill

This skill provides PostgreSQL database querying capabilities. **Read operations execute automatically. Write operations are BLOCKED by default** - the user must explicitly enable writes for the session.

## Prerequisites

### Environment Variable

The `POSTGRES_URL` environment variable must be set with a valid connection string:

```
postgresql://user:password@host:port/database
```

Example:
```bash
export POSTGRES_URL="postgresql://myuser:mypassword@localhost:5432/mydb"
```

### psql Client

The `psql` command-line client must be installed:

**macOS:**
```bash
# Full PostgreSQL installation
brew install postgresql

# Client-only (lighter weight)
brew install libpq && brew link --force libpq
```

**Linux (Debian/Ubuntu):**
```bash
sudo apt-get install postgresql-client
```

**Linux (RHEL/CentOS):**
```bash
sudo yum install postgresql
```

### First-Run Check

On first use, verify prerequisites:

1. Check if `POSTGRES_URL` environment variable is set
2. Check if `psql` is available in PATH

If either is missing, explain the setup requirements and provide installation instructions.

## Quick Reference

### Operation Types

| Type | Operations | Behavior |
|------|------------|----------|
| **Read** | SELECT, EXPLAIN (without ANALYZE on writes), \d commands | Automatic - no confirmation needed |
| **Write** | INSERT, UPDATE, DELETE, DROP, TRUNCATE, ALTER, CREATE, COPY, GRANT, REVOKE | **BLOCKED by default** |
| **Admin** | pg_cancel_backend, pg_terminate_backend, VACUUM, REINDEX, CLUSTER | **Requires confirmation** |

### Read Operations (Automatic)

- `SELECT` queries (except those with side-effect functions)
- `EXPLAIN` queries (without `ANALYZE` on write statements—see note below)
- `\d` - describe table structure
- `\dt` - list tables
- `\di` - list indexes
- `\dv` - list views
- `\dn` - list schemas
- `\df` - list functions
- `\du` - list roles

### Write Operations (Blocked by Default)

The following operations are **blocked** unless the user explicitly enables writes:

- `INSERT` - add data
- `UPDATE` - modify data
- `DELETE` - remove data
- `DROP` - drop objects
- `TRUNCATE` - empty tables
- `ALTER` - modify schema
- `CREATE` - create objects
- `COPY` - import/export data (can write files)
- `GRANT` / `REVOKE` - modify permissions
- `COMMENT` - modify metadata

**IMPORTANT:** `EXPLAIN ANALYZE` actually executes the query. If the analyzed query is a write operation (e.g., `EXPLAIN ANALYZE DELETE FROM users`), it **will execute the deletion**. Treat `EXPLAIN ANALYZE` + write statement as a write operation.

### Administrative Operations (Confirmation Required)

These operations use SELECT syntax but have side effects:

- `pg_cancel_backend(pid)` - cancels a running query (disruptive)
- `pg_terminate_backend(pid)` - terminates a connection (disruptive)
- `VACUUM` - reclaims storage, can lock tables
- `REINDEX` - rebuilds indexes, can lock tables
- `CLUSTER` - reorders table data, requires exclusive lock

Always confirm before executing these, even if writes are not enabled.

### Transaction Commands

Transaction control commands (`BEGIN`, `COMMIT`, `ROLLBACK`, `START TRANSACTION`) have limited utility with this skill because each `psql -c` invocation uses a **separate connection**. Transaction state is not preserved between calls. If transaction support is needed, inform the user of this limitation.

**To enable writes**, the user must explicitly request it:
- "enable writes"
- "I want to modify data"
- "allow write operations"
- "enable database modifications"

## Query Execution

### Basic Query Pattern

Use the Bash tool to execute queries via psql. Use **single quotes** around the query to prevent shell injection:

```bash
psql "$POSTGRES_URL" --no-password -c 'YOUR_QUERY_HERE'
```

**Security Note:** Always use single quotes around SQL queries to prevent shell command injection. With double quotes, malicious input containing backticks or `$()` could execute arbitrary shell commands. For queries that need single quotes internally, escape them as `''` (two single quotes) which is standard SQL escaping.

### Output Formats

**Default (Markdown tables):**
```bash
psql "$POSTGRES_URL" --no-password -t -A -F $'\t' -c 'SELECT * FROM users LIMIT 5'
```

Then format the tab-delimited output as a markdown table. Using tab (`$'\t'`) instead of pipe avoids issues when data contains pipe characters. When converting to markdown, escape any literal `|` in the data as `\|`.

**JSON output (when requested):**
```bash
psql "$POSTGRES_URL" --no-password -t -A -c 'SELECT row_to_json(t) FROM (SELECT * FROM users LIMIT 5) t'
```

### Useful psql Flags

| Flag | Purpose |
|------|---------|
| `-c 'query'` | Execute single query (use single quotes!) |
| `--no-password` | Never prompt for password (use connection string) |
| `-t` | Tuples only (no headers/footers) |
| `-A` | Unaligned output (no padding) |
| `-F $'\t'` | Set field separator (tab recommended) |
| `-x` | Expanded output (one column per line) |

## Core Workflows

### Listing Tables

```bash
psql "$POSTGRES_URL" --no-password -c '\dt'
```

### Describing a Table

```bash
psql "$POSTGRES_URL" --no-password -c '\d table_name'
```

### Running SELECT Queries

```bash
# Get data with markdown-friendly output
psql "$POSTGRES_URL" --no-password -t -A -F $'\t' -c 'SELECT id, name, email FROM users LIMIT 10'
```

Format result as:

```markdown
| id | name | email |
|----|------|-------|
| 1 | Alice | alice@example.com |
| 2 | Bob | bob@example.com |
```

### Explaining Query Plans

```bash
# EXPLAIN without ANALYZE (safe - doesn't execute the query)
psql "$POSTGRES_URL" --no-password -c 'EXPLAIN SELECT * FROM users WHERE status = ''active'''

# EXPLAIN ANALYZE (executes the query - safe only for SELECT)
psql "$POSTGRES_URL" --no-password -c 'EXPLAIN ANALYZE SELECT * FROM users WHERE status = ''active'''
```

**Warning:** Never use `EXPLAIN ANALYZE` with write statements unless writes are enabled and you intend to execute them. `EXPLAIN ANALYZE DELETE FROM users` will actually delete rows!

## Write Operations Workflow

### Detecting Write Operations

Before executing any query, check if it contains write-related keywords:

**Data-modifying statements:**
- `INSERT`, `UPDATE`, `DELETE`, `DROP`, `TRUNCATE`, `ALTER`, `CREATE`
- `COPY`, `GRANT`, `REVOKE`, `COMMENT`

**Special cases:**
- `EXPLAIN ANALYZE` + any of the above = treat as write operation
- `pg_cancel_backend`, `pg_terminate_backend` = require confirmation (admin ops)
- `VACUUM`, `REINDEX`, `CLUSTER` = require confirmation (admin ops)

Use case-insensitive matching and handle queries that start with these keywords or contain them after CTEs (`WITH`).

### When Writes Are Blocked

If a write operation is detected and writes are not enabled:

```markdown
**Write operation blocked**

The query contains a write operation (`DELETE`), which is blocked by default for safety.

To enable write operations for this session, say:
- "enable writes" or
- "I want to modify data"

Then retry your query.
```

### Enabling Writes

When the user explicitly enables writes, acknowledge it:

```markdown
**Write operations enabled** for this session.

I'll ask for confirmation before executing any data-modifying queries.
```

### Executing Write Operations (When Enabled)

When writes are enabled and a write query is requested:

1. **Preview** the operation
2. **Confirm** using AskUserQuestion
3. **Execute** only if confirmed
4. **Report** results

Example confirmation:

```markdown
I'm ready to execute this DELETE statement:

**Query:**
```sql
DELETE FROM users WHERE status = 'inactive' AND last_login < '2023-01-01'
```

This will permanently remove matching rows from the `users` table.
```

Use AskUserQuestion:
```
Question: "Execute this DELETE query?"
Options:
  - "Yes, execute it" - Proceed with deletion
  - "Show affected rows first" - Run SELECT with same WHERE clause
  - "Cancel" - Abort the operation
```

## Output Formatting

### Markdown Table Format (Default)

Convert psql output to readable markdown tables:

```markdown
| column1 | column2 | column3 |
|---------|---------|---------|
| value1  | value2  | value3  |
| value4  | value5  | value6  |
```

### JSON Format (On Request)

When user asks for JSON output:

```bash
psql "$POSTGRES_URL" --no-password -t -A -c 'SELECT json_agg(row_to_json(t)) FROM (SELECT * FROM users LIMIT 5) t'
```

### Handling Large Result Sets

For queries returning many rows:
- When **generating** a simple SELECT query, include `LIMIT 100` if the user hasn't specified a limit
- Do **not** automatically inject LIMIT into user-provided SQL (could break subqueries, CTEs, aggregations)
- Inform user: "Showing first 100 rows. Add `LIMIT n` to see more or fewer."

### Handling NULL Values

Display NULL values clearly in output:
```markdown
| id | name | email |
|----|------|-------|
| 1 | Alice | alice@example.com |
| 2 | Bob | (NULL) |
```

## Error Handling

### Connection Errors

```
psql: error: connection to server failed
```

Suggest:
- Verify `POSTGRES_URL` is correctly set
- Check that the database server is running
- Verify network connectivity to the host
- Check firewall rules if connecting remotely

### Authentication Errors

```
psql: error: FATAL: password authentication failed
```

Suggest:
- Verify credentials in `POSTGRES_URL`
- Check if user has access to the specified database
- Verify pg_hba.conf allows the connection method

### Missing psql

```
psql: command not found
```

Provide installation instructions based on detected platform.

### Permission Errors

```
ERROR: permission denied for table users
```

Explain:
- Current database user lacks required permissions
- Contact database administrator to grant access

## Security Notes

- Never log or display the full `POSTGRES_URL` (contains password)
- Use `$POSTGRES_URL` in commands (shell expansion hides value)
- Write operations require explicit opt-in for safety
- Always confirm destructive operations before execution

## Additional Resources

For common query patterns and useful PostgreSQL commands, see `references/common-queries.md`.

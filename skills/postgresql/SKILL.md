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
| **Read** | SELECT, EXPLAIN, \d commands | Automatic - no confirmation needed |
| **Write** | INSERT, UPDATE, DELETE, DROP, TRUNCATE, ALTER, CREATE | **BLOCKED by default** |

### Read Operations (Automatic)

- `SELECT` queries
- `EXPLAIN` / `EXPLAIN ANALYZE` queries
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

**To enable writes**, the user must explicitly request it:
- "enable writes"
- "I want to modify data"
- "allow write operations"
- "enable database modifications"

## Query Execution

### Basic Query Pattern

Use the Bash tool to execute queries via psql:

```bash
psql "$POSTGRES_URL" --no-password -c "YOUR_QUERY_HERE"
```

### Output Formats

**Default (Markdown tables):**
```bash
psql "$POSTGRES_URL" --no-password -t -A -F '|' -c "SELECT * FROM users LIMIT 5"
```

Then format the pipe-delimited output as a markdown table.

**JSON output (when requested):**
```bash
psql "$POSTGRES_URL" --no-password -t -A -c "SELECT row_to_json(t) FROM (SELECT * FROM users LIMIT 5) t"
```

### Useful psql Flags

| Flag | Purpose |
|------|---------|
| `-c "query"` | Execute single query |
| `--no-password` | Never prompt for password (use connection string) |
| `-t` | Tuples only (no headers/footers) |
| `-A` | Unaligned output (no padding) |
| `-F '|'` | Set field separator |
| `-x` | Expanded output (one column per line) |

## Core Workflows

### Listing Tables

```bash
psql "$POSTGRES_URL" --no-password -c "\dt"
```

### Describing a Table

```bash
psql "$POSTGRES_URL" --no-password -c "\d table_name"
```

### Running SELECT Queries

```bash
# Get data with markdown-friendly output
psql "$POSTGRES_URL" --no-password -t -A -F '|' -c "SELECT id, name, email FROM users LIMIT 10"
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
psql "$POSTGRES_URL" --no-password -c "EXPLAIN ANALYZE SELECT * FROM users WHERE status = 'active'"
```

## Write Operations Workflow

### Detecting Write Operations

Before executing any query, check if it contains write keywords:
- `INSERT`, `UPDATE`, `DELETE`, `DROP`, `TRUNCATE`, `ALTER`, `CREATE`

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
psql "$POSTGRES_URL" --no-password -t -A -c "
SELECT json_agg(row_to_json(t))
FROM (SELECT * FROM users LIMIT 5) t
"
```

### Handling Large Result Sets

For queries returning many rows:
- Default to `LIMIT 100` if no limit specified
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

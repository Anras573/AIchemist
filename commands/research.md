---
name: research
description: Search your Obsidian vault for relevant context, notes, and past knowledge on a topic.
argument-hint: "<query> [--folder <path>] [--limit <n>]"
allowed-tools: mcp__obsidian__*, Read
---

# Research Command

Search your Obsidian vault for relevant context during coding sessions. Quickly find past notes, decisions, and knowledge without leaving your workflow.

## Usage

```
/research authentication patterns
/research --folder Projects/ caching strategy
/research --limit 10 error handling
```

## Arguments

| Argument | Description |
|----------|-------------|
| `<query>` | Search terms (required) |
| `--folder <path>` | Limit search to specific folder |
| `--limit <n>` | Maximum results to show (default: 5) |

## Execution Steps

### 1. Parse Arguments

Extract from user input:
- `query`: The search terms (everything not a flag)
- `--folder <path>`: Optional folder filter
- `--limit <n>`: Optional result limit (default: 5)

### 2. Execute Search

Use `mcp__obsidian__search` with the query:

```
1. Call mcp__obsidian__search with query
2. Receive array of matching results
```

### 3. Filter Results (if --folder)

If `--folder` specified:
```
1. Filter results to only include files starting with folder path
2. Example: --folder "Projects/" keeps only "Projects/..." paths
```

### 4. Rank and Limit Results

```
1. Sort by relevance (search API typically returns in relevance order)
2. Take top N results (based on --limit, default 5)
```

### 5. Enrich Results

For each result, gather context:
```
1. Extract note title from path
2. Get matching excerpt from search result
3. Optionally fetch last modified date if available
```

### 6. Present Results

Format results clearly:

```markdown
### Research Results: "authentication patterns"

**Found 5 relevant notes:**

---

**1. Authentication Design**
`Architecture/Auth.md`

> We decided to use JWT with refresh tokens because they allow stateless
> verification while still providing a mechanism for token revocation...

---

**2. API Security Notes**
`Projects/API/security.md`

> OAuth2 flow handles the authentication layer. Key considerations:
> - Token expiration: 15 minutes for access, 7 days for refresh...

---

**3. Login Flow Redesign**
`Projects/WebApp/login-redesign.md`

> The new authentication pattern separates concerns between identity
> verification and session management...

---

_Say "read 1" to see the full note, or refine your search._
```

### 7. Handle Follow-up (read N)

If user responds with "read 1", "read 2", etc.:
```
1. Identify which result they want
2. Use mcp__obsidian__get_file_contents to fetch full content
3. Display the complete note
```

## Result Format

Each result shows:
- **Title**: Derived from filename or first heading
- **Path**: Full path in vault (as clickable context)
- **Excerpt**: Relevant matching text (2-3 sentences)

## Error Handling

### No Query Provided

```markdown
**No search query provided**

Usage: `/research <your query>`

Examples:
- `/research authentication`
- `/research --folder Projects/ caching`
```

### No Results Found

```markdown
**No results found** for "quantum encryption"

Suggestions:
- Try broader terms: "encryption" instead of "quantum encryption"
- Check spelling
- Search in specific folder: `--folder Projects/`
- The topic might not be in your vault yet
```

### Connection Failed

```markdown
**Obsidian connection failed**

Please verify:
1. Obsidian is running with Local REST API plugin enabled
2. `OBSIDIAN_API_KEY` environment variable is set
```

### Folder Not Found

```markdown
**Folder not found:** `Projects/OldProject/`

Available top-level folders:
- Projects/
- Archive/
- Daily Notes/

Try: `/research --folder Projects/ your query`
```

## Examples

**Basic search:**
```
/research caching strategies
```

**Search within folder:**
```
/research --folder Architecture/ database design
```

**Get more results:**
```
/research --limit 10 error handling patterns
```

**Combined:**
```
/research --folder Projects/API/ --limit 3 rate limiting
```

## Tips

- **Be specific**: "JWT refresh token rotation" finds better matches than "auth"
- **Use folder filters**: Narrow down to relevant project or topic area
- **Follow up**: Use "read N" to dive into promising results
- **Iterate**: Refine your query based on initial results

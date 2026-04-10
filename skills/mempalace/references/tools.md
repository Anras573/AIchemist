# MemPalace Tool Reference

## READ Tools (Automatic — No Confirmation Needed)

### `mcp__mempalace__mempalace_status`
Palace overview — total drawers, wing and room counts. Also returns the AAAK dialect spec and memory protocol. **Call this on wake-up.**

```
(no parameters)
```

---

### `mcp__mempalace__mempalace_search`
Semantic vector search over palace contents.

```
query   string  required  Natural language search query
limit   int     optional  Max results (default: 5)
wing    string  optional  Filter to a specific wing
room    string  optional  Filter to a specific room
```

**Returns:** Matching drawers with similarity scores and metadata.

---

### `mcp__mempalace__mempalace_list_wings`
List all wings with drawer counts.

```
(no parameters)
```

---

### `mcp__mempalace__mempalace_list_rooms`
List rooms within a wing (or all rooms).

```
wing  string  optional  Wing to inspect
```

---

### `mcp__mempalace__mempalace_get_taxonomy`
Full taxonomy: wing → room → drawer count.

```
(no parameters)
```

---

### `mcp__mempalace__mempalace_check_duplicate`
Check if content already exists before filing.

```
content    string  required  Content to check
threshold  number  optional  Similarity threshold 0–1 (default: 0.9)
```

**Returns:** `is_duplicate` boolean + matching drawers.

---

### `mcp__mempalace__mempalace_kg_query`
Query the knowledge graph for an entity's relationships. Returns typed facts with temporal validity.

```
entity     string  required  Entity to query (e.g. 'Max', 'AIchemist')
as_of      string  optional  Date filter — facts valid at this date (YYYY-MM-DD)
direction  string  optional  'outgoing', 'incoming', or 'both' (default: 'both')
```

---

### `mcp__mempalace__mempalace_kg_timeline`
Chronological timeline of facts for an entity (or all entities).

```
entity  string  optional  Entity to get timeline for
```

---

### `mcp__mempalace__mempalace_kg_stats`
Knowledge graph overview: entities, triples, relationship types.

```
(no parameters)
```

---

### `mcp__mempalace__mempalace_diary_read`
Read an agent's recent diary entries.

```
agent_name  string  required  Agent name
last_n      int     optional  Number of entries to return (default: 10)
```

---

## WRITE Tools (Auto-store: no confirmation; explicit request: confirmation required)

### `mcp__mempalace__mempalace_add_drawer`
File content into a wing/room. Checks for duplicates first (idempotent by content hash).

```
wing         string  required  Target wing (e.g. 'wing_user', 'wing_code')
room         string  required  Target room (e.g. 'preferences-tools', 'architecture-auth')
content      string  required  Content to store — verbatim, never summarised
source_file  string  optional  Where this came from
added_by     string  optional  Who is filing this (default: 'mcp')
```

---

### `mcp__mempalace__mempalace_kg_add`
Add a fact to the knowledge graph (subject → predicate → object).

```
subject        string  required  Entity doing/being something
predicate      string  required  Relationship type (e.g. 'prefers', 'works_on')
object         string  required  Entity being connected to
valid_from     string  optional  When this became true (YYYY-MM-DD)
source_closet  string  optional  Source drawer ID
```

---

### `mcp__mempalace__mempalace_kg_invalidate`
Mark a fact as no longer true (set end date).

```
subject    string  required  Entity
predicate  string  required  Relationship
object     string  required  Connected entity
ended      string  optional  When it stopped being true (YYYY-MM-DD, default: today)
```

---

### `mcp__mempalace__mempalace_diary_write`
Write a diary entry for an agent in AAAK format.

```
agent_name  string  required  Agent name (each agent gets its own diary wing)
entry       string  required  Diary entry in AAAK format
topic       string  optional  Topic tag (default: 'general')
```

---

## DESTRUCTIVE Tools (Confirmation Required)

### `mcp__mempalace__mempalace_delete_drawer`
Delete a single drawer by ID. **Irreversible.**

```
drawer_id  string  required  ID of the drawer to delete
```

Always confirm with the user before calling this.

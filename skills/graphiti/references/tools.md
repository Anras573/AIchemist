# Graphiti Tool Reference

## READ Tools (Automatic — No Confirmation Needed)

### `graphiti/search_nodes`
Search for entity nodes (people, concepts, systems, decisions) in the graph.

```
query        string   required  Natural language search query
group_ids    string[] optional  Filter to specific namespaces
max_nodes    int      optional  Max results (default: 10)
entity_types string[] optional  Filter by entity type labels
```

**Returns:** List of nodes with `uuid`, `name`, `labels`, `summary`, `attributes`, `group_id`

---

### `graphiti/search_memory_facts`
Search for facts — relationships between entities. Best for "what does X relate to Y" queries.

```
query            string   required  Natural language search query
group_ids        string[] optional  Filter to specific namespaces
max_facts        int      optional  Max results (default: 10)
center_node_uuid string   optional  Anchor search around a specific node UUID
```

**Returns:** List of facts with temporal metadata (created_at, valid/invalid status)

---

### `graphiti/get_entity_edge`
Retrieve a single fact/relationship by its UUID. Use when you have a specific UUID from a prior search.

```
uuid  string  required  UUID of the entity edge
```

---

### `graphiti/get_episodes`
List raw episodes (the source content that was ingested). Useful for reviewing what was stored.

```
group_ids     string[] optional  Filter to specific namespaces
max_episodes  int      optional  Max results (default: 10)
```

**Returns:** List of episodes with content, source type, timestamps

---

### `graphiti/get_status`
Health check — verifies the server and database are reachable. Call this if tools return unexpected errors.

```
(no parameters)
```

---

## WRITE Tools (Confirmation Required)

### `graphiti/add_memory`
Add an episode to the knowledge graph. Graphiti will automatically extract entities and relationships.

```
name               string  required  Descriptive name for the episode
episode_body       string  required  Content to store (text, JSON string, or message)
group_id           string  optional  Target namespace (defaults to server default)
source             string  optional  'text' | 'json' | 'message' (default: 'text')
source_description string  optional  Human-readable description of the source
uuid               string  optional  Custom UUID (auto-generated if omitted)
```

**Source types:**
- `text` — plain prose, notes, decisions, observations
- `json` — structured data; `episode_body` must be a valid JSON string
- `message` — conversation-style content

---

## DESTRUCTIVE Tools (Strong Confirmation Required)

### `graphiti/delete_episode`
Remove a single episode by UUID. The extracted nodes/facts may persist.

```
uuid  string  required  UUID of the episode to delete
```

---

### `graphiti/delete_entity_edge`
Remove a single fact/relationship by UUID. Does not remove the nodes themselves.

```
uuid  string  required  UUID of the entity edge to delete
```

---

### `graphiti/clear_graph`
**⚠️ IRREVERSIBLE.** Wipes all data for the specified group IDs.

```
group_ids  string[]  optional  Groups to clear. If omitted, clears the default group.
```

Always show the user exactly which `group_id`s will be wiped before proceeding.

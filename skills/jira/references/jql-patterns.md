# JQL Patterns Reference

## Basic JQL Syntax

JQL (Jira Query Language) queries consist of:
- **Fields**: project, status, assignee, priority, etc.
- **Operators**: =, !=, ~, in, is, was, changed
- **Keywords**: AND, OR, NOT, ORDER BY
- **Functions**: currentUser(), now(), startOfDay(), etc.

## Field Reference

### Common Fields

| Field | Type | Example |
|-------|------|---------|
| `project` | Text | `project = "PROJ"` |
| `status` | Text | `status = "In Progress"` |
| `assignee` | User | `assignee = currentUser()` |
| `reporter` | User | `reporter = "john.doe"` |
| `priority` | Text | `priority = High` |
| `type` | Text | `type = Bug` |
| `labels` | Text | `labels = "needs-review"` |
| `created` | Date | `created >= -7d` |
| `updated` | Date | `updated >= startOfMonth()` |
| `resolved` | Date | `resolved >= -30d` |
| `duedate` | Date | `duedate <= 7d` |
| `summary` | Text | `summary ~ "login"` |
| `description` | Text | `description ~ "error"` |

### Custom Fields

Custom fields use format `cf[XXXXX]` or their configured name:
```sql
"Story Points" > 5
cf[10001] = "Value"
```

## Operators

### Comparison Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `=` | Equals | `status = Done` |
| `!=` | Not equals | `status != Done` |
| `>` | Greater than | `priority > Medium` |
| `>=` | Greater or equal | `created >= -7d` |
| `<` | Less than | `duedate < 7d` |
| `<=` | Less or equal | `updated <= -30d` |

### Text Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `~` | Contains | `summary ~ "error"` |
| `!~` | Does not contain | `summary !~ "test"` |

### Collection Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `in` | In list | `status in (Open, "In Progress")` |
| `not in` | Not in list | `priority not in (Low, Lowest)` |
| `is` | Is empty/null | `assignee is EMPTY` |
| `is not` | Is not empty | `assignee is not EMPTY` |

### Change Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `was` | Previously was | `status was "In Progress"` |
| `was in` | Was in list | `status was in (Open, "To Do")` |
| `was not` | Was not | `assignee was not currentUser()` |
| `changed` | Has changed | `status changed` |

## Functions

### User Functions

```sql
-- Current logged-in user
assignee = currentUser()

-- Members of a group
assignee in membersOf("developers")
```

### Date Functions

```sql
-- Relative dates
created >= -7d                    -- Last 7 days
updated >= -1w                    -- Last week
resolved >= -1M                   -- Last month

-- Calendar functions
created >= startOfDay()           -- Since midnight today
created >= startOfWeek()          -- Since start of week
created >= startOfMonth()         -- Since start of month
created >= startOfYear()          -- Since start of year

-- End functions
duedate <= endOfWeek()
duedate <= endOfMonth()

-- Specific date
created >= "2024-01-01"
```

### Sprint Functions

```sql
-- Issues in open sprints
sprint in openSprints()

-- Issues in closed sprints
sprint in closedSprints()

-- Issues in future sprints
sprint in futureSprints()
```

### Project Functions

```sql
-- Projects user leads
project in projectsLeadByUser()

-- Projects with specific permission
project in projectsWhereUserHasPermission("Edit Issues")
```

## Complex Query Examples

### Sprint Planning

```sql
-- Unestimated stories in backlog
project = PROJ
  AND type = Story
  AND "Story Points" is EMPTY
  AND status = "To Do"
```

### Release Management

```sql
-- Issues fixed in version
project = PROJ
  AND fixVersion = "1.0.0"
  AND status = Done
  ORDER BY resolved DESC

-- Issues blocking release
project = PROJ
  AND fixVersion = "1.0.0"
  AND status != Done
  ORDER BY priority DESC
```

### Team Workload

```sql
-- Issues per team member in sprint
project = PROJ
  AND sprint in openSprints()
  AND assignee is not EMPTY
  ORDER BY assignee, priority DESC
```

### Bug Tracking

```sql
-- Critical bugs not in progress
project = PROJ
  AND type = Bug
  AND priority in (Critical, Blocker)
  AND status not in ("In Progress", Done, Resolved)
  ORDER BY created ASC

-- Bugs created this week
project = PROJ
  AND type = Bug
  AND created >= startOfWeek()
  ORDER BY priority DESC
```

### Stale Issues

```sql
-- Issues not updated in 30 days
project = PROJ
  AND status not in (Done, Closed)
  AND updated <= -30d
  ORDER BY updated ASC

-- Assigned but inactive
project = PROJ
  AND assignee is not EMPTY
  AND status = "In Progress"
  AND updated <= -7d
```

### Cross-Project Queries

```sql
-- All my issues across projects
assignee = currentUser()
  AND status not in (Done, Closed)
  ORDER BY project, priority DESC

-- Issues I reported
reporter = currentUser()
  ORDER BY created DESC
```

## Ordering Results

```sql
-- Single field
ORDER BY created DESC

-- Multiple fields
ORDER BY priority DESC, created ASC

-- Custom field ordering
ORDER BY "Story Points" DESC NULLS LAST
```

### Order Options

- `ASC` - Ascending (default)
- `DESC` - Descending
- `NULLS FIRST` - Empty values first
- `NULLS LAST` - Empty values last

## Performance Tips

1. **Use indexed fields first**: project, status, type, priority
2. **Limit text searches**: Use specific terms, avoid wildcards at start
3. **Use date ranges**: Instead of scanning all history
4. **Limit results**: Use pagination for large result sets
5. **Avoid OR on different fields**: Prefer separate queries

## Escaping Special Characters

```sql
-- Quotes in text
summary ~ "can't"
summary ~ "\"quoted\""

-- Reserved words
summary ~ "\\\"AND\\\""
```

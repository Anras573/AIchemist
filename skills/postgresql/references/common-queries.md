# Common PostgreSQL Query Patterns

Quick reference for frequently used PostgreSQL queries and commands.

## Table Information

### List All Tables

```sql
-- Using psql meta-command
\dt

-- Using SQL
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
```

### Describe Table Structure

```sql
-- Using psql meta-command
\d table_name

-- Using SQL (columns with types)
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'your_table'
ORDER BY ordinal_position;
```

### Table Size

```sql
-- Single table size
SELECT pg_size_pretty(pg_total_relation_size('table_name'));

-- All tables with sizes
SELECT
    relname AS table_name,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
    pg_size_pretty(pg_relation_size(relid)) AS data_size,
    pg_size_pretty(pg_indexes_size(relid)) AS index_size
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

### Row Counts

```sql
-- Exact count (slow for large tables)
SELECT COUNT(*) FROM table_name;

-- Approximate count (fast, from stats)
SELECT reltuples::bigint AS estimate
FROM pg_class
WHERE relname = 'table_name';
```

## Index Information

### List Indexes

```sql
-- Using psql meta-command
\di

-- Using SQL with details
SELECT
    indexname,
    tablename,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
```

### Index Usage Stats

```sql
SELECT
    relname AS table_name,
    indexrelname AS index_name,
    idx_scan AS times_used,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

### Find Missing Indexes (Sequential Scans)

```sql
SELECT
    relname AS table_name,
    seq_scan AS sequential_scans,
    seq_tup_read AS rows_fetched,
    idx_scan AS index_scans,
    n_live_tup AS row_count
FROM pg_stat_user_tables
WHERE seq_scan > 0
ORDER BY seq_tup_read DESC
LIMIT 10;
```

## Query Analysis

### Explain Query Plan

```sql
-- Basic explain
EXPLAIN SELECT * FROM users WHERE email = 'test@example.com';

-- With execution stats (actually runs the query)
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'test@example.com';

-- Verbose with buffers
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM users WHERE email = 'test@example.com';
```

### Currently Running Queries

```sql
SELECT
    pid,
    now() - pg_stat_activity.query_start AS duration,
    query,
    state
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 seconds'
  AND state != 'idle'
ORDER BY duration DESC;
```

### Kill a Query

```sql
-- Cancel query (graceful)
SELECT pg_cancel_backend(pid);

-- Terminate connection (force)
SELECT pg_terminate_backend(pid);
```

## Data Exploration

### Sample Data

```sql
-- First N rows
SELECT * FROM table_name LIMIT 10;

-- Random sample
SELECT * FROM table_name
ORDER BY RANDOM()
LIMIT 10;

-- TABLESAMPLE for large tables (faster)
SELECT * FROM table_name TABLESAMPLE SYSTEM (1);  -- ~1% of rows
```

### Column Statistics

```sql
-- Value distribution
SELECT column_name, COUNT(*) as count
FROM table_name
GROUP BY column_name
ORDER BY count DESC
LIMIT 20;

-- Numeric column stats
SELECT
    MIN(column_name) AS min_val,
    MAX(column_name) AS max_val,
    AVG(column_name) AS avg_val,
    STDDEV(column_name) AS std_dev
FROM table_name;
```

### Find Duplicates

```sql
SELECT column1, column2, COUNT(*)
FROM table_name
GROUP BY column1, column2
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;
```

### NULL Analysis

```sql
SELECT
    COUNT(*) AS total_rows,
    COUNT(column_name) AS non_null,
    COUNT(*) - COUNT(column_name) AS null_count,
    ROUND(100.0 * (COUNT(*) - COUNT(column_name)) / COUNT(*), 2) AS null_pct
FROM table_name;
```

## Schema Information

### List Schemas

```sql
\dn

-- Or using SQL
SELECT schema_name
FROM information_schema.schemata
ORDER BY schema_name;
```

### List Views

```sql
\dv

-- Or using SQL
SELECT table_name AS view_name
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;
```

### List Functions

```sql
\df

-- Or using SQL
SELECT
    routine_name,
    routine_type,
    data_type AS return_type
FROM information_schema.routines
WHERE routine_schema = 'public'
ORDER BY routine_name;
```

### Foreign Keys

```sql
SELECT
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
ORDER BY tc.table_name;
```

## Database Information

### Current Database

```sql
SELECT current_database();
```

### Database Size

```sql
SELECT pg_size_pretty(pg_database_size(current_database()));
```

### Connection Info

```sql
SELECT
    current_user,
    current_database(),
    inet_server_addr() AS server_ip,
    inet_server_port() AS server_port;
```

### Active Connections

```sql
SELECT
    datname AS database,
    usename AS user,
    client_addr,
    state,
    COUNT(*)
FROM pg_stat_activity
GROUP BY datname, usename, client_addr, state
ORDER BY COUNT(*) DESC;
```

## JSON Operations

### Query JSON Columns

```sql
-- Extract value from JSON
SELECT data->>'name' AS name FROM table_name;

-- Query nested JSON
SELECT data->'address'->>'city' AS city FROM table_name;

-- Filter by JSON value
SELECT * FROM table_name
WHERE data->>'status' = 'active';

-- Expand JSON array
SELECT jsonb_array_elements(data->'items') AS item
FROM table_name;
```

### Aggregate to JSON

```sql
-- Single row to JSON
SELECT row_to_json(t) FROM (SELECT id, name FROM users LIMIT 1) t;

-- Multiple rows to JSON array
SELECT json_agg(row_to_json(t))
FROM (SELECT id, name FROM users LIMIT 10) t;
```

## Date/Time Queries

### Time-Based Filtering

```sql
-- Records from last 7 days
SELECT * FROM events
WHERE created_at > NOW() - INTERVAL '7 days';

-- Records from specific date range
SELECT * FROM events
WHERE created_at BETWEEN '2024-01-01' AND '2024-01-31';

-- Records from current month
SELECT * FROM events
WHERE DATE_TRUNC('month', created_at) = DATE_TRUNC('month', CURRENT_DATE);
```

### Date Aggregations

```sql
-- Group by day
SELECT
    DATE_TRUNC('day', created_at) AS day,
    COUNT(*)
FROM events
GROUP BY day
ORDER BY day DESC;

-- Group by hour of day
SELECT
    EXTRACT(HOUR FROM created_at) AS hour,
    COUNT(*)
FROM events
GROUP BY hour
ORDER BY hour;
```

## Performance Tuning Queries

### Cache Hit Ratio

```sql
SELECT
    sum(heap_blks_read) AS heap_read,
    sum(heap_blks_hit) AS heap_hit,
    ROUND(sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0) * 100, 2) AS hit_ratio
FROM pg_statio_user_tables;
```

### Index Hit Ratio

```sql
SELECT
    sum(idx_blks_read) AS idx_read,
    sum(idx_blks_hit) AS idx_hit,
    ROUND(sum(idx_blks_hit) / NULLIF(sum(idx_blks_hit) + sum(idx_blks_read), 0) * 100, 2) AS hit_ratio
FROM pg_statio_user_indexes;
```

### Unused Indexes

```sql
SELECT
    indexrelname AS index_name,
    relname AS table_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan AS times_used
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;
```

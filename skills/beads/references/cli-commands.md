# Beads CLI Reference

Source: https://github.com/steveyegge/beads
CLI commands for the `bd` tool (run `bd version` to see your installed version)

## Installation

```bash
brew install beads          # macOS/Linux — recommended (verified checksums)
npm install -g @beads/bd    # npm
go install github.com/steveyegge/beads/cmd/bd@latest  # Go
```

## Global Flags (apply to every command)

| Flag | Description |
|------|-------------|
| `--db string` | Database path (default: auto-discover `.beads/*.db` in CWD) |
| `--json` | Output in JSON format (preferred for agent use) |
| `-q, --quiet` | Suppress non-essential output |
| `-v, --verbose` | Enable debug output |
| `--readonly` | Block all write operations |
| `--sandbox` | Disable auto-sync |
| `--actor string` | Override actor name in audit trail |

## Setup & Initialization

```bash
bd init                          # Initialize in current directory
bd init -p myprefix              # Custom issue prefix
bd init --stealth                # Stealth: adds .beads/ to .git/info/exclude
bd setup claude                  # Install Claude integration (writes CLAUDE.md snippet)
bd setup claude --stealth        # Claude integration without committing beads files
bd setup --list                  # List all available editor integrations
bd where                         # Show active database location
bd prime                         # Output AI-optimized workflow context (use at session start)
bd onboard                       # Show minimal AGENTS.md snippet
bd info                          # Show database info and statistics
bd status                        # Overview and statistics
```

## Working with Issues

```bash
# Create
bd create "Title"                # Create issue
bd create "Title" -p 0           # With priority (0 = highest)
bd create "Title" -d "desc"      # With description
bd create "Title" --deps bd-a1b2 # With dependency
bd q "Title"                     # Quick capture — outputs only the new ID
bd todo add "Task"               # Create a TODO task

# List & Search
bd list                          # All issues
bd list --json                   # JSON output
bd ready                         # Unblocked open issues (what to work on)
bd blocked                       # Issues that are blocked
bd search "query"                # Text search
bd query "type=bug"              # Filter with query language
bd stale                         # Issues not updated recently

# View
bd show bd-a1b2                  # Issue details
bd show bd-a1b2 --json           # JSON output
bd history bd-a1b2               # Version history (requires Dolt)

# Update
bd update bd-a1b2 --claim        # Atomically claim (assignee + in_progress)
bd update bd-a1b2 --status done  # Set status
bd update bd-a1b2 --status in_progress
bd update bd-a1b2 --status open
bd close bd-a1b2                 # Close issue
bd reopen bd-a1b2                # Reopen issue
bd defer bd-a1b2 +2d             # Defer (hide from bd ready) until date
bd undefer bd-a1b2               # Remove deferral

# Dependencies
bd dep add <child-id> <parent-id>   # child is blocked by parent
bd graph                            # Show dependency graph

# Relationships
bd duplicate bd-a1b2 bd-c3d4    # Mark as duplicate of another
bd supersede bd-a1b2 bd-c3d4    # Mark as superseded by another
```

## Epics & Structure

```bash
bd epic                          # Epic management
bd swarm                         # Swarm management for structured epics
bd children bd-a1b2              # List child issues of a parent
```

## Maintenance (Destructive — Confirm Before Running)

```bash
bd delete bd-a1b2                # Delete an issue
bd gc                            # Decay old issues + compact Dolt + run Dolt GC
bd purge                         # Delete closed ephemeral issues
bd compact                       # Squash old Dolt commits
bd flatten                       # Squash all Dolt history to single commit
```

## Sync & Data

```bash
bd export                        # Export issues to JSONL
bd backup                        # Backup database
bd branch                        # List/create branches (Dolt)
bd vc                            # Version control operations (Dolt)
```

## Issue Status Values

| Status | Meaning |
|--------|---------|
| `open` | Not started |
| `in_progress` | Being worked on |
| `done` | Completed |

## Priority

Lower number = higher priority. `0` is the highest priority.

## Task ID Format

| Format | Meaning |
|--------|---------|
| `bd-a1b2` | Top-level task or epic |
| `bd-a1b2.1` | Sub-task |
| `bd-a1b2.1.1` | Sub-sub-task |

## Dolt (Database Backend)

Dolt is bundled with beads and its server is **auto-started transparently** — no manual management needed.

```bash
bd dolt status    # check server state
bd dolt start     # start explicitly if needed
bd dolt stop      # stop the server
bd dolt show      # show config + connection test
bd doctor         # full health check
```

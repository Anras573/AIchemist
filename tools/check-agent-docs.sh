#!/usr/bin/env bash
#
# check-agent-docs.sh
#
# CI contract: every agent file in `agents/*.agent.md` must be referenced
# by filename in `docs/agents.md`. Enforces the convention that each
# documented agent section includes a Source link pointing back at the
# source file — this gives readers click-through navigation and gives
# CI a trivial check target.
#
# Exit 0 if all agents are documented; exit 1 with a structured error
# message otherwise.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
readonly AGENTS_DIR="$REPO_ROOT/agents"
readonly DOCS_FILE="$REPO_ROOT/docs/agents.md"

if [ ! -d "$AGENTS_DIR" ]; then
  echo "::error::agents/ directory not found at $AGENTS_DIR"
  exit 1
fi

if [ ! -f "$DOCS_FILE" ]; then
  echo "::error::docs/agents.md not found at $DOCS_FILE"
  exit 1
fi

# Forward check: every agent file must be referenced via the Source-link
# convention in docs. Use fixed-string match (-F) so `.` in filenames
# isn't interpreted as regex-any-char, and match the FULL markdown link
# — both the display text `[\`agents/<file>\`]` AND the target
# `(../agents/<file>)` — so a broken link target (or an incidental
# filename mention in prose) doesn't satisfy the contract.
#
# Portability: uses plain find | sort (not -print0/-z) because `sort -z`
# is GNU-only and fails on stock macOS/BSD. Agent filenames are
# controlled by convention (slug-like, no spaces or newlines), so
# line-delimited iteration is safe.
missing=()
while IFS= read -r agent_file; do
  [ -z "$agent_file" ] && continue
  base=$(basename "$agent_file")
  if ! grep -F -q '**Source:** [`agents/'"$base"'`](../agents/'"$base"')' "$DOCS_FILE"; then
    missing+=("$base")
  fi
done < <(find "$AGENTS_DIR" -maxdepth 1 -name "*.agent.md" -type f | sort)

if [ ${#missing[@]} -gt 0 ]; then
  echo "::error title=Missing agent documentation::docs/agents.md is missing entries for ${#missing[@]} agent(s)."
  {
    echo ""
    echo "The following agents have source files but no reference in docs/agents.md:"
    for m in "${missing[@]}"; do
      echo "  - agents/$m"
    done
    echo ""
    echo "Fix: add a section in docs/agents.md that references each missing file, e.g."
    echo ""
    echo "    ## My Agent"
    echo ""
    echo "    **Source:** [\`agents/my.agent.md\`](../agents/my.agent.md)"
    echo ""
    echo "    <description>"
  } >&2
  exit 1
fi

# Reverse check: every agent filename mentioned in docs must correspond to
# a real file (catches orphans after renames / deletes).
orphaned=()
while IFS= read -r referenced; do
  [ -z "$referenced" ] && continue
  if [ ! -f "$AGENTS_DIR/$referenced" ]; then
    orphaned+=("$referenced")
  fi
done < <(grep -oE '[a-zA-Z0-9_-]+\.agent\.md' "$DOCS_FILE" | sort -u)

if [ ${#orphaned[@]} -gt 0 ]; then
  echo "::error title=Orphaned agent references::docs/agents.md references ${#orphaned[@]} agent file(s) that do not exist."
  {
    echo ""
    echo "The following references in docs/agents.md point to nonexistent files:"
    for o in "${orphaned[@]}"; do
      echo "  - agents/$o"
    done
    echo ""
    echo "Fix: remove or update the stale references in docs/agents.md."
  } >&2
  exit 1
fi

agent_count=$(find "$AGENTS_DIR" -maxdepth 1 -name "*.agent.md" -type f | wc -l | tr -d ' ')
echo "✓ All $agent_count agent(s) in agents/*.agent.md are documented in docs/agents.md"

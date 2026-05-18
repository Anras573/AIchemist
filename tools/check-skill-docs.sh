#!/usr/bin/env bash
#
# check-skill-docs.sh
#
# CI contract: every skill definition in `skills/*/SKILL.md` must be
# referenced by path in `docs/skills.md` using the Source-link convention.
# This keeps docs discoverable and lets CI validate references with simple,
# deterministic matching.
#
# Exit 0 if all skills are documented; exit 1 with a structured error
# message otherwise.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
readonly SKILLS_DIR="$REPO_ROOT/skills"
readonly DOCS_FILE="$REPO_ROOT/docs/skills.md"

if [ ! -d "$SKILLS_DIR" ]; then
  echo "::error::skills/ directory not found at $SKILLS_DIR"
  exit 1
fi

if [ ! -f "$DOCS_FILE" ]; then
  echo "::error::docs/skills.md not found at $DOCS_FILE"
  exit 1
fi

# Forward check: every SKILL.md file must be referenced via Source link in docs.
missing=()
while IFS= read -r skill_file; do
  [ -z "$skill_file" ] && continue
  rel_path="skills/${skill_file#"$SKILLS_DIR"/}"
  if ! grep -F -q '**Source:** [`'"$rel_path"'`](../'"$rel_path"')' "$DOCS_FILE"; then
    missing+=("$rel_path")
  fi
done < <(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -path "*/SKILL.md" -type f | sort)

if [ ${#missing[@]} -gt 0 ]; then
  echo "::error title=Missing skill documentation::docs/skills.md is missing entries for ${#missing[@]} skill file(s)."
  {
    echo ""
    echo "The following skill files have no Source reference in docs/skills.md:"
    for m in "${missing[@]}"; do
      echo "  - $m"
    done
    echo ""
    echo "Fix: add a section in docs/skills.md that references each missing file, e.g."
    echo ""
    echo "    ## My Skill"
    echo ""
    echo "    **Source:** [\`skills/my-skill/SKILL.md\`](../skills/my-skill/SKILL.md)"
    echo ""
    echo "    <description>"
  } >&2
  exit 1
fi

# Reverse check: every referenced SKILL.md path in docs must exist.
orphaned=()
while IFS= read -r referenced; do
  [ -z "$referenced" ] && continue
  if [ ! -f "$REPO_ROOT/$referenced" ]; then
    orphaned+=("$referenced")
  fi
done < <(grep -oE 'skills/[a-zA-Z0-9_-]+/SKILL\.md' "$DOCS_FILE" | sort -u)

if [ ${#orphaned[@]} -gt 0 ]; then
  echo "::error title=Orphaned skill references::docs/skills.md references ${#orphaned[@]} skill file(s) that do not exist."
  {
    echo ""
    echo "The following references in docs/skills.md point to nonexistent files:"
    for o in "${orphaned[@]}"; do
      echo "  - $o"
    done
    echo ""
    echo "Fix: remove or update the stale references in docs/skills.md."
  } >&2
  exit 1
fi

skill_count=$(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -path "*/SKILL.md" -type f | wc -l | tr -d ' ')
echo "✓ All $skill_count skill(s) in skills/*/SKILL.md are documented in docs/skills.md"

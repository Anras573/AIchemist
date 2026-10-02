#!/usr/bin/env bash
# Resolve the beads (bd) database for a repository and print the path to pass
# as `bd --db`. Shared by the beads skill and the beads-band mod, so both pick
# the same database.
#
# Usage:
#   beads-db.sh [--init] [--repo DIR]
#
#   --repo DIR  Repository to resolve for (default: the git root of the current
#               directory, or the current directory outside a git repository)
#   --init      Create a sidecar database when none exists yet. Without it the
#               script never writes anything.
#
# Resolution order:
#   1. In-repo:  <repo>/.beads, when the repo has initialized beads itself
#   2. Sidecar:  $AICHEMIST_BEADS_HOME/<repo-name>/.beads
#                (default: ${XDG_DATA_HOME:-~/.local/share}/aichemist/beads)
#   3. Legacy:   ~/.beads/<repo-name>/.beads, from before bd 1.x. bd now keeps
#                its own state in ~/.beads and refuses to init inside it, so new
#                sidecars are never created there.
#
# Exit status: 0 with the path on stdout; 3 when there is no database and
# --init was not given; 1 on any other error. Notes go to stderr.

set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }

init=0
repo=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --init) init=1; shift ;;
    --repo) [[ $# -ge 2 ]] || die "--repo requires a value"; repo="$2"; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

if [[ -n "$repo" ]]; then
  [[ -d "$repo" ]] || die "Not a directory: $repo"
  if ! repo_root=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null); then
    repo_root=$(cd "$repo" && pwd -P)
  fi
elif ! repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
  repo_root=$(pwd -P)
fi
repo_name=$(basename "$repo_root")

# An initialized .beads holds metadata.json (bd 1.x) or a .db file (older bd).
is_beads_dir() {
  [[ -f "$1/metadata.json" ]] || compgen -G "$1/*.db" >/dev/null
}

# 1. In-repo
if is_beads_dir "$repo_root/.beads"; then
  echo "beads: using in-repo storage ($repo_root/.beads)" >&2
  echo "$repo_root/.beads"
  exit 0
fi

# Picks <root>/<repo-name>, or <root>/<repo-name>-<parent-dir> when the first
# belongs to a different repository (its .beads-repo-path marker says another
# path, or is missing). Prints the directory; does not create it.
sidecar_dir() {
  local root="$1" dir="$1/$repo_name"
  if [[ -e "$dir" ]] && [[ "$(cat "$dir/.beads-repo-path" 2>/dev/null)" != "$repo_root" ]]; then
    dir="$root/$repo_name-$(basename "$(dirname "$repo_root")")"
  fi
  echo "$dir"
}

sidecar_root="${AICHEMIST_BEADS_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/aichemist/beads}"
sidecar=$(sidecar_dir "$sidecar_root")

# 2. Sidecar
if is_beads_dir "$sidecar/.beads"; then
  echo "beads: using sidecar storage ($sidecar)" >&2
  echo "$sidecar/.beads"
  exit 0
fi

# 3. Legacy sidecar
legacy=$(sidecar_dir "$HOME/.beads")
if is_beads_dir "$legacy/.beads"; then
  echo "beads: using legacy sidecar storage ($legacy); new sidecars live under $sidecar_root" >&2
  echo "$legacy/.beads"
  exit 0
fi

if [[ "$init" -ne 1 ]]; then
  echo "beads: no database for $repo_root (run with --init to create a sidecar)" >&2
  exit 3
fi

command -v bd >/dev/null 2>&1 || die "bd is not installed. See https://github.com/steveyegge/beads#installation"

mkdir -p "$sidecar"
# Agents and hooks are skipped: the sidecar is not a repository anyone works in.
if ! (cd "$sidecar" && bd init -p "$repo_name" -q --skip-agents --skip-hooks --non-interactive >/dev/null); then
  die "failed to initialize a beads sidecar at $sidecar"
fi
echo "$repo_root" > "$sidecar/.beads-repo-path"
is_beads_dir "$sidecar/.beads" || die "bd init finished but $sidecar/.beads holds no database"

echo "beads: initialized sidecar storage ($sidecar)" >&2
echo "$sidecar/.beads"

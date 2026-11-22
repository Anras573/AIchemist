#!/usr/bin/env bash
#
# commit-gate.sh
#
# PreToolUse hook (matcher: Bash). Before the agent runs `git commit` or
# `git push`, makes sure the project builds, its tests pass and its formatting
# is clean. Blocks the command (exit 2, report on stderr) when a step fails so
# the agent has to fix the problem first.
#
# Language support is auto-detected from files in the repo root:
#   Node (npm/pnpm/yarn/bun), Python, Go, Rust, .NET, Maven, Gradle, Makefile.
# Formatting is only ever *checked* here, never applied, so the hook cannot
# change files underneath a commit. The report says how to fix a failure.
#
# Configuration (environment variables, e.g. via "env" in settings.json):
#   AICHEMIST_GATE_SKIP=1        disable the gate entirely
#   AICHEMIST_GATE_BUILD=<cmd>   replace the detected build step ("" = skip it)
#   AICHEMIST_GATE_TEST=<cmd>    replace the detected test step   ("" = skip it)
#   AICHEMIST_GATE_FORMAT=<cmd>  replace the detected format step ("" = skip it)
#
# A successful run is cached per working-tree content, so `git commit`
# followed by `git push` does not run everything twice.
#
# Fail-open: anything unexpected (no git, no python3, unknown project type,
# missing toolchain) lets the command through. Only a real failing check blocks.

set -u

[ "${AICHEMIST_GATE_SKIP:-0}" = "1" ] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# --- Parse hook input -------------------------------------------------------

input=$(cat)
parsed=$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = d.get("tool_input") or {}
print(d.get("cwd") or "")
print((ti.get("command") or "").replace("\n", " ; "))
' 2>/dev/null) || exit 0

cwd=$(printf '%s\n' "$parsed" | sed -n '1p')
cmd=$(printf '%s\n' "$parsed" | sed -n '2p')
[ -n "$cmd" ] || exit 0

# Only `git commit` / `git push`, allowing global options (-C path, -c k=v).
git_re='(^|[;&|(]|[[:space:]])git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+|[[:space:]]+--[a-z-]+(=[^[:space:]]+)?)*[[:space:]]+(commit|push)([[:space:]]|$)'
[[ "$cmd" =~ $git_re ]] || exit 0
[[ "$cmd" == *--dry-run* ]] && exit 0

[ -n "$cwd" ] && cd "$cwd" 2>/dev/null
if ! repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
  exit 0
fi
cd "$repo_root" || exit 0

# --- Cache: skip when this exact working tree already passed ---------------

git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || exit 0
cache_file="$git_dir/aichemist-gate-ok"

tree_hash() {
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/gate-index-XXXXXX") || return 1
  # An empty file is a corrupt index; start from a missing one instead.
  if [ -f "$git_dir/index" ]; then cp "$git_dir/index" "$tmp"; else rm -f "$tmp"; fi
  GIT_INDEX_FILE="$tmp" git add -A >/dev/null 2>&1
  GIT_INDEX_FILE="$tmp" git write-tree 2>/dev/null
  rm -f "$tmp"
}

current_hash=$(tree_hash) || current_hash=""
if [ -n "$current_hash" ] && [ -f "$cache_file" ] && [ "$(cat "$cache_file" 2>/dev/null)" = "$current_hash" ]; then
  exit 0
fi

# --- Step detection ---------------------------------------------------------

STEP_LABELS=()
STEP_KINDS=()
STEP_CMDS=()
SKIPPED=()

add_step() { # kind label cmd
  STEP_KINDS+=("$1"); STEP_LABELS+=("$2"); STEP_CMDS+=("$3")
}

have() { command -v "$1" >/dev/null 2>&1; }

pkg_script() { # name -> 0 when package.json defines scripts.<name>
  python3 - "$1" <<'PY' 2>/dev/null
import json, sys
try:
    s = json.load(open("package.json")).get("scripts") or {}
except Exception:
    sys.exit(1)
sys.exit(0 if sys.argv[1] in s else 1)
PY
}

pkg_dep() { # name -> 0 when listed in (dev)dependencies
  python3 - "$1" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open("package.json"))
except Exception:
    sys.exit(1)
deps = {}
deps.update(d.get("dependencies") or {})
deps.update(d.get("devDependencies") or {})
sys.exit(0 if sys.argv[1] in deps else 1)
PY
}

make_target() { # name -> 0 when Makefile defines the target
  local mf
  for mf in Makefile makefile GNUmakefile; do
    [ -f "$mf" ] && grep -Eq "^$1[[:space:]]*:" "$mf" && return 0
  done
  return 1
}

detect_node() {
  [ -f package.json ] || return 0
  local pm=npm run exec_
  if [ -f pnpm-lock.yaml ]; then pm=pnpm
  elif [ -f yarn.lock ]; then pm=yarn
  elif [ -f bun.lockb ] || [ -f bun.lock ]; then pm=bun
  fi
  if ! have "$pm"; then SKIPPED+=("node: $pm not installed"); return 0; fi
  case "$pm" in
    npm) run="npm run --silent"; exec_="npx --no-install" ;;
    *)   run="$pm run"; exec_="$pm exec" ;;
  esac
  [ -d node_modules ] || { SKIPPED+=("node: node_modules missing (run $pm install)"); return 0; }

  pkg_script build && add_step build "node build" "$run build"
  if pkg_script test; then
    # `npm init` default is a placeholder that always fails; ignore it.
    grep -q 'no test specified' package.json || add_step test "node test" "$pm test"
  fi
  local s
  for s in format:check fmt:check check-format prettier:check format-check; do
    if pkg_script "$s"; then add_step format "node format ($s)" "$run $s"; return 0; fi
  done
  if pkg_dep prettier; then add_step format "prettier --check" "$exec_ prettier --check ."
  elif pkg_dep @biomejs/biome; then add_step format "biome format" "$exec_ biome format ."
  fi
}

detect_python() {
  [ -f pyproject.toml ] || [ -f setup.py ] || [ -f setup.cfg ] || [ -f requirements.txt ] || [ -f pytest.ini ] || return 0
  local py=python3
  have python3 || return 0
  if have pytest; then add_step test "pytest" "pytest -q"
  elif $py -c 'import pytest' 2>/dev/null; then add_step test "pytest" "$py -m pytest -q"
  fi
  if have ruff; then add_step format "ruff format --check" "ruff format --check ."
  elif have black; then add_step format "black --check" "black --check ."
  fi
}

detect_go() {
  [ -f go.mod ] || return 0
  have go || { SKIPPED+=("go: not installed"); return 0; }
  add_step build "go build" "go build ./..."
  add_step test "go test" "go test ./..."
  add_step format "gofmt" 'out=$(gofmt -l .); [ -z "$out" ] || { echo "Unformatted files:"; echo "$out"; echo "Fix with: gofmt -w ."; exit 1; }'
}

detect_rust() {
  [ -f Cargo.toml ] || return 0
  have cargo || { SKIPPED+=("rust: cargo not installed"); return 0; }
  add_step build "cargo build" "cargo build --quiet"
  add_step test "cargo test" "cargo test --quiet"
  add_step format "cargo fmt --check" "cargo fmt --check"
}

detect_dotnet() {
  local f
  f=$(find . -maxdepth 2 \( -name '*.sln' -o -name '*.slnx' -o -name '*.csproj' -o -name '*.fsproj' \) -not -path './node_modules/*' 2>/dev/null | head -n1)
  [ -n "$f" ] || return 0
  have dotnet || { SKIPPED+=("dotnet: not installed"); return 0; }
  add_step build ".NET build" "dotnet build --nologo -v q"
  add_step test ".NET test" "dotnet test --nologo -v q"
  add_step format ".NET format" "dotnet format --verify-no-changes"
}

detect_jvm() {
  if [ -f pom.xml ]; then
    local mvn=mvn
    [ -x ./mvnw ] && mvn=./mvnw
    have "$mvn" || [ "$mvn" = ./mvnw ] || { SKIPPED+=("maven: not installed"); return 0; }
    add_step build "maven compile" "$mvn -q -B compile"
    add_step test "maven test" "$mvn -q -B test"
  elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
    local g=gradle
    [ -x ./gradlew ] && g=./gradlew
    have "$g" || [ "$g" = ./gradlew ] || { SKIPPED+=("gradle: not installed"); return 0; }
    add_step build "gradle build" "$g build -x test -q"
    add_step test "gradle test" "$g test -q"
  fi
}

detect_make() {
  # Only fills steps no language detector already provided.
  have make || return 0
  local k t target
  for k in build test format; do
    case " ${STEP_KINDS[*]:-} " in *" $k "*) continue ;; esac
    case "$k" in
      build) set -- build ;;
      test) set -- test check ;;
      format) set -- format-check fmt-check check-format lint-format ;;
    esac
    for t in "$@"; do
      if make_target "$t"; then add_step "$k" "make $t" "make --no-print-directory $t"; break; fi
    done
  done
}

apply_override() { # kind ENVVAR
  local kind="$1" var="$2" i
  [ "${!var+x}" = x ] || return 0
  # Drop detected steps of this kind, then add the override (when non-empty).
  local nl=() nk=() nc=()
  for i in "${!STEP_KINDS[@]}"; do
    [ "${STEP_KINDS[$i]}" = "$kind" ] && continue
    nl+=("${STEP_LABELS[$i]}"); nk+=("${STEP_KINDS[$i]}"); nc+=("${STEP_CMDS[$i]}")
  done
  STEP_LABELS=("${nl[@]+"${nl[@]}"}"); STEP_KINDS=("${nk[@]+"${nk[@]}"}"); STEP_CMDS=("${nc[@]+"${nc[@]}"}")
  [ -n "${!var}" ] && add_step "$kind" "$kind (custom)" "${!var}"
  return 0
}

detect_node; detect_python; detect_go; detect_rust; detect_dotnet; detect_jvm; detect_make
apply_override build AICHEMIST_GATE_BUILD
apply_override test AICHEMIST_GATE_TEST
apply_override format AICHEMIST_GATE_FORMAT

if [ "${#STEP_CMDS[@]}" -eq 0 ]; then
  exit 0
fi

# --- Run the steps in order: build, test, format ----------------------------

failures=0
report=""
for kind in build test format; do
  for i in "${!STEP_KINDS[@]}"; do
    [ "${STEP_KINDS[$i]}" = "$kind" ] || continue
    log=$(mktemp "${TMPDIR:-/tmp}/gate-log-XXXXXX") || continue
    if bash -c "${STEP_CMDS[$i]}" >"$log" 2>&1 </dev/null; then
      :
    else
      failures=$((failures + 1))
      report+=$'\n'"✗ ${kind}: ${STEP_LABELS[$i]}  (\`${STEP_CMDS[$i]}\`)"$'\n'
      report+="$(tail -n 40 "$log" | sed 's/^/    /')"$'\n'
    fi
    rm -f "$log"
  done
done

if [ "$failures" -gt 0 ]; then
  {
    echo "Blocked: pre-commit checks failed ($failures step(s)). Fix these, then retry the git command."
    printf '%s' "$report"
    [ "${#SKIPPED[@]}" -gt 0 ] && printf 'Skipped: %s\n' "${SKIPPED[*]}"
    echo "(Set AICHEMIST_GATE_SKIP=1 to bypass this gate.)"
  } >&2
  exit 2
fi

[ -n "$current_hash" ] && printf '%s\n' "$current_hash" >"$cache_file" 2>/dev/null
exit 0

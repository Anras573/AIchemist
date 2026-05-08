#!/usr/bin/env bash
#
# skill-suggester.sh
#
# Hook script for PreCompact and SessionEnd events. Mines the current session
# transcript for patterns that could become reusable skills, agents, or hooks,
# and appends markdown bullet entries (top-level bullet plus _evidence_
# and _observed_ sub-bullets) to "AIchemist/Skill Ideas.md" in the user's
# Obsidian vault.
#
# Best-effort: any failure exits 0 silently to avoid breaking the session.

set -u

# DRY_RUN is read-only once captured below, but we need its value up front
# to decide whether the `obsidian` CLI dep is actually required. Default to
# "0" so the normal hook path still requires obsidian.
readonly DRY_RUN="${DRY_RUN:-0}"

# Always-required deps for the detection pipeline.
for cmd in jq awk sort python3; do
  command -v "$cmd" >/dev/null 2>&1 || exit 0
done

# obsidian CLI is only required for actual note I/O. DRY_RUN=1 prints the
# intended writes to stdout without shelling out, so contributors can test
# the detection logic on machines or CI envs without Obsidian installed.
if [ "$DRY_RUN" != "1" ]; then
  command -v obsidian >/dev/null 2>&1 || exit 0
fi

# claude CLI is optional (only needed for the semantic fallback).
HAS_CLAUDE=0
command -v claude >/dev/null 2>&1 && HAS_CLAUDE=1

# ----- Config --------------------------------------------------------------

readonly PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
readonly NOTE_PATH="AIchemist/Skill Ideas.md"
readonly TOOL_SEQ_LEN=3
readonly TOOL_REPEAT_MIN=2
readonly NGRAM_SIZE=4
readonly NGRAM_REPEAT_MIN=2
readonly SESSION_GATE=20
readonly MAX_SUGGESTIONS=3
readonly MIN_TRANSCRIPT_LINES=10
readonly CLAUDE_OUTPUT_MAX=32768

# DRY_RUN was made readonly at the top of the script (before the obsidian
# dep check). is_dry_run is defined here so the Config section stays
# self-contained for callers.
is_dry_run() { [ "$DRY_RUN" = "1" ]; }

readonly EXCLUDED_TOOLS_REGEX='^(Read|TodoWrite|TaskCreate|TaskUpdate|TaskList|TaskGet|TaskOutput|TaskStop|AskUserQuestion|EnterPlanMode|ExitPlanMode|EnterWorktree|ExitWorktree|ScheduleWakeup|Monitor)$'

# ----- Vault resolution (runs BEFORE stdin I/O) ----------------------------

# Capture the SYSTEM tmpdir before we shadow TMPDIR with our per-invocation
# mktemp path. The write-phase lock must live in a path shared across all
# hook invocations of the same user — NOT inside our per-process mktemp
# dir (which is what the previous lock inadvertently did, making every
# invocation acquire its own uncontested lock and defeating the purpose).
readonly SYSTEM_TMPDIR="${TMPDIR:-/tmp}"

resolve_vault() {
  local vault=""
  local config="$PLUGIN_ROOT/config.json"

  if [ -f "$config" ]; then
    vault=$(jq -r '.obsidian.preferredVault // empty' "$config" 2>/dev/null)
  fi

  [ -z "$vault" ] && vault="${OBSIDIAN_VAULT:-}"

  # NOTE: no auto-pick, even for single-vault setups. Per the repo's
  # "Explicit over implicit" rule, a hook that persists content to a
  # long-lived note in the user's vault must be explicitly enabled.
  # Auto-picking "whichever vault exists" would start writing to a
  # fresh install the first time a session ends — the user never had
  # a chance to consent. If `preferredVault` isn't set in config.json
  # and `$OBSIDIAN_VAULT` isn't in the environment, return empty and
  # silently skip the entire hook.

  echo "$vault"
}

# Resolve the vault FIRST — before we create a tmpdir or consume stdin.
# The docs now recommend "don't configure a vault" as the disable path,
# which makes this the common case for users who haven't opted in. We
# want the disabled path to be cheap: one small config.json read, maybe
# one env-var check, exit. Doing the full stdin-to-tmpfile dance before
# realizing we have nothing to do would waste multi-MB of I/O on every
# PreCompact/SessionEnd for users who deliberately haven't opted in.
VAULT=$(resolve_vault)
if [ -z "$VAULT" ]; then
  if is_dry_run; then
    VAULT="<no-vault-configured>"
    echo "[DRY_RUN] no vault resolved; continuing with placeholder" >&2
  else
    exit 0
  fi
fi

# ----- Read hook input -----------------------------------------------------

# Cleanup: remove tmpdir on exit, and the write-phase lock if we acquired it.
LOCK_ACQUIRED=""
cleanup() {
  rm -rf "$TMPDIR" 2>/dev/null
  [ -n "$LOCK_ACQUIRED" ] && rm -rf "$LOCK_ACQUIRED" 2>/dev/null
}

TMPDIR=$(mktemp -d -t skill-suggester.XXXXXX) || exit 0
trap cleanup EXIT HUP INT TERM

# Stream stdin directly to a temp file instead of slurping into a shell
# variable — PreCompact transcripts can be multi-MB and doubling that in
# memory can dominate the hook's cost.
STDIN_FILE="$TMPDIR/stdin.raw"
cat > "$STDIN_FILE"
[ ! -s "$STDIN_FILE" ] && exit 0

# Hook stdin may be a JSON payload (with transcript_path) or a raw JSONL dump.
# Probe ONLY the first line: the hook payload is always a single JSON object
# on one line. Reading the whole file through jq three separate times (as an
# earlier version did) would re-parse a multi-MB PreCompact transcript on
# every probe — pure waste if the input turns out to be raw JSONL.
TRANSCRIPT=""
HOOK_EVENT="unknown"
FIRST_LINE=$(head -n1 "$STDIN_FILE")
if PAYLOAD_FIELDS=$(echo "$FIRST_LINE" | jq -r 'select(type == "object") | [(.transcript_path // ""), (.hook_event_name // "unknown")] | @tsv' 2>/dev/null) \
    && [ -n "$PAYLOAD_FIELDS" ]; then
  IFS=$'\t' read -r PATH_FIELD HOOK_EVENT <<< "$PAYLOAD_FIELDS"
  [ -n "$PATH_FIELD" ] && [ -f "$PATH_FIELD" ] && TRANSCRIPT="$PATH_FIELD"
fi
[ -z "$TRANSCRIPT" ] && TRANSCRIPT="$STDIN_FILE"

# Early gate: skip full pipeline on trivially small transcripts.
_line_count=$(wc -l < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')
[ "${_line_count:-0}" -lt "$MIN_TRANSCRIPT_LINES" ] && exit 0

# ----- Transcript parsing --------------------------------------------------

extract_tools() {
  # shellcheck disable=SC2016
  jq -r --arg excl "$EXCLUDED_TOOLS_REGEX" '
    def normalize(name; input):
      if name == "Bash" then
        (input.command // "" | split(" ") | .[0:2] | join(" ")) as $two
        | "Bash(" + $two + ")"
      elif (name | startswith("mcp__plugin_")) then
        (name | sub("^mcp__plugin_[^_]+_"; "") | sub("__"; ":"))
      else
        name
      end;

    # `[., inputs]` (not `[inputs]`) captures the first JSON value too —
    # otherwise jq discards it as the initial `.` binding, losing the first
    # tool use and skewing every reported line number by 1.
    [., inputs] as $lines
    | $lines
    | to_entries
    | map(
        .key as $i
        | .value
        | ((.message?.content? // []) | if type == "array" then . else [] end)
        | map(select(.type? == "tool_use"))
        | map({ name: normalize(.name; .input), line: ($i + 1) })
        | .[]?
      )
    | map(select(.name | test($excl) | not))
    | .[]
    | .name + "\t" + (.line | tostring)
  ' "$TRANSCRIPT" 2>/dev/null
}

# Extract user messages once, cache to msgs.tsv for reuse by
# count_user_exchanges and detect_user_ngrams.
extract_user_messages() {
  local msgs="$TMPDIR/msgs.tsv"
  if [ ! -f "$msgs" ]; then
    jq -r '
      # `[., inputs]` includes the first transcript entry; `[inputs]` alone
      # would drop it (jq binds the first value to `.` implicitly).
      [., inputs] as $lines
      | $lines
      | to_entries
      | map(
          select(
            (.value.type? == "user") or (.value.message?.role? == "user")
          )
          | {
              line: (.key + 1),
              text: (
                .value.message?.content // .value.content // ""
                | if type == "string" then .
                  elif type == "array" then
                    map(if type == "object" then (.text // "") else . end) | join(" ")
                  else ""
                  end
                # Strip Claude Code harness-injected tags so we only count
                # actual user phrasings, not slash-command metadata or
                # system reminders.
                | gsub("<system-reminder>.*?</system-reminder>"; ""; "s")
                | gsub("<local-command-stdout>.*?</local-command-stdout>"; ""; "s")
                | gsub("<local-command-caveat>.*?</local-command-caveat>"; ""; "s")
                | gsub("<command-name>.*?</command-name>"; ""; "s")
                | gsub("<command-message>.*?</command-message>"; ""; "s")
                | gsub("<command-args>.*?</command-args>"; ""; "s")
                | gsub("\\s+"; " ")
                | ascii_downcase
                # Trim leading/trailing whitespace so messages that
                # contained ONLY harness tags (and left a " " residue
                # after gsub) fail the nonempty check below rather
                # than inflating the user-exchange count with blanks.
                | gsub("^ | $"; "")
              )
            }
          | select(.text != "")
        )
      | .[]
      | "\(.line)\t\(.text)"
    ' "$TRANSCRIPT" 2>/dev/null > "$msgs"
  fi
  cat "$msgs"
}

count_user_exchanges() {
  extract_user_messages | wc -l | tr -d ' '
}

# ----- Regex detection -----------------------------------------------------

detect_tool_sequences() {
  local tools="$TMPDIR/tools.tsv"
  extract_tools > "$tools"
  [ ! -s "$tools" ] && return 0

  # The " → " separator (U+2192) must stay in sync with the Python split
  # in format_regex_suggestions — both encode the arrow the same way.
  # Count non-overlapping occurrences only: a single run of Edit→Edit→Edit→Edit
  # should count as ONE match of "Edit→Edit→Edit", not two. Greedy scan —
  # when a key matches at position i, require the next match of the same key
  # to start at position >= i+len.
  # awk associative-array iteration order is undefined, so we pipe
  # through `sort` to get a deterministic order — by first-line
  # number (column 2, numeric). Two effects: identical transcripts
  # produce identical suggestion lists across runs/platforms, and
  # patterns surface in the order they first appeared in the session
  # (chronological), which is more intuitive than alphabetic.
  awk -F'\t' -v len="$TOOL_SEQ_LEN" -v min="$TOOL_REPEAT_MIN" '
    { names[NR] = $1; lines[NR] = $2 }
    END {
      for (i = 1; i <= NR - len + 1; i++) {
        key = names[i]
        for (j = 1; j < len; j++) key = key " \xe2\x86\x92 " names[i+j]
        if (!(key in last_start) || i >= last_start[key] + len) {
          count[key]++
          last_start[key] = i
          if (!(key in first_line)) first_line[key] = lines[i]
        }
      }
      for (k in count) {
        if (count[k] >= min) print k "\t" first_line[k]
      }
    }
  ' "$tools" | sort -t $'\t' -k2n
}

detect_user_ngrams() {
  local msgs="$TMPDIR/msgs.tsv"
  extract_user_messages > /dev/null  # ensure cache populated
  [ ! -s "$msgs" ] && return 0

  # Non-overlapping count: a repeated phrase within one message ("the the
  # the the the" with n=4) counts as one occurrence, not two. Across
  # messages we always count separately since positions reset each record.
  # Deterministic order via external sort — see detect_tool_sequences
  # for the same pattern and reasoning.
  awk -F'\t' -v n="$NGRAM_SIZE" -v min="$NGRAM_REPEAT_MIN" '
    {
      line = $1
      nwords = split($2, w, /[[:space:]]+/)
      for (i = 1; i <= nwords - n + 1; i++) {
        key = ""
        for (j = 0; j < n; j++) key = key (j ? " " : "") w[i+j]
        if (!(key in last_nr) || last_nr[key] != NR || i >= last_pos[key] + n) {
          count[key]++
          last_nr[key] = NR
          last_pos[key] = i
          if (!(key in first_line)) first_line[key] = line
        }
      }
    }
    END {
      for (k in count) {
        if (count[k] >= min) print k "\t" first_line[k]
      }
    }
  ' "$msgs" | sort -t $'\t' -k2n
}

# ----- Format regex hits as suggestions JSON -------------------------------

format_regex_suggestions() {
  local seqs="$TMPDIR/seqs.tsv"
  local ngrams="$TMPDIR/ngrams.tsv"
  detect_tool_sequences > "$seqs"
  detect_user_ngrams > "$ngrams"

  python3 - "$seqs" "$ngrams" "$MAX_SUGGESTIONS" <<'PY' 2>/dev/null || echo "[]"
import json, sys, re

seq_path, ngram_path, cap = sys.argv[1], sys.argv[2], int(sys.argv[3])
out = []

def slug(s):
    # Cap at 28 so that even with the "workflow-" prefix (9 chars) we stay
    # safely under redact_snippet's 40-char length threshold — otherwise
    # legitimate long slugs collide on [REDACTED-LONG].
    s = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
    return s[:28] or "pattern"

with open(seq_path) as f:
    for line in f:
        if len(out) >= cap: break
        line = line.rstrip("\n")
        if not line: continue
        seq, _, lineno = line.rpartition("\t")
        # Slug the FULL sequence so two workflows that happen to start
        # with the same tool (e.g. Edit→Bash(git add)→Edit vs
        # Edit→Bash(git status)→Edit) get distinct names.
        out.append({
            "kind": "skill",
            "name": "workflow-" + slug(seq),
            "one_liner": f"Repeated tool workflow: {seq}",
            "evidence_line": int(lineno) if lineno.isdigit() else 0,
            "evidence_snippet": seq,
        })

with open(ngram_path) as f:
    for line in f:
        if len(out) >= cap: break
        line = line.rstrip("\n")
        if not line: continue
        phrase, _, lineno = line.rpartition("\t")
        out.append({
            "kind": "skill",
            "name": slug(phrase),
            "one_liner": f"Recurring user phrasing: \"{phrase}\"",
            "evidence_line": int(lineno) if lineno.isdigit() else 0,
            "evidence_snippet": phrase,
        })

print(json.dumps(out))
PY
}

# ----- Claude semantic fallback --------------------------------------------

# Extracts the `name:` frontmatter field from each matching file passed as
# an argument. Callers pass filenames via shell glob expansion so no
# reliance on `find`'s extensions — works identically on BSD and GNU.
list_existing() {
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    awk -F': *' '/^name:/ { gsub(/[[:space:]]+$/, "", $2); print $2; exit }' "$f"
  done | sort -u
}

invoke_claude_fallback() {
  [ "$HAS_CLAUDE" = "1" ] || { echo "[]"; return; }

  local skills agents transcript_snippet
  # Glob expansion happens at call time in the current shell. If no files
  # match, the literal glob string is passed and `[ -f "$f" ]` filters it.
  skills=$(list_existing "$PLUGIN_ROOT"/skills/*/SKILL.md | paste -sd, -)
  agents=$(list_existing "$PLUGIN_ROOT"/agents/*.agent.md | paste -sd, -)
  transcript_snippet=$(tail -n 400 "$TRANSCRIPT")

  local prompt_file="$TMPDIR/prompt.txt"
  cat > "$prompt_file" <<EOF
You are analyzing a Claude Code session transcript for patterns that could
become reusable automations. The user already has:

  SKILLS: $skills
  AGENTS: $agents
  EXISTING HOOK PURPOSES:
    - Desktop notification on session idle
    - Mining session transcripts into mempalace memory
    - Mining sessions for skill suggestions

Find up to $MAX_SUGGESTIONS patterns NOT already covered above. A pattern qualifies
only if it appears 2+ times in the transcript OR the user explicitly describes
it as a habitual workflow.

Look for:
1. Repeated tool-call sequences of 3+ steps that accomplish a coherent sub-goal.
   Regex has already caught exact repeats — you find fuzzy ones.
2. Repeated user phrasings that mean the same thing semantically.
3. Multi-step process descriptions the user typed out.

For each pattern, classify as ONE of:
- "skill": a named recipe the user invokes by command
- "agent": a specialized expertise/role that other code delegates to
- "hook": a deterministic side effect triggered by a tool event

Decision rule:
- User describes a fixed sequence ("first X then Y then Z") → skill
- User asks Claude to adopt a role ("review as security expert") → agent
- Side effect always following a tool event, no reasoning → hook

Do NOT suggest:
- Patterns covered by existing skills/agents (including by role overlap)
- Meta-automations ("summarize session", "remember context")
- Single-occurrence patterns
- Skills that would be one bash command

Output ONLY a JSON array, no prose. Max $MAX_SUGGESTIONS items. Return [] if nothing
qualifies; err on the side of [].

[
  {
    "kind": "skill|agent|hook",
    "name": "kebab-case-name",
    "one_liner": "What it would do in ~12 words",
    "evidence_line": 147,
    "evidence_snippet": "Brief quote from the transcript"
  }
]

--- TRANSCRIPT (tail, JSONL) ---
$transcript_snippet
EOF

  # Pipe the prompt via stdin instead of passing it as a `-p` argv
  # argument. The transcript tail can be hundreds of KB; on macOS
  # ARG_MAX is ~256KB, so argv-based invocation would silently fail
  # on exactly the long sessions this fallback path is meant to
  # analyze. `claude -p` (with no message argument) reads the prompt
  # from stdin in print mode.
  local raw json
  raw=$(claude -p --output-format text < "$prompt_file" 2>/dev/null | tr -d '\r')
  json=$(echo "$raw" | awk '/^\[/,/^\]$/' | head -c "$CLAUDE_OUTPUT_MAX")
  if echo "$json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "$json"
  else
    echo "[]"
  fi
}

# ----- Obsidian dedup + append --------------------------------------------

# Cached note contents — populated once by load_note_cache, read by
# already_in_note for each suggestion without re-fetching.
NOTE_CACHE=""

load_note_cache() {
  if is_dry_run; then
    NOTE_CACHE=""
    return 0
  fi
  NOTE_CACHE=$(obsidian vault="$VAULT" read path="$NOTE_PATH" 2>/dev/null || true)
}

already_in_note() {
  local name="$1"
  is_dry_run && return 1
  echo "$NOTE_CACHE" | grep -F -q "\`$name\`"
}

ensure_note_exists() {
  if is_dry_run; then
    echo "[DRY_RUN] would ensure $NOTE_PATH exists in vault=$VAULT" >&2
    return 0
  fi
  if ! obsidian vault="$VAULT" read path="$NOTE_PATH" >/dev/null 2>&1; then
    local header_file="$TMPDIR/header.md"
    cat > "$header_file" <<EOF
# Skill Ideas

Auto-generated by AIchemist's skill-suggester hook. Entries are patterns
observed across your Claude Code sessions that might be worth turning into
a skill, agent, or hook.

Review periodically; delete what doesn't land.

EOF
    obsidian vault="$VAULT" create path="$NOTE_PATH" content="$(cat "$header_file")" >/dev/null 2>&1 || return 1
    # Obsidian indexes files asynchronously; poll until the note is readable
    # before returning so load_note_cache and the first append don't race.
    local retries=10
    while [ "$retries" -gt 0 ]; do
      obsidian vault="$VAULT" read path="$NOTE_PATH" >/dev/null 2>&1 && return 0
      sleep 0.3
      retries=$((retries - 1))
    done
    return 1
  fi
  return 0
}

# Redact likely-secret substrings from a string before persisting it to the
# long-lived Obsidian note. Best-effort — catches common patterns (API-key
# prefixes, credential assignments, long opaque tokens) but is not a
# replacement for secret scanning.
#
# Uses python3 (already a required dep) rather than sed because BSD sed on
# macOS does not support the `/i` case-insensitive flag, and the
# credential-assignment pattern needs case-insensitive matching to catch
# both "password=" and "PASSWORD=".
redact_snippet() {
  python3 -c '
import re, sys
s = sys.argv[1]
s = re.sub(r"(sk-|xoxb-|xoxp-|ghp_|gho_|ghu_|github_pat_|AKIA|Bearer\s+)[A-Za-z0-9_./+=-]+",
           "[REDACTED-TOKEN]", s)
s = re.sub(r"(password|passwd|secret|token|api[_-]?key|access[_-]?key)(\s*[=:]\s*)\S+",
           r"\1\2[REDACTED]", s, flags=re.IGNORECASE)
s = re.sub(r"[A-Za-z0-9_+/=-]{40,}", "[REDACTED-LONG]", s)
sys.stdout.write(s)
' "$1"
}

append_suggestion() {
  local kind="$1" name="$2" one_liner="$3" line="$4" snippet="$5"
  local date_iso
  date_iso=$(date -u +"%Y-%m-%d")

  local body
  body=$(cat <<EOF
- \`$name\` ($kind): $one_liner
    - _evidence_: line $line — "$snippet"
    - _observed_: $date_iso
EOF
)
  if is_dry_run; then
    echo "--- would append to $NOTE_PATH ---"
    echo "$body"
    echo
    return 0
  fi
  obsidian vault="$VAULT" append path="$NOTE_PATH" content="$body

" >/dev/null 2>&1
}

# Best-effort mutex on the write phase: two concurrent hook invocations
# (e.g. two sessions' SessionEnd firing at once) would otherwise both load
# NOTE_CACHE before either appends, both see no entry, and both append the
# same suggestion. Uses mkdir (atomic on local fs) with PID-based stale
# detection so an orphaned lock from a killed process eventually releases.
# If the lock is held by a live process, we skip this run silently —
# consistent with the hook's best-effort contract.
acquire_write_lock() {
  # Use SYSTEM_TMPDIR (captured before TMPDIR was shadowed) so the lock
  # path is stable across all hook invocations of this user, not buried
  # inside each invocation's unique mktemp dir.
  #
  # Scope the lock BY (user, vault):
  #   - Vault: two sessions targeting different Obsidian vaults can't
  #     race since they're writing different files.
  #   - User: on Linux, $SYSTEM_TMPDIR is typically /tmp, which is
  #     shared across users. Two OS users who happen to have the same
  #     vault name would otherwise contend on the same lockdir and
  #     silently suppress each other's suggestions.
  # Sanitize both tokens into filesystem-safe strings before embedding.
  local vault_token user_token
  vault_token=$(printf '%s' "$VAULT" | tr -c 'a-zA-Z0-9' '_' | cut -c1-64)
  user_token="${UID:-nouser}"
  local lockdir="$SYSTEM_TMPDIR/aichemist-skill-suggester.${user_token}.${vault_token:-default}.lock"
  if mkdir "$lockdir" 2>/dev/null; then
    echo "$$" > "$lockdir/pid" 2>/dev/null || true
    LOCK_ACQUIRED="$lockdir"
    return 0
  fi
  # Lock held — check staleness via TWO signals:
  #   a) PID liveness: holder process actually running?
  #   b) Lock age: hook runs are short (< 1 min typically), so a lock
  #      older than 15 minutes is almost certainly orphaned — the
  #      original process crashed and its PID may have been reused
  #      by an unrelated process. PID-alive alone can't distinguish
  #      "still holding the lock" from "unrelated reused-PID process",
  #      so age is the tiebreaker.
  # `find -mmin +15` is portable across BSD and GNU find.
  local holder lock_old holder_alive=0
  holder=$(cat "$lockdir/pid" 2>/dev/null)
  [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null && holder_alive=1
  lock_old=$(find "$lockdir" -maxdepth 0 -mmin +15 2>/dev/null)
  if [ "$holder_alive" = "0" ] || [ -n "$lock_old" ]; then
    # Stale: holder is gone, or lock has been held implausibly long.
    # Break and retry once.
    rm -rf "$lockdir" 2>/dev/null
    if mkdir "$lockdir" 2>/dev/null; then
      echo "$$" > "$lockdir/pid" 2>/dev/null || true
      LOCK_ACQUIRED="$lockdir"
      return 0
    fi
  fi
  return 1
}

# ----- Main ---------------------------------------------------------------

main() {
  local suggestions
  suggestions=$(format_regex_suggestions)

  local regex_count
  regex_count=$(echo "$suggestions" | jq -r 'length' 2>/dev/null)

  # Only run the Claude semantic fallback on a known-SessionEnd event.
  # Reasoning: a session that fires both PreCompact AND SessionEnd would
  # otherwise invoke `claude -p` twice, and the non-deterministic model
  # can phrase the same workflow differently across runs — bypassing
  # name-based dedup. Strict allowlist (SessionEnd only, not a denylist
  # of PreCompact) because HOOK_EVENT is "unknown" for raw-JSONL input,
  # and a denylist would let PreCompact-as-raw-JSONL slip through.
  # Regex is deterministic and runs on all events, so PreCompact still
  # contributes regex hits.
  if [ "${regex_count:-0}" = "0" ] && [ "$HOOK_EVENT" = "SessionEnd" ]; then
    local exchanges
    exchanges=$(count_user_exchanges)
    if [ "${exchanges:-0}" -ge "$SESSION_GATE" ]; then
      suggestions=$(invoke_claude_fallback)
    fi
  fi

  local total
  total=$(echo "$suggestions" | jq -r 'length' 2>/dev/null)
  [ "${total:-0}" = "0" ] && exit 0

  # Acquire the write-phase lock BEFORE touching the note at all, so the
  # create-or-append flow is entirely inside the critical section.
  # Otherwise two concurrent runs against a missing note would both see
  # it as absent, both try to create, and the loser gets a spurious
  # failure and exits without processing any of its suggestions.
  if ! is_dry_run && ! acquire_write_lock; then
    exit 0  # another instance holds the lock; skip silently
  fi
  ensure_note_exists || exit 0
  load_note_cache

  # One jq call emits all suggestion fields as TSV; the while loop reads
  # each row without re-parsing the JSON array on every field access.
  # The loop body extends NOTE_CACHE after each append so that same-run
  # duplicates (e.g. two suggestions with colliding names) are caught by
  # already_in_note on subsequent iterations.
  while IFS=$'\t' read -r kind name one_liner line snippet; do
    # Cap name length to match the Python slug cap (28) BEFORE redaction
    # so Claude-fallback names (which arrive verbatim, no Python slug
    # pass) don't hit the 40-char [REDACTED-LONG] pattern and collapse
    # multiple distinct suggestions onto the same stored key.
    name="${name:0:36}"
    # Redact ALL text-bearing fields, including name — for n-gram and
    # Claude-fallback suggestions the name is slugged from user text, so
    # a secret-bearing phrase can otherwise end up as the backticked
    # name in the note.
    name=$(redact_snippet "$name")
    one_liner=$(redact_snippet "$one_liner")
    snippet=$(redact_snippet "$(echo "$snippet" | tr -d '"' | head -c 200)")
    if [ -n "$name" ] && [ -n "$one_liner" ] && ! already_in_note "$name"; then
      append_suggestion "$kind" "$name" "$one_liner" "$line" "$snippet"
      NOTE_CACHE="$NOTE_CACHE"$'\n'"\`$name\`"
    fi
  done < <(echo "$suggestions" | jq -r '.[] | [.kind // "skill", .name // "", .one_liner // "", .evidence_line // 0, .evidence_snippet // ""] | @tsv')

  exit 0
}

main

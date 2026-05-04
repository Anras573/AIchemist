#!/usr/bin/env bash
#
# skill-suggester.sh
#
# Hook script for PreCompact and SessionEnd events. Mines the current session
# transcript for patterns that could become reusable skills, agents, or hooks,
# and appends one-line nudges to "AIchemist/Skill Ideas.md" in the user's
# Obsidian vault.
#
# Best-effort: any failure exits 0 silently to avoid breaking the session.

set -u

for cmd in jq awk sort obsidian python3; do
  command -v "$cmd" >/dev/null 2>&1 || exit 0
done

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

readonly DRY_RUN="${DRY_RUN:-0}"
is_dry_run() { [ "$DRY_RUN" = "1" ]; }

readonly EXCLUDED_TOOLS_REGEX='^(Read|TodoWrite|TaskCreate|TaskUpdate|TaskList|TaskGet|TaskOutput|TaskStop|AskUserQuestion|EnterPlanMode|ExitPlanMode|EnterWorktree|ExitWorktree|ScheduleWakeup|Monitor)$'

# ----- Read hook input -----------------------------------------------------

TMPDIR=$(mktemp -d -t skill-suggester.XXXXXX) || exit 0
trap 'rm -rf "$TMPDIR" 2>/dev/null' EXIT HUP INT TERM

# Stream stdin directly to a temp file instead of slurping into a shell
# variable — PreCompact transcripts can be multi-MB and doubling that in
# memory can dominate the hook's cost.
STDIN_FILE="$TMPDIR/stdin.raw"
cat > "$STDIN_FILE"
[ ! -s "$STDIN_FILE" ] && exit 0

# Hook stdin may be a JSON payload (with transcript_path) or a raw JSONL dump.
TRANSCRIPT=""
if jq -e . < "$STDIN_FILE" >/dev/null 2>&1; then
  PATH_FIELD=$(jq -r '.transcript_path // empty' < "$STDIN_FILE" 2>/dev/null)
  [ -n "$PATH_FIELD" ] && [ -f "$PATH_FIELD" ] && TRANSCRIPT="$PATH_FIELD"
fi
[ -z "$TRANSCRIPT" ] && TRANSCRIPT="$STDIN_FILE"

# Early gate: skip full pipeline on trivially small transcripts.
_line_count=$(wc -l < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')
[ "${_line_count:-0}" -lt "$MIN_TRANSCRIPT_LINES" ] && exit 0

# ----- Vault resolution ----------------------------------------------------

resolve_vault() {
  local vault=""
  local config="$PLUGIN_ROOT/config.json"

  if [ -f "$config" ]; then
    vault=$(jq -r '.obsidian.preferredVault // empty' "$config" 2>/dev/null)
  fi

  [ -z "$vault" ] && vault="${OBSIDIAN_VAULT:-}"

  if [ -z "$vault" ]; then
    # Parse `obsidian vaults` output. Use tab as separator so vault names
    # with spaces ("My Vault") resolve correctly — `print $1` with default
    # whitespace separator truncates at the first space.
    local vaults count
    vaults=$(obsidian vaults 2>/dev/null | awk -F'\t' 'NF && !/^(NAME|Available|No vault)/ { print $1 }')
    count=$(echo "$vaults" | grep -c . || true)
    [ "$count" = "1" ] && vault=$(echo "$vaults" | head -n1)
  fi

  echo "$vault"
}

VAULT=$(resolve_vault)
if [ -z "$VAULT" ]; then
  if is_dry_run; then
    VAULT="<no-vault-configured>"
    echo "[DRY_RUN] no vault resolved; continuing with placeholder" >&2
  else
    exit 0
  fi
fi

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
  ' "$tools"
}

detect_user_ngrams() {
  local msgs="$TMPDIR/msgs.tsv"
  extract_user_messages > /dev/null  # ensure cache populated
  [ ! -s "$msgs" ] && return 0

  # Non-overlapping count: a repeated phrase within one message ("the the
  # the the the" with n=4) counts as one occurrence, not two. Across
  # messages we always count separately since positions reset each record.
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
  ' "$msgs"
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

list_existing() {
  local dir="$1" glob="$2"
  find "$PLUGIN_ROOT/$dir" -maxdepth 2 -name "$glob" 2>/dev/null | while read -r f; do
    awk -F': *' '/^name:/ { gsub(/[[:space:]]+$/, "", $2); print $2; exit }' "$f"
  done | sort -u
}

invoke_claude_fallback() {
  [ "$HAS_CLAUDE" = "1" ] || { echo "[]"; return; }

  local skills agents transcript_snippet
  skills=$(list_existing "skills" "SKILL.md" | paste -sd, -)
  agents=$(list_existing "agents" "*.agent.md" | paste -sd, -)
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

  local raw json
  raw=$(claude -p "$(cat "$prompt_file")" --output-format text 2>/dev/null | tr -d '\r')
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

# ----- Main ---------------------------------------------------------------

main() {
  local suggestions
  suggestions=$(format_regex_suggestions)

  local regex_count
  regex_count=$(echo "$suggestions" | jq -r 'length' 2>/dev/null)

  if [ "${regex_count:-0}" = "0" ]; then
    local exchanges
    exchanges=$(count_user_exchanges)
    if [ "${exchanges:-0}" -ge "$SESSION_GATE" ]; then
      suggestions=$(invoke_claude_fallback)
    fi
  fi

  local total
  total=$(echo "$suggestions" | jq -r 'length' 2>/dev/null)
  [ "${total:-0}" = "0" ] && exit 0

  ensure_note_exists || exit 0
  load_note_cache

  # One jq call emits all suggestion fields as TSV; the while loop reads
  # each row without re-parsing the JSON array on every field access.
  # The loop body extends NOTE_CACHE after each append so that same-run
  # duplicates (e.g. two suggestions with colliding names) are caught by
  # already_in_note on subsequent iterations.
  while IFS=$'\t' read -r kind name one_liner line snippet; do
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

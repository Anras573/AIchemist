#!/usr/bin/env bash
#
# skill-suggester.sh
#
# Hook script for PreCompact and SessionEnd events. Mines the current session
# transcript for patterns that could become reusable skills, agents, or hooks,
# and appends one-line nudges to "AIchemist/Skill Ideas.md" in the user's
# Obsidian vault.
#
# Flow:
#   1. Read hook payload from stdin (JSON with transcript_path, or raw JSONL).
#   2. Build a normalized tool-call sequence and extract user messages.
#   3. Regex pass: detect tool-call subsequences (len 3, 2+ repeats) and
#      user-phrasing n-grams (4 words, 2+ repeats).
#   4. If regex found nothing AND session has >=20 exchanges: invoke
#      `claude -p` for semantic detection (hybrid fallback).
#   5. Dedup against existing note contents; append new suggestions via
#      `obsidian append`.
#
# Best-effort: any failure exits 0 silently to avoid breaking the session.

set -u
trap 'exit 0' EXIT ERR

# ----- Dependencies ---------------------------------------------------------

for cmd in jq awk sort uniq obsidian; do
  command -v "$cmd" >/dev/null 2>&1 || exit 0
done

# claude CLI is optional (only needed for the semantic fallback)
HAS_CLAUDE=0
command -v claude >/dev/null 2>&1 && HAS_CLAUDE=1

# ----- Config ---------------------------------------------------------------

readonly PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
readonly NOTE_PATH="AIchemist/Skill Ideas.md"
readonly TOOL_SEQ_LEN=3
readonly TOOL_REPEAT_MIN=2
readonly NGRAM_SIZE=4
readonly NGRAM_REPEAT_MIN=2
readonly SESSION_GATE=20
readonly MAX_SUGGESTIONS=3

# DRY_RUN=1 → print what would be written, don't touch Obsidian
readonly DRY_RUN="${DRY_RUN:-0}"

readonly EXCLUDED_TOOLS_REGEX='^(Read|TodoWrite|TaskCreate|TaskUpdate|TaskList|TaskGet|TaskOutput|TaskStop|AskUserQuestion|EnterPlanMode|ExitPlanMode|EnterWorktree|ExitWorktree|ScheduleWakeup|Monitor)$'

# ----- Read hook input -----------------------------------------------------

HOOK_INPUT=$(cat)
[ -z "$HOOK_INPUT" ] && exit 0

TMPDIR=$(mktemp -d -t skill-suggester.XXXXXX) || exit 0
# Override the existing trap to also clean up tmpdir
trap 'rm -rf "$TMPDIR" 2>/dev/null; exit 0' EXIT ERR

# Try JSON payload with transcript_path; else treat stdin as raw JSONL
TRANSCRIPT=""
if echo "$HOOK_INPUT" | jq -e . >/dev/null 2>&1; then
  PATH_FIELD=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  [ -n "$PATH_FIELD" ] && [ -f "$PATH_FIELD" ] && TRANSCRIPT="$PATH_FIELD"
fi
if [ -z "$TRANSCRIPT" ]; then
  TRANSCRIPT="$TMPDIR/session.jsonl"
  echo "$HOOK_INPUT" > "$TRANSCRIPT"
fi

# ----- Vault resolution ----------------------------------------------------

resolve_vault() {
  local vault=""
  local config="$PLUGIN_ROOT/config.json"

  if [ -f "$config" ]; then
    vault=$(jq -r '.obsidian.preferredVault // empty' "$config" 2>/dev/null)
  fi

  [ -z "$vault" ] && vault="${OBSIDIAN_VAULT:-}"

  if [ -z "$vault" ]; then
    # Try single-vault auto-pick: parse `obsidian vaults` output
    local vaults count
    vaults=$(obsidian vaults 2>/dev/null | awk 'NF && !/^(NAME|Available|No vault)/' | awk '{print $1}')
    count=$(echo "$vaults" | grep -c . || true)
    [ "$count" = "1" ] && vault=$(echo "$vaults" | head -n1)
  fi

  echo "$vault"
}

VAULT=$(resolve_vault)
if [ -z "$VAULT" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    VAULT="<no-vault-configured>"
    echo "[DRY_RUN] no vault resolved; continuing with placeholder" >&2
  else
    exit 0
  fi
fi

# ----- Transcript parsing --------------------------------------------------

# Emit one tool-call per line, filtered + normalized.
# Output format: <normalized-tool-name>\t<line-number>
extract_tools() {
  # shellcheck disable=SC2016
  jq -r --arg excl "$EXCLUDED_TOOLS_REGEX" '
    def normalize(name; input):
      if name == "Bash" then
        # Two-token Bash grouping: first 2 whitespace-separated tokens
        (input.command // "" | split(" ") | .[0:2] | join(" ")) as $two
        | "Bash(" + $two + ")"
      elif (name | startswith("mcp__plugin_")) then
        # mcp__plugin_<vendor>_<server>__<tool> → <server>:<tool>
        (name | sub("^mcp__plugin_[^_]+_"; "") | sub("__"; ":")) as $n
        | $n
      else
        name
      end;

    [inputs] as $lines
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

# Emit each user message on one line (newlines collapsed), lowercased.
# Output format: <line-number>\t<message-text>
extract_user_messages() {
  jq -r '
    [inputs] as $lines
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
              # Strip Claude Code harness-injected tags (system reminders,
              # slash-command metadata, captured command I/O) before
              # n-gram detection, so we only count actual user phrasings.
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
  ' "$TRANSCRIPT" 2>/dev/null
}

count_user_exchanges() {
  extract_user_messages | wc -l | tr -d ' '
}

# ----- Regex detection -----------------------------------------------------

# Tool subsequences: sliding window of length TOOL_SEQ_LEN, repeats >= TOOL_REPEAT_MIN.
# Emits one line per matching subsequence: <seq-with-arrows>\t<first-line-number>
detect_tool_sequences() {
  local tools="$TMPDIR/tools.tsv"
  extract_tools > "$tools"
  [ ! -s "$tools" ] && return 0

  awk -F'\t' -v len="$TOOL_SEQ_LEN" -v min="$TOOL_REPEAT_MIN" '
    { names[NR] = $1; lines[NR] = $2 }
    END {
      for (i = 1; i <= NR - len + 1; i++) {
        key = names[i]
        for (j = 1; j < len; j++) key = key " \xe2\x86\x92 " names[i+j]
        count[key]++
        if (!(key in first_line)) first_line[key] = lines[i]
      }
      for (k in count) {
        if (count[k] >= min) print k "\t" first_line[k]
      }
    }
  ' "$tools"
}

# User-phrasing n-grams: sliding window of NGRAM_SIZE words, repeats >= NGRAM_REPEAT_MIN.
# Emits: <ngram-text>\t<first-line-number>
detect_user_ngrams() {
  local msgs="$TMPDIR/msgs.tsv"
  extract_user_messages > "$msgs"
  [ ! -s "$msgs" ] && return 0

  awk -F'\t' -v n="$NGRAM_SIZE" -v min="$NGRAM_REPEAT_MIN" '
    {
      line = $1
      # tokenize $2 on whitespace
      nwords = split($2, w, /[[:space:]]+/)
      for (i = 1; i <= nwords - n + 1; i++) {
        key = ""
        for (j = 0; j < n; j++) key = key (j ? " " : "") w[i+j]
        count[key]++
        if (!(key in first_line)) first_line[key] = line
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

# Converts regex detections into the same JSON shape Claude would produce.
# Uses heuristics: tool sequences → likely skill/hook; repeated phrasings → likely skill.
format_regex_suggestions() {
  local seqs="$TMPDIR/seqs.tsv"
  local ngrams="$TMPDIR/ngrams.tsv"
  detect_tool_sequences > "$seqs"
  detect_user_ngrams > "$ngrams"

  # Build JSON array; cap at MAX_SUGGESTIONS total (sequences first, then ngrams)
  jq -Rs --argjson cap "$MAX_SUGGESTIONS" '
    split("\n") | map(select(length > 0)) | .[:$cap]
  ' "$seqs" > "$TMPDIR/seq-arr.json" 2>/dev/null

  python3 - "$seqs" "$ngrams" "$MAX_SUGGESTIONS" <<'PY' 2>/dev/null || echo "[]"
import json, sys, re

seq_path, ngram_path, cap = sys.argv[1], sys.argv[2], int(sys.argv[3])
out = []

def slug(s):
    s = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
    return s[:48] or "pattern"

with open(seq_path) as f:
    for line in f:
        if len(out) >= cap: break
        line = line.rstrip("\n")
        if not line: continue
        seq, _, lineno = line.rpartition("\t")
        out.append({
            "kind": "skill",
            "name": "workflow-" + slug(seq.split(" → ")[0]),
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
    awk '/^name:/ { sub(/^name:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, ""); print; exit }' "$f"
  done | sort -u
}

invoke_claude_fallback() {
  [ "$HAS_CLAUDE" = "1" ] || { echo "[]"; return; }

  local skills agents preamble transcript_snippet
  skills=$(list_existing "skills" "SKILL.md" | paste -sd, -)
  agents=$(list_existing "agents" "*.agent.md" | paste -sd, -)

  # Tail the transcript to keep prompt size bounded
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
    - Mining sessions for skill suggestions (this hook)

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

  # Invoke headless claude; require valid JSON array or give up
  local raw
  raw=$(claude -p "$(cat "$prompt_file")" --output-format text 2>/dev/null | tr -d '\r')
  # Extract JSON array from response (first [ to last ])
  local json
  json=$(echo "$raw" | awk '/^\[/,/^\]$/' | head -c 8192)
  if echo "$json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "$json"
  else
    echo "[]"
  fi
}

# ----- Obsidian dedup + append --------------------------------------------

already_in_note() {
  local name="$1"
  [ "$DRY_RUN" = "1" ] && return 1
  # Read current note; if suggestion name already appears, skip
  obsidian vault="$VAULT" read path="$NOTE_PATH" 2>/dev/null \
    | grep -F -q "\`$name\`" && return 0
  return 1
}

ensure_note_exists() {
  if [ "$DRY_RUN" = "1" ]; then
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
  if [ "$DRY_RUN" = "1" ]; then
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

  # Determine if we should invoke Claude fallback
  local regex_count
  regex_count=$(echo "$suggestions" | jq -r 'length' 2>/dev/null || echo 0)

  if [ "$regex_count" = "0" ]; then
    local exchanges
    exchanges=$(count_user_exchanges)
    if [ "$exchanges" -ge "$SESSION_GATE" ]; then
      suggestions=$(invoke_claude_fallback)
    fi
  fi

  local total
  total=$(echo "$suggestions" | jq -r 'length' 2>/dev/null || echo 0)
  [ "$total" = "0" ] && exit 0

  ensure_note_exists || exit 0

  # Iterate suggestions, dedup, append
  local i=0
  while [ "$i" -lt "$total" ]; do
    local sug kind name one_liner line snippet
    sug=$(echo "$suggestions" | jq -r ".[$i]")
    kind=$(echo "$sug" | jq -r '.kind // "skill"')
    name=$(echo "$sug" | jq -r '.name // empty')
    one_liner=$(echo "$sug" | jq -r '.one_liner // empty')
    line=$(echo "$sug" | jq -r '.evidence_line // 0')
    snippet=$(echo "$sug" | jq -r '.evidence_snippet // empty' | tr -d '"' | head -c 200)

    if [ -n "$name" ] && [ -n "$one_liner" ] && ! already_in_note "$name"; then
      append_suggestion "$kind" "$name" "$one_liner" "$line" "$snippet"
    fi
    i=$((i + 1))
  done

  exit 0
}

main

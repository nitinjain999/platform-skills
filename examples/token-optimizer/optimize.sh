#!/usr/bin/env bash
# optimize.sh — deterministic read-size classification for /platform-skills:token-optimizer.
#
# FAIL-OPEN BY DESIGN. Every error path logs one degradation line, emits nothing,
# and exits 0. This is the OPPOSITE of examples/ai-governance/evaluate.sh, which
# fails closed. A security gate that stops gating is worse than a broken session;
# a cost optimizer that starts denying reads when its own config breaks gets
# uninstalled. Do not "fix" this asymmetry — both behaviours are intentional.
#
# Never executes or evaluates shell text from a payload.
set -uo pipefail

SCHEMA_VERSION=1

SOURCE_ONLY=0
MODE="hook"
PLATFORM="none"
CONFIG_FILE=".token-optimizer.yaml"
DEGRADED=0
CLI_PATH=""
CLI_OFFSET=0
CLI_LIMIT=0

# Config defaults. load_config overrides these when a readable, VALID config exists.
ENABLED=1
MODE_SETTING="audit"
WORKER_AGENT="platform-bulk-reader"
WORKER_MODEL=""
MAX_LINES=350
MAX_BYTES=32768
MAX_RANGE_RATIO=80
SUMMARY_WORDS=600
EXEMPT_AGENT_TYPES="platform-bulk-reader"
LOG_FILE=".token-optimizer/decisions.log"
STATE_DIR=".token-optimizer/state"
DEFAULT_READ_LIMIT=0
CUMULATIVE_LINES=8000
CUMULATIVE_BYTES=524288
MAX_DELEGATIONS_PER_TASK=3
MAX_WORKER_RETRIES=1
MAX_WORKER_SECONDS=120

# Normalised payload fields. normalize_payload sets these directly rather than
# echoing them, because a command substitution runs in a subshell and would
# discard any DEGRADED flag it set — the failure would be invisible to the caller.
P_TOOL=""
P_PATH=""
P_OFFSET=0
P_LIMIT=0
P_COMMAND=""
P_AGENT_TYPE=""
P_AGENT_ID=""
P_SESSION=""
P_OUTPUT_MODE=""
P_HEAD_LIMIT=0

usage() {
  cat <<'EOF'
Usage: optimize.sh [--mode=hook|classify|explain|report] [--platform=copilot|claude|vscode|none]
                   [--config=PATH] [--path=PATH] [--offset=N] [--limit=N] [--source-only]

Modes:
  hook      Read a PreToolUse JSON payload on stdin, classify, emit a decision.
  classify  Classify an explicit --path (with optional --offset/--limit).
  explain   Dry run: print requested size, effective config with sources, and
            the decision that would be made. Writes no log and no state.
  report    Aggregate the decision log into a summary table.

Exit codes:
  0 = pass, audit, or redirect (real platforms emit JSON deny and exit 0)
  2 = redirect on --platform=none (scriptable dry-run signal)
EOF
}

for arg in "$@"; do
  case "$arg" in
    --source-only) SOURCE_ONLY=1 ;;
    --mode=*) MODE="${arg#--mode=}" ;;
    --platform=*) PLATFORM="${arg#--platform=}" ;;
    --config=*) CONFIG_FILE="${arg#--config=}" ;;
    --path=*) CLI_PATH="${arg#--path=}" ;;
    --offset=*) CLI_OFFSET="${arg#--offset=}" ;;
    --limit=*) CLI_LIMIT="${arg#--limit=}" ;;
    -h|--help) usage; exit 0 ;;
  esac
done

# --- logging -----------------------------------------------------------------

log_line() {
  # log_line <outcome> <rule> <detail> <target>
  #
  # NEVER creates its own directory. `setup` creates it; until then this writes
  # nothing. A naive `mkdir -p` here creates .token-optimizer/ in whatever
  # directory the core runs from, including a CI checkout root.
  [[ "$PLATFORM" == "none" ]] && return 0
  [[ -z "${LOG_FILE:-}" ]] && return 0
  local dir
  dir="$(dirname "$LOG_FILE")"
  [[ "$LOG_FILE" == "/dev/null" || -d "$dir" ]] || return 0
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" "$4" >>"$LOG_FILE" 2>/dev/null || true
  [[ "$LOG_FILE" == "/dev/null" ]] || chmod 600 "$LOG_FILE" 2>/dev/null || true
  return 0
}

degrade() {
  DEGRADED=1
  log_line "degraded" "optimizer_unavailable" "$1" "-"
  return 0
}

# --- config validation -------------------------------------------------------

is_uint() {
  case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

set_uint() {
  # set_uint <var_name> <value> <min> <max>
  # Applies the value only when it is a valid unsigned int in range. An invalid
  # threshold silently applied is worse than a default: `max_lines: -1` would
  # make every one-line read oversized.
  local name="$1" value="$2" min="$3" max="$4"
  if ! is_uint "$value"; then
    degrade "invalid $name (not an unsigned integer): $value"
    return 1
  fi
  if [[ "$value" -lt "$min" || "$value" -gt "$max" ]]; then
    degrade "$name out of range [$min-$max]: $value"
    return 1
  fi
  eval "$name=\$value"
  return 0
}

yq_get() {
  # Raw value or empty. Does NOT use `//`, because in yq `a // b` substitutes for
  # false as well as null, so `.enabled // ""` turns `enabled: false` into "" and
  # a real `false` is indistinguishable from a missing key.
  local out
  out="$(yq eval "$1" "$CONFIG_FILE" 2>/dev/null)" || return 1
  [[ "$out" == "null" ]] && return 1
  printf '%s' "$out"
  return 0
}

load_config() {
  [[ -r "$CONFIG_FILE" ]] || { degrade "config not readable: $CONFIG_FILE"; return 0; }
  command -v yq >/dev/null 2>&1 || { degrade "yq not installed"; return 0; }

  local v
  # Schema version first — an unknown schema must not be interpreted with
  # this version's key meanings.
  if v="$(yq_get '.version')"; then
    if is_uint "$v" && [[ "$v" -gt "$SCHEMA_VERSION" ]]; then
      degrade "config schema version $v is newer than supported $SCHEMA_VERSION"
      return 0
    fi
  fi

  # enabled: read directly. `false` and a missing key are different things.
  if v="$(yq_get '.enabled')"; then
    case "$v" in
      false|False|FALSE) ENABLED=0 ;;
      true|True|TRUE)    ENABLED=1 ;;
      *) degrade "invalid enabled (expected true/false): $v" ;;
    esac
  fi

  if v="$(yq_get '.mode')"; then
    case "$v" in
      off|advisory|audit|redirect) MODE_SETTING="$v" ;;
      *) degrade "invalid mode: $v" ;;
    esac
  fi

  v="$(yq_get '.worker_agent')" && [[ -n "$v" ]] && WORKER_AGENT="$v"
  v="$(yq_get '.worker_model')" && [[ -n "$v" ]] && WORKER_MODEL="$v"
  v="$(yq_get '.log')"          && [[ -n "$v" ]] && LOG_FILE="$v"
  v="$(yq_get '.state_dir')"    && [[ -n "$v" ]] && STATE_DIR="$v"

  v="$(yq_get '.max_lines')"           && set_uint MAX_LINES "$v" 1 100000000
  v="$(yq_get '.max_bytes')"           && set_uint MAX_BYTES "$v" 1 1073741824
  v="$(yq_get '.max_range_ratio')"     && set_uint MAX_RANGE_RATIO "$v" 1 100
  v="$(yq_get '.summary_words')"       && set_uint SUMMARY_WORDS "$v" 1 100000
  v="$(yq_get '.default_read_limit')"  && set_uint DEFAULT_READ_LIMIT "$v" 0 100000000
  v="$(yq_get '.cumulative_lines')"    && set_uint CUMULATIVE_LINES "$v" 1 100000000
  v="$(yq_get '.cumulative_bytes')"    && set_uint CUMULATIVE_BYTES "$v" 1 1073741824
  v="$(yq_get '.max_delegations_per_task')" && set_uint MAX_DELEGATIONS_PER_TASK "$v" 1 100
  v="$(yq_get '.max_worker_retries')"  && set_uint MAX_WORKER_RETRIES "$v" 0 10
  v="$(yq_get '.max_worker_seconds')"  && set_uint MAX_WORKER_SECONDS "$v" 1 3600

  v="$(yq eval '.exempt_agent_types[]' "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ')"
  [[ -n "${v// /}" && "$v" != "null " ]] && EXEMPT_AGENT_TYPES="$v"

  apply_platform_defaults
  return 0
}

apply_platform_defaults() {
  # An omitted read limit means the CLIENT's default, not the whole file.
  # Only fill in a measured per-client value when the config did not set one.
  if [[ "$DEFAULT_READ_LIMIT" -eq 0 ]]; then
    case "$PLATFORM" in
      claude) DEFAULT_READ_LIMIT=2000 ;;   # Claude Code Read defaults to 2000 lines
      *) : ;;                              # unknown elsewhere until probed
    esac
  fi
  return 0
}

# --- effective mode ----------------------------------------------------------

effective_mode() {
  # Platform capability CAPS the configured mode. A repo that shares one config
  # across clients must not get a redirect on a client that cannot support it.
  # Claude Code is the only client with verified delegation and a documented
  # per-call worker identity, so it is the only one that may redirect.
  [[ "$ENABLED" -eq 0 ]] && { echo "off"; return 0; }
  case "$MODE_SETTING" in off) echo "off"; return 0 ;; esac
  case "$PLATFORM" in
    claude|none) echo "$MODE_SETTING" ;;
    copilot|vscode)
      if [[ "$MODE_SETTING" == "redirect" ]]; then echo "audit"; else echo "$MODE_SETTING"; fi
      ;;
    *) echo "audit" ;;
  esac
}

effective_mode_reason() {
  case "$PLATFORM" in
    copilot) [[ "$MODE_SETTING" == "redirect" ]] && printf 'capped to audit: redirection unsupported on copilot (no per-call worker identity in the documented payload)' ;;
    vscode)  [[ "$MODE_SETTING" == "redirect" ]] && printf 'capped to audit: delegation unverified on vscode (runtime fixture required)' ;;
  esac
  return 0
}

# --- payload -----------------------------------------------------------------

normalize_payload() {
  # Sets P_* globals. Returns 1 on parse failure so the caller sees it — an
  # echoing version captured with $( ) loses DEGRADED to the subshell.
  #
  # Fields are NUL-delimited and read through process substitution. A NUL byte
  # cannot appear inside a JSON string, so payload content can never forge a
  # field boundary. A NEWLINE can (as \n), which is why an earlier
  # newline-delimited parse was exploitable: a file_path containing \n split
  # across positional lines, shifting every later field — the offset landed in
  # limit, the session id was lost, and the truncated path failed
  # classification so an oversized read passed unchallenged.
  #
  # Command substitution must NOT be used to capture this: bash silently drops
  # NUL bytes, so the delimiters would vanish before they could be read.
  local raw="${1:-}"
  P_TOOL=""; P_PATH=""; P_OFFSET=0; P_LIMIT=0
  P_COMMAND=""; P_AGENT_TYPE=""; P_AGENT_ID=""; P_SESSION=""
  P_OUTPUT_MODE=""; P_HEAD_LIMIT=0

  command -v jq >/dev/null 2>&1 || { degrade "jq not installed"; return 1; }

  local -a f=()
  local item
  while IFS= read -r -d '' item; do f+=("$item"); done < <(
    printf '%s' "$raw" | jq -j '
      # A client may send tool arguments as an object OR as a JSON-encoded
      # STRING. Coercing a string to {} silently discarded the path, so every
      # read arrived unclassified and unlogged. Parse the string; if it is not
      # valid JSON, report malformed rather than swallowing it.
      def parsed(g):
        g | if   type == "object" then {ok: true,  v: .}
            elif type == "null"   then {ok: true,  v: {}}
            elif type == "string" then
              # Must decode to an OBJECT. `try {ok: true, v: fromjson}` accepted
              # a scalar or an array, so toolArgs: "null" / "[]" / "42" decoded
              # "successfully", collapsed to {}, and passed with an empty path and
              # no degradation — the same silent hole as the unparsed string.
              (try (fromjson | if type == "object" then {ok: true, v: .}
                               else {ok: false, v: {}} end)
               catch {ok: false, v: {}})
            else {ok: false, v: {}} end;
      parsed(.tool_input) as $ti
      | parsed(.toolArgs) as $ta
      | (($ti.v | if type == "object" then . else {} end)
         + ($ta.v | if type == "object" then . else {} end)) as $a
      | [ (.tool_name // .toolName // "")
        , ($a.file_path // $a.path // $a.notebook_path // "")
        , (($a.offset // 0) | tostring)
        , (($a.limit // 0) | tostring)
        , ($a.command // "")
        , (.agent_type // .agentType // "")
        , (.agent_id // .agentId // "")
        , (.session_id // .sessionId // "")
        , ($a.output_mode // "")
        , (($a.head_limit // 0) | tostring)
        , (if ($ti.ok and $ta.ok) then "ok" else "malformed" end)
        ] | map(. + "\u0000") | join("")
    ' 2>/dev/null
  )

  # Exactly eight fields, or the parse failed. This also catches malformed JSON,
  # where jq emits nothing at all.
  if [[ "${#f[@]}" -ne 11 ]]; then
    degrade "payload parse failed (${#f[@]} of 11 fields)"
    return 1
  fi

  P_TOOL="${f[0]}"; P_PATH="${f[1]}"; P_OFFSET="${f[2]}"; P_LIMIT="${f[3]}"
  P_COMMAND="${f[4]}"; P_AGENT_TYPE="${f[5]}"; P_AGENT_ID="${f[6]}"; P_SESSION="${f[7]}"
  P_OUTPUT_MODE="${f[8]}"; P_HEAD_LIMIT="${f[9]}"
  is_uint "$P_OFFSET" || P_OFFSET=0
  is_uint "$P_LIMIT"  || P_LIMIT=0
  is_uint "$P_HEAD_LIMIT" || P_HEAD_LIMIT=0

  # Malformed tool arguments must not pass as an empty read. Fail open as
  # always, but say so, so an unclassifiable payload is visible in the log
  # instead of looking like a small read.
  if [[ "${f[10]}" != "ok" ]]; then
    degrade "tool arguments were neither an object nor valid JSON"
    return 1
  fi
  return 0
}

# --- size classification -----------------------------------------------------

file_lines() {
  # awk NR, not `wc -l`. wc counts newlines, so a file whose final line is
  # unterminated reports one short — and that invisible line can be 50 KiB.
  [[ -n "${1:-}" && -r "$1" && -f "$1" ]] || return 1
  local n; n="$(awk 'END{print NR}' "$1" 2>/dev/null)" || return 1
  is_uint "$n" || return 1
  printf '%s' "$n"
}

file_bytes() {
  [[ -n "${1:-}" && -r "$1" && -f "$1" ]] || return 1
  local n; n="$(wc -c <"$1" 2>/dev/null)" || return 1
  printf '%s' "$(( n ))"
}

range_bytes() {
  # MEASURED, never estimated from a per-line average: a five-line window can
  # be 200 KiB, and an average would report it as tiny.
  local n; n="$(sed -n "${2},${3}p" "$1" 2>/dev/null | wc -c 2>/dev/null)" || return 1
  printf '%s' "$(( n ))"
}

# Tools whose output IS the file's content, so the file's size predicts the
# cost of the call.
is_content_read_tool() {
  local name
  name="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$name" in
    read|view|cat|notebookread|readfile|str_replace_editor_view) return 0 ;;
    *) return 1 ;;
  esac
}

# Tools whose output is DERIVED from the file — a count, a list of paths, the
# matching lines. The file's size says nothing about the size of that output.
# Classifying these by file size denied a `Grep` with output_mode=count against a
# 1000-line file, which returns a single number: a false positive that makes the
# optimizer look broken and costs a delegation for nothing.
is_search_tool() {
  local name
  name="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$name" in
    grep|search|glob|find|ls|list|codebase|usages) return 0 ;;
    *) return 1 ;;
  esac
}

# A search is in scope only when the payload states a bound we can size. A
# content-mode search with an explicit head_limit requests that many lines; a
# count or a filenames-only search returns effectively nothing; an unbounded
# content search cannot be predicted from the file at all.
search_requested_lines() {
  # search_requested_lines <output_mode> <head_limit>  -> lines, or empty if unsizable
  local mode head
  mode="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  head="${2:-0}"
  case "$mode" in
    count|files_with_matches|files-with-matches) printf '0' ; return 0 ;;
  esac
  if is_uint "$head" && [[ "$head" -gt 0 ]]; then printf '%s' "$head"; return 0; fi
  return 1
}

REQ_LINES=0
REQ_BYTES=0
TOTAL_LINES=0
CLASS_RESULT="pass"

classify_size() {
  # classify_size <path> <offset> <limit>  ->  "pass" | "oversized"
  # Echoes the result AND sets CLASS_RESULT, REQ_LINES, REQ_BYTES, TOTAL_LINES.
  #
  # Callers that need those globals MUST call this directly and read
  # CLASS_RESULT — never `class="$(classify_size ...)"`. A command substitution
  # runs in a subshell, so every global set here is discarded and the caller
  # silently sees zeros. That bug shipped once already: `explain` reported
  # "requested lines: 0" for every file, and the cumulative counter was fed 0
  # on every read so it could never cross its threshold.
  #
  # MAX_LINES and MAX_BYTES are ABSOLUTE gates on every read, ranged or not.
  # MAX_RANGE_RATIO is a reporting signal only and can never turn an over-limit
  # request into a pass.
  local path="${1:-}" offset="${2:-0}" limit="${3:-0}"
  local total_lines total_bytes start end avail
  REQ_LINES=0; REQ_BYTES=0; TOTAL_LINES=0

  total_lines="$(file_lines "$path")" || { CLASS_RESULT="pass"; echo "pass"; return 0; }
  total_bytes="$(file_bytes "$path")" || { CLASS_RESULT="pass"; echo "pass"; return 0; }
  is_uint "$offset" || offset=0
  is_uint "$limit"  || limit=0
  [[ "$total_lines" -eq 0 ]] && total_lines=1
  TOTAL_LINES="$total_lines"

  if   [[ "$limit" -gt 0 ]]; then REQ_LINES="$limit"
  elif [[ "$DEFAULT_READ_LIMIT" -gt 0 ]]; then REQ_LINES="$DEFAULT_READ_LIMIT"
  else REQ_LINES=$(( total_lines - offset )); fi

  avail=$(( total_lines - offset ))
  [[ "$avail" -lt 0 ]] && avail=0
  [[ "$REQ_LINES" -gt "$avail" ]] && REQ_LINES="$avail"
  [[ "$REQ_LINES" -le 0 ]] && { CLASS_RESULT="pass"; echo "pass"; return 0; }

  if [[ "$offset" -eq 0 && "$REQ_LINES" -ge "$total_lines" ]]; then
    REQ_BYTES="$total_bytes"
  else
    start=$(( offset + 1 )); end=$(( offset + REQ_LINES ))
    REQ_BYTES="$(range_bytes "$path" "$start" "$end")" || REQ_BYTES=0
  fi

  [[ "$REQ_LINES" -gt "$MAX_LINES" ]] && { CLASS_RESULT="oversized"; echo "oversized"; return 0; }
  [[ "$REQ_BYTES" -gt "$MAX_BYTES" ]] && { CLASS_RESULT="oversized"; echo "oversized"; return 0; }
  CLASS_RESULT="pass"
  echo "pass"
}

# Classify by a REQUESTED LINE COUNT alone, with no reference to any file.
# Search output is not a prefix of the source: a content search for a pattern on
# the last line of a 40 KiB single-line file returns 7 bytes, while the first
# `head_limit` source lines are the whole 40 KiB. Measuring source bytes to size
# search output denied that search. Bytes are unknowable before the search runs,
# so they are not guessed — REQ_BYTES stays 0 and only the line bound applies.
classify_lines_only() {
  # classify_lines_only <requested_lines>  ->  "pass" | "oversized"
  local requested="${1:-0}"
  REQ_LINES=0; REQ_BYTES=0; TOTAL_LINES=0
  is_uint "$requested" || { CLASS_RESULT="pass"; echo "pass"; return 0; }
  REQ_LINES="$requested"
  if [[ "$REQ_LINES" -gt "$MAX_LINES" ]]; then
    CLASS_RESULT="oversized"; echo "oversized"; return 0
  fi
  CLASS_RESULT="pass"; echo "pass"
}

is_whole_file_read() {
  # Reporting only. Never affects the pass/fail outcome.
  local total="${1:-0}" requested="${2:-0}" ratio
  [[ "$total" -gt 0 ]] || return 1
  ratio=$(( requested * 100 / total ))
  [[ "$ratio" -gt "$MAX_RANGE_RATIO" ]]
}

# --- shell read detection ----------------------------------------------------
#
# Pattern matching only. The command string is NEVER executed, evaluated, or
# passed to a subshell. Recognises the common whole-file readers and nothing
# more: a pipe, `rg`, awk, or a Python one-liner can also print an entire file
# and is deliberately NOT claimed as recognised. Unrecognised syntax is an audit
# finding, not proof of safety. This is a cost heuristic, not a data boundary.

detect_shell_full_read() {
  local cmd="${1:-}"
  [[ -n "$cmd" ]] || return 0
  case "$cmd" in
    *'|'*|*'>'*|*'<'*|*';'*|*'&'*|*'$('*|*'`'*|*'${'*) return 0 ;;
  esac

  local verb rest first_word
  verb="${cmd%% *}"
  rest="${cmd#* }"
  [[ "$rest" == "$cmd" ]] && rest=""

  case "$verb" in
    cat|less|more|bat) : ;;
    head|tail)
      first_word="${rest%% *}"
      if [[ "$first_word" == "-n" ]]; then
        local count after
        after="${rest#-n }"
        count="${after%% *}"
        is_uint "$count" || return 0
        [[ "$count" -lt "$MAX_LINES" ]] && return 0
        rest="${after#* }"
      else
        return 0
      fi
      ;;
    *) return 0 ;;
  esac

  local token target=""
  for token in $rest; do
    case "$token" in -*) continue ;; esac
    target="$token"
  done
  printf '%s' "$target"
  return 0
}

# --- exemption ---------------------------------------------------------------

is_exempt_agent() {
  local candidate="${1:-}" entry
  [[ -n "$candidate" ]] || return 1
  for entry in $EXEMPT_AGENT_TYPES; do
    [[ "$candidate" == "$entry" ]] && return 0
  done
  return 1
}

# --- bounded recovery --------------------------------------------------------

session_id() {
  # Payload session first. Env vars are a fallback, and there is deliberately NO
  # shared literal default: without a session identity, recovery state cannot be
  # scoped, so a shared "nosession" bucket would let one session inherit
  # another's exemption. Empty means "no state possible".
  if [[ -n "$P_SESSION" ]]; then printf '%s' "$P_SESSION"; return 0; fi
  printf '%s' "${TOKEN_OPTIMIZER_SESSION:-${CLAUDE_SESSION_ID:-${COPILOT_SESSION_ID:-}}}"
}

abs_path() {
  local d b
  d="$(dirname "$1")"; b="$(basename "$1")"
  if d="$(cd "$d" 2>/dev/null && pwd)"; then printf '%s/%s' "$d" "$b"; else printf '%s' "$1"; fi
}

hash_str() {
  if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum 2>/dev/null | cut -d' ' -f1
  else return 1; fi
}

state_key() {
  # Collision-resistant: a hash of session + absolute path, not a sanitised
  # string where two different paths can flatten to the same filename.
  local sess; sess="$(session_id)"
  [[ -n "$sess" ]] || return 1
  hash_str "${sess}|$(abs_path "$1")"
}

redirect_attempts() {
  local key f n
  key="$(state_key "$1")" || { echo 0; return 0; }
  f="$STATE_DIR/$key"
  [[ -r "$f" ]] || { echo 0; return 0; }
  n="$(cat "$f" 2>/dev/null)" || { echo 0; return 0; }
  is_uint "$n" || { echo 0; return 0; }
  echo "$n"
}

record_redirect_attempt() {
  # Returns 0 only when the attempt was durably recorded. The caller MUST NOT
  # deny unless this succeeds: without persistence the counter never advances
  # and the same read is denied forever, which is the deadlock bounded recovery
  # exists to prevent.
  [[ "$PLATFORM" == "none" ]] && return 1   # dry run persists nothing
  [[ -d "$STATE_DIR" ]] || return 1
  local key f
  key="$(state_key "$1")" || return 1
  f="$STATE_DIR/$key"
  # Atomic claim: noclobber makes `>` fail if another concurrent hook call
  # already created this file, so exactly one caller can claim the denial.
  # A read-then-write would let two callers both observe zero and both deny.
  ( set -C; : > "$f" ) 2>/dev/null || return 1
  printf '1' > "$f" 2>/dev/null || true
  return 0
}

# --- cumulative discovery ----------------------------------------------------

cumulative_add() {
  # Advisory only, on every client. A session is not a task boundary, so this
  # reports and never denies.
  [[ "$PLATFORM" == "none" ]] && return 0
  [[ -d "$STATE_DIR" ]] || return 0
  local sess key f tmp cur_l cur_b new_l new_b
  sess="$(session_id)"; [[ -n "$sess" ]] || return 0
  key="$(hash_str "cumulative|${sess}")" || return 0
  f="$STATE_DIR/$key"
  cur_l=0; cur_b=0
  if [[ -r "$f" ]]; then
    cur_l="$(cut -d' ' -f1 "$f" 2>/dev/null)"; is_uint "$cur_l" || cur_l=0
    cur_b="$(cut -d' ' -f2 "$f" 2>/dev/null)"; is_uint "$cur_b" || cur_b=0
  fi
  new_l=$(( cur_l + ${1:-0} )); new_b=$(( cur_b + ${2:-0} ))
  tmp="${f}.tmp.$$"
  printf '%s %s' "$new_l" "$new_b" >"$tmp" 2>/dev/null || return 0
  mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 0; }
  if [[ "$new_l" -gt "$CUMULATIVE_LINES" || "$new_b" -gt "$CUMULATIVE_BYTES" ]]; then
    log_line "cumulative_exceeded" "cumulative_discovery" "lines=$new_l bytes=$new_b" "-"
  fi
  return 0
}

# --- decision ----------------------------------------------------------------

resolve_decision() {
  # resolve_decision <classification>  ->  "pass" | "audit" | "redirect"
  local class="${1:-pass}" eff
  eff="$(effective_mode)"
  [[ "$eff" == "off" ]] && { echo "pass"; return 0; }
  [[ "$class" == "oversized" ]] || { echo "pass"; return 0; }
  case "$eff" in
    advisory) echo "pass" ;;
    redirect) echo "redirect" ;;
    audit)    echo "audit" ;;
    *)        echo "audit" ;;
  esac
}

json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}

emit_redirect() {
  # Emits the JSON deny envelope and returns the exit code to use.
  # Real platforms (claude, copilot, vscode) exit 0 with a JSON deny — the JSON
  # decides, not the exit code. platform=none exits 2 (scriptable dry-run signal).
  local reason esc
  reason="${1:-oversized read}"
  esc="$(json_escape "$reason")"
  case "$PLATFORM" in
    claude)
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$esc"
      return 0
      ;;
    copilot|vscode)
      printf '{"permissionDecision":"deny","permissionDecisionReason":"%s"}\n' "$esc"
      return 0
      ;;
    *)
      printf '{"decision":"redirect","rule":"full_file_read","reason":"%s"}\n' "$esc"
      return 2
      ;;
  esac
}

redirect_reason() {
  # Carries the worker budgets to the model. These are the ONLY channel the core
  # has for them, and on clients that do not enforce them natively they are
  # instruction-only — `doctor` says which.
  printf 'This read is large enough to be worth delegating. Ask the %s subagent%s to answer the specific question against %s and return bounded evidence: a complete|partial|blocked verdict, file paths and symbols, short excerpts, the exact file paths its answer rests on so you can hash them yourself before editing, what was omitted or truncated, and remaining uncertainties, in roughly %s words. Budget: at most %s delegations for this task, %s retries, %s seconds. Then read only the sections you must verify yourself.' \
    "$WORKER_AGENT" \
    "${WORKER_MODEL:+ (model $WORKER_MODEL)}" \
    "${1:--}" "$SUMMARY_WORDS" \
    "$MAX_DELEGATIONS_PER_TASK" "$MAX_WORKER_RETRIES" "$MAX_WORKER_SECONDS"
}

run_hook_mode() {
  local raw class decision target reason

  raw="$(cat)"

  if ! normalize_payload "$raw"; then
    # Our own failure never blocks a call.
    return 0
  fi
  [[ "$DEGRADED" -eq 1 ]] && return 0

  # enabled: false / mode: off short-circuits before any classification.
  [[ "$(effective_mode)" == "off" ]] && return 0

  # The configured worker must be able to read what it was asked to read.
  is_exempt_agent "$P_AGENT_TYPE" && return 0

  if [[ -n "$P_COMMAND" ]]; then
    target="$(detect_shell_full_read "$P_COMMAND")"
    if [[ -n "$target" ]]; then
      # Direct call so REQ_* survive for cumulative_add. A whole-file `cat` is
      # discovery cost like any other read.
      classify_size "$target" 0 0 >/dev/null
      if [[ "$CLASS_RESULT" == "oversized" ]]; then
        cumulative_add "$REQ_LINES" "$REQ_BYTES"
        local eff; eff="$(effective_mode)"
        [[ "$eff" == "audit" || "$eff" == "redirect" ]] && log_line "would_redirect" "shell_full_read" "$P_COMMAND" "$target"
        return 0
      fi
    fi
    local eff; eff="$(effective_mode)"
    [[ "$eff" == "audit" || "$eff" == "redirect" ]] && log_line "audit" "shell_unparsed" "$P_COMMAND" "-"
    return 0
  fi

  [[ -n "$P_PATH" ]] || return 0

  local eff_limit="$P_LIMIT" eff_offset="$P_OFFSET"
  if is_content_read_tool "$P_TOOL"; then
    : # the file's size is the cost; classify it as given
  elif is_search_tool "$P_TOOL"; then
    # Size the SEARCH OUTPUT, never the underlying file.
    local slines
    if ! slines="$(search_requested_lines "$P_OUTPUT_MODE" "$P_HEAD_LIMIT")"; then
      # Unbounded content search: its output cannot be derived from the file, so
      # there is nothing honest to classify. Pass.
      log_line "audit" "search_unsizable" "${P_TOOL} mode=${P_OUTPUT_MODE:-unset}" "$P_PATH"
      return 0
    fi
    if [[ "$slines" -eq 0 ]]; then
      # count / files_with_matches: the result is a number or a path list.
      return 0
    fi
    # head_limit is an UPPER BOUND on output lines. Size it on that alone and
    # never touch the source file — see classify_lines_only.
    classify_lines_only "$slines" >/dev/null
    class="$CLASS_RESULT"
    cumulative_add "$REQ_LINES" "$REQ_BYTES"
    decision="$(resolve_decision "$class")"
    case "$decision" in
      redirect)
        if [[ "$(redirect_attempts "$P_PATH")" -ge 1 ]]; then
          log_line "redirect_exhausted" "recovery_bound" "$P_TOOL" "$P_PATH"; return 0
        fi
        if ! record_redirect_attempt "$P_PATH"; then
          log_line "recovery_unavailable" "state_write_failed" "$P_TOOL" "$P_PATH"; return 0
        fi
        log_line "redirect" "search_head_limit" "$P_TOOL" "$P_PATH"
        emit_redirect "$(redirect_reason "$P_PATH")"
        exit $?
        ;;
      audit) log_line "would_redirect" "search_head_limit" "$P_TOOL" "$P_PATH"; return 0 ;;
      *) return 0 ;;
    esac
  else
    return 0
  fi

  # Direct call, not $( ) — see classify_size's comment. REQ_LINES/REQ_BYTES
  # must survive for cumulative_add and the log.
  classify_size "$P_PATH" "$eff_offset" "$eff_limit" >/dev/null
  class="$CLASS_RESULT"
  cumulative_add "$REQ_LINES" "$REQ_BYTES"
  decision="$(resolve_decision "$class")"

  case "$decision" in
    redirect)
      if [[ "$(redirect_attempts "$P_PATH")" -ge 1 ]]; then
        log_line "redirect_exhausted" "recovery_bound" "$P_TOOL" "$P_PATH"
        return 0
      fi
      if ! record_redirect_attempt "$P_PATH"; then
        # Cannot bound the recovery, so must not start it.
        log_line "recovery_unavailable" "state_write_failed" "$P_TOOL" "$P_PATH"
        return 0
      fi
      reason="$(redirect_reason "$P_PATH")"
      log_line "redirect" "full_file_read" "$P_TOOL" "$P_PATH"
      emit_redirect "$reason"
      exit $?
      ;;
    audit)
      log_line "would_redirect" "full_file_read" "${P_TOOL}${P_AGENT_ID:+ agent=$P_AGENT_ID}" "$P_PATH"
      return 0
      ;;
    *)
      # PASS EMITS NOTHING. Never an explicit "allow" — that could contend with
      # an ai-governance deny registered on this same PreToolUse event.
      return 0
      ;;
  esac
}

run_explain_mode() {
  local path="$CLI_PATH" offset="$CLI_OFFSET" limit="$CLI_LIMIT"
  local raw class decision eff reason whole

  if [[ -z "$path" ]] && [[ ! -t 0 ]]; then
    raw="$(cat)"
    if normalize_payload "$raw"; then
      path="$P_PATH"; offset="$P_OFFSET"; limit="$P_LIMIT"
    fi
  fi

  classify_size "$path" "$offset" "$limit" >/dev/null
  class="$CLASS_RESULT"
  decision="$(resolve_decision "$class")"
  eff="$(effective_mode)"
  reason="$(effective_mode_reason)"
  if is_whole_file_read "$TOTAL_LINES" "$REQ_LINES"; then whole="yes"; else whole="no"; fi

  echo "path:                 ${path:-<none>}"
  echo "total lines:          $TOTAL_LINES"
  echo "requested lines:      $REQ_LINES"
  echo "requested bytes:      $REQ_BYTES (measured)"
  echo "counts as whole file: $whole (ratio threshold ${MAX_RANGE_RATIO}%, reporting only)"
  echo "max_lines:            $MAX_LINES"
  echo "max_bytes:            $MAX_BYTES"
  if [[ "$DEFAULT_READ_LIMIT" -gt 0 ]]; then
    echo "default_read_limit:   $DEFAULT_READ_LIMIT (platform: $PLATFORM)"
  else
    echo "default_read_limit:   unknown (omitted limit treated as whole file)"
  fi
  echo "configured mode:      $MODE_SETTING"
  echo "effective mode:       $eff${reason:+  [$reason]}"
  echo "enabled:              $([[ "$ENABLED" -eq 1 ]] && echo true || echo false)"
  echo "worker agent:         $WORKER_AGENT"
  echo "worker model:         ${WORKER_MODEL:-<inherit>} (requested; run doctor for resolved)"
  echo "worker budgets:       delegations=$MAX_DELEGATIONS_PER_TASK retries=$MAX_WORKER_RETRIES seconds=$MAX_WORKER_SECONDS"
  echo "cumulative limits:    lines=$CUMULATIVE_LINES bytes=$CUMULATIVE_BYTES (advisory)"
  echo "classification:       $class"
  echo "decision:             $decision"
  echo "degraded:             $([[ "$DEGRADED" -eq 1 ]] && echo yes || echo no)"
  echo ""
  echo "Dry run: no worker invoked, no log written, no recovery state recorded."
  return 0
}

run_report_mode() {
  if [[ ! -r "$LOG_FILE" ]]; then
    echo "No decision log at $LOG_FILE. Run in audit mode first."
    return 0
  fi
  echo "outcome              count"
  echo "-------------------- -----"
  awk -F'\t' '{c[$2]++} END {for (k in c) printf "%-20s %5d\n", k, c[k]}' "$LOG_FILE" | sort
  echo ""
  echo "Counts are decision events, not billed token usage. A hook invocation"
  echo "log is not a billing receipt — reconcile against your provider."
  return 0
}

main() {
  load_config
  case "$MODE" in
    hook) run_hook_mode ;;
    classify) classify_size "$CLI_PATH" "$CLI_OFFSET" "$CLI_LIMIT" ;;
    explain) run_explain_mode ;;
    report) run_report_mode ;;
    *) usage ;;
  esac
  exit 0
}

if [[ "$SOURCE_ONLY" -eq 0 ]]; then
  main "$@"
fi

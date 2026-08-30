#!/usr/bin/env bash
set -uo pipefail

MODE=""
PLATFORM=""
EVENT=""
POLICY_FILE=".ai-governance.yaml"
BASE_REF=""
SOURCE_ONLY=0

usage() {
  echo "Usage: evaluate.sh --mode=hook|ci [--platform=copilot|claude] [--event=preToolUse|postToolUse] [--policy=<path>] [--base-ref=<ref>]" >&2
  exit 1
}

for arg in "$@"; do
  case "$arg" in
    --mode=*) MODE="${arg#--mode=}" ;;
    --platform=*) PLATFORM="${arg#--platform=}" ;;
    --event=*) EVENT="${arg#--event=}" ;;
    --policy=*) POLICY_FILE="${arg#--policy=}" ;;
    --base-ref=*) BASE_REF="${arg#--base-ref=}" ;;
    --source-only) SOURCE_ONLY=1 ;;
    *) usage ;;
  esac
done

if [[ "$SOURCE_ONLY" -eq 0 ]]; then
  [[ -z "$MODE" ]] && usage
  if [[ "$MODE" == "hook" && -z "$PLATFORM" ]]; then
    usage
  fi
fi

json_string() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  printf '"%s"' "$s"
}

emit_decision() {
  local decision="$1"
  local reason="${2:-}"

  # MODE=ci always uses Copilot envelope; hook mode selects envelope by PLATFORM
  if [[ "$MODE" == "ci" || "$PLATFORM" == "copilot" ]]; then
    if [[ "$decision" == "deny" ]]; then
      printf '{"permissionDecision":"deny","permissionDecisionReason":%s}\n' "$(json_string "$reason")"
      exit 2
    else
      printf '{"permissionDecision":"allow"}\n'
      exit 0
    fi
  elif [[ "$PLATFORM" == "claude" ]]; then
    if [[ "$decision" == "deny" ]]; then
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$(json_string "$reason")"
      exit 2
    else
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}\n'
      exit 0
    fi
  else
    echo "evaluate.sh: unknown platform '$PLATFORM'" >&2
    exit 1
  fi
}

ENFORCEMENT="audit"
MAX_DIFF_FILES=0
REQUIRE_DISCLOSURE="false"
PROTECTED_PATHS=()
DENIED_COMMANDS=()

load_policy() {
  if ! command -v yq >/dev/null 2>&1; then
    emit_decision "deny" "policy_load_failed: yq not installed"
  fi
  if [[ ! -f "$POLICY_FILE" ]]; then
    emit_decision "deny" "policy_load_failed: $POLICY_FILE not found"
  fi
  if ! yq eval '.' "$POLICY_FILE" >/dev/null 2>&1; then
    emit_decision "deny" "policy_load_failed: invalid YAML in $POLICY_FILE"
  fi
  ENFORCEMENT="$(yq eval '.enforcement // "audit"' "$POLICY_FILE")"
  MAX_DIFF_FILES="$(yq eval '.max_diff_files // 0' "$POLICY_FILE")"
  REQUIRE_DISCLOSURE="$(yq eval '.require_disclosure // false' "$POLICY_FILE")"
  PROTECTED_PATHS=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && PROTECTED_PATHS+=("$line")
  done < <(yq eval '.protected_paths[]' "$POLICY_FILE" 2>/dev/null || true)
  DENIED_COMMANDS=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && DENIED_COMMANDS+=("$line")
  done < <(yq eval '.denied_commands[]' "$POLICY_FILE" 2>/dev/null || true)
}

match_protected_path() {
  local target="$1"
  [[ ${#PROTECTED_PATHS[@]} -eq 0 ]] && return 1
  local pattern
  for pattern in "${PROTECTED_PATHS[@]}"; do
    case "$target" in
      $pattern)
        echo "$pattern"
        return 0
        ;;
    esac
  done
  return 1
}

# match_denied_command: word-tokenized prefix matching against DENIED_COMMANDS
# Non-guarantee: does not catch variations like "rm -r -f" matching "rm -rf" (different token sequences)
# or "terraform -chdir=x apply" matching "terraform apply" (different token order).
match_denied_command() {
  local cmd="$1"
  [[ ${#DENIED_COMMANDS[@]} -eq 0 ]] && return 1
  local -a cmd_tokens
  read -ra cmd_tokens <<< "$cmd"
  local entry
  for entry in "${DENIED_COMMANDS[@]}"; do
    local -a entry_tokens
    read -ra entry_tokens <<< "$entry"
    (( ${#entry_tokens[@]} == 0 )) && continue
    local i matched=1
    for ((i = 0; i < ${#entry_tokens[@]}; i++)); do
      if [[ "${cmd_tokens[i]:-}" != "${entry_tokens[i]}" ]]; then
        matched=0
        break
      fi
    done
    if [[ $matched -eq 1 ]]; then
      echo "$entry"
      return 0
    fi
  done
  return 1
}

AUDIT_LOG=".ai-governance/audit.log"

log_audit() {
  local outcome="$1" rule="$2" target="$3"
  mkdir -p "$(dirname "$AUDIT_LOG")"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$MODE" "$outcome" "$rule" "$target" >> "$AUDIT_LOG"
  chmod 600 "$AUDIT_LOG" 2>/dev/null || true
}

decide() {
  local rule_fired="$1"
  local rule_id="$2"
  local target="$3"

  if [[ "$rule_fired" != "true" ]]; then
    emit_decision "allow"
  fi

  case "$ENFORCEMENT" in
    block)
      log_audit "deny" "$rule_id" "$target"
      emit_decision "deny" "$rule_id"
      ;;
    *)
      log_audit "would_deny" "$rule_id" "$target"
      emit_decision "allow"
      ;;
  esac
}

run_hook_mode() {
  local stdin_json
  stdin_json="$(cat)"

  local path command
  path="$(echo "$stdin_json" | jq -r '.toolArgs.path // .toolArgs.file_path // .tool_input.path // .tool_input.file_path // empty')"
  command="$(echo "$stdin_json" | jq -r '.toolArgs.command // .tool_input.command // empty')"

  if [[ -n "$command" ]]; then
    local matched
    if matched="$(match_denied_command "$command")"; then
      decide "true" "$matched" "$command"
    else
      decide "false" "" "$command"
    fi
  elif [[ -n "$path" ]]; then
    local matched
    if matched="$(match_protected_path "$path")"; then
      decide "true" "protected_paths: $matched ($path)" "$path"
    else
      decide "false" "" "$path"
    fi
  else
    emit_decision "allow"
  fi
}

run_ci_mode() {
  local -a changed_paths=()
  while IFS= read -r -d '' path; do
    changed_paths+=("$path")
  done

  if [[ ${#changed_paths[@]} -gt 0 ]]; then
    local path matched
    for path in "${changed_paths[@]}"; do
      if matched="$(match_protected_path "$path")"; then
        decide "true" "protected_paths: $matched ($path)" "$path"
      fi
    done
  fi

  local file_count=${#changed_paths[@]}
  if [[ "$MAX_DIFF_FILES" -gt 0 && "$file_count" -gt "$MAX_DIFF_FILES" ]]; then
    decide "true" "max_diff_files: $file_count > $MAX_DIFF_FILES" "$file_count files"
  fi

  if [[ "$REQUIRE_DISCLOSURE" == "true" && -n "$BASE_REF" ]]; then
    if ! git log "${BASE_REF}..HEAD" --format=%B 2>/dev/null \
        | grep -qiE 'co-authored-by:.*(copilot|claude)|ai-generated|ai-assisted'; then
      decide "true" "require_disclosure: no AI-attribution trailer found" "commit range"
    fi
  fi

  decide "false" "" ""
}

main() {
  load_policy
  case "$MODE" in
    hook) run_hook_mode ;;
    ci) run_ci_mode ;;  # implemented in Task 7
    *) usage ;;
  esac
}

if [[ "$SOURCE_ONLY" -eq 0 ]]; then
  main "$@"
fi

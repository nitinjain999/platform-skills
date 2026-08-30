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

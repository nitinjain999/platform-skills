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
  printf '"%s"' "$s"
}

emit_decision() {
  local decision="$1"
  local reason="${2:-}"

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

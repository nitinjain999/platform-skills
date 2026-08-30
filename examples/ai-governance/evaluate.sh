#!/usr/bin/env bash
set -uo pipefail

MODE=""
PLATFORM=""
EVENT=""
POLICY_FILE=".ai-governance.yaml"
BASE_REF=""
SOURCE_ONLY=0

usage() {
  echo "Usage: evaluate.sh --mode=hook|ci [--platform=copilot|claude|none] [--event=preToolUse|postToolUse] [--policy=<path>] [--base-ref=<ref>]" >&2
  echo "" >&2
  echo "  --platform=none   dry-run renderer used by 'check' mode: prints a platform-neutral" >&2
  echo "                    decision instead of a vendor envelope, and writes no audit log." >&2
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

# emit_decision <allow|deny> [reason] [rule_code] — never returns.
emit_decision() {
  local decision="$1"
  local reason="${2:-}"
  local rule_code="${3:-}"

  # --platform=none is the dry-run renderer behind `check` mode: a platform
  # engineer tuning policy needs the rule that fired, not a vendor transport
  # format. log_audit is suppressed for this platform too, so a dry run never
  # writes into the real audit trail.
  if [[ "$PLATFORM" == "none" ]]; then
    if [[ "$decision" == "deny" ]]; then
      printf '{"decision":"deny","rule":%s,"reason":%s}\n' \
        "$(json_string "$rule_code")" "$(json_string "$reason")"
      exit 2
    else
      printf '{"decision":"allow"}\n'
      exit 0
    fi
  fi

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
    emit_decision "deny" "policy_load_failed: yq not installed" "policy_load_failed"
  fi
  if [[ ! -f "$POLICY_FILE" ]]; then
    emit_decision "deny" "policy_load_failed: $POLICY_FILE not found" "policy_load_failed"
  fi
  if ! yq eval '.' "$POLICY_FILE" >/dev/null 2>&1; then
    emit_decision "deny" "policy_load_failed: invalid YAML in $POLICY_FILE" "policy_load_failed"
  fi
  # Syntax-valid YAML can still be the wrong shape (`protected_paths: "x"`
  # instead of a list). `.protected_paths[]` on a scalar errors, the `2>/dev/null
  # || true` below swallows that error to keep a genuinely-empty/absent list
  # working, and the two look identical from the loop's side: PROTECTED_PATHS
  # ends up empty either way. An empty PROTECTED_PATHS means match_protected_path
  # denies nothing — so a type mistake here silently disables every protected
  # path instead of failing closed. Reject the wrong type before that happens.
  local field field_type
  for field in protected_paths denied_commands; do
    field_type="$(yq eval ".${field} | type" "$POLICY_FILE" 2>/dev/null)"
    case "$field_type" in
      '!!seq' | '!!null' | '') ;;
      *) emit_decision "deny" "policy_load_failed: .${field} must be a list, got ${field_type}" "policy_load_failed" ;;
    esac
  done
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
  local root_pattern
  for pattern in "${PROTECTED_PATHS[@]}"; do
    # Unquoted on purpose: the unquoted expansion IS the glob mechanism. This is
    # what makes `.github/workflows/**` a pattern rather than a literal filename,
    # and it works on bash 3.2 where `globstar`/`extglob` are unavailable.
    # shellcheck disable=SC2254
    case "$target" in
      $pattern)
        echo "$pattern"
        return 0
        ;;
    esac
    # `**` here is just two `*` characters, not bash's globstar — a leading
    # `**/` still demands a literal `/` before the rest of the pattern, so
    # `**/secrets/**` silently misses a root-level `secrets/token` even though
    # a human author intends "at any depth, including the root." Also try the
    # pattern with that prefix stripped, so the root case matches too.
    if [[ "$pattern" == '**/'* ]]; then
      root_pattern="${pattern#\*\*/}"
      # shellcheck disable=SC2254
      case "$target" in
        $root_pattern)
          echo "$pattern"
          return 0
          ;;
      esac
    fi
  done
  return 1
}

# The governance assets are hardcoded, not read from the policy file: the whole
# point of the self-disable rule is that it cannot be weakened by editing the
# policy it protects. `case` glob matching is plain string matching, so `**`
# spans `/` — `.ai-governance/**` covers `.ai-governance/policies/x/y.yaml`.
GOVERNANCE_ASSETS=(
  ".ai-governance.yaml"
  ".ai-governance/**"
  ".github/hooks/**"
  ".github/workflows/ai-governance-check.yml"
  ".claude/settings.json"
)

match_governance_asset() {
  local target="$1"
  local pattern
  for pattern in "${GOVERNANCE_ASSETS[@]}"; do
    # Unquoted on purpose — same glob-via-`case` mechanism as match_protected_path.
    # shellcheck disable=SC2254
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

# Tab-separated: timestamp, mode, outcome, rule_code, detail, target.
# rule_code is a short, stable identifier (protected_paths, denied_commands,
# max_diff_files, require_disclosure, self_disable, policy_load_failed,
# post_tool_use) so log aggregation never has to parse prose; detail carries
# the human-readable specifics.
log_audit() {
  local outcome="$1" rule_code="$2" detail="$3" target="$4"
  # A dry run (`check`, i.e. --platform=none) must not pollute the real trail.
  [[ "$PLATFORM" == "none" ]] && return 0
  mkdir -p "$(dirname "$AUDIT_LOG")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$MODE" "$outcome" "$rule_code" "$detail" "$target" >> "$AUDIT_LOG"
  chmod 600 "$AUDIT_LOG" 2>/dev/null || true
}

reason_string() {
  local rule_code="$1" detail="$2"
  if [[ -n "$detail" ]]; then
    printf '%s: %s' "$rule_code" "$detail"
  else
    printf '%s' "$rule_code"
  fi
}

# tier_outcome [force_deny] — maps the enforcement tier to an audit outcome:
#   block  -> deny             (the call or PR is actually blocked)
#   warn   -> would_deny_warn  (allowed; the CI workflow posts a PR comment)
#   audit  -> would_deny       (allowed; logged only)
# Any unrecognized tier falls back to `audit`'s behavior.
# A non-empty force_deny overrides the tier entirely. Only the CI self-disable
# rule uses it: a diff that touches a governance asset alongside another
# protected path denies under every tier, so a team still onboarding under
# `audit` cannot have its own governance config quietly switched off.
tier_outcome() {
  if [[ -n "${1:-}" ]]; then
    echo "deny"
  elif [[ "$ENFORCEMENT" == "block" ]]; then
    echo "deny"
  elif [[ "$ENFORCEMENT" == "warn" ]]; then
    echo "would_deny_warn"
  else
    echo "would_deny"
  fi
}

# decide <rule_fired: true|false> <rule_code> <detail> [target] [force_deny]
# Writes the audit line, then renders the decision. Never returns.
decide() {
  local rule_fired="$1"
  local rule_code="$2"
  local detail="$3"
  local target="${4:-}"
  local force_deny="${5:-}"

  if [[ "$rule_fired" != "true" ]]; then
    emit_decision "allow"
  fi

  local outcome
  outcome="$(tier_outcome "$force_deny")"
  log_audit "$outcome" "$rule_code" "$detail" "$target"

  if [[ "$outcome" == "deny" ]]; then
    emit_decision "deny" "$(reason_string "$rule_code" "$detail")" "$rule_code"
  else
    emit_decision "allow"
  fi
}

# Tool names that only read. Anything else carrying a path is treated as write
# intent — fail-closed, because write-tool names vary across platforms and
# versions while the read-only set is small and stable.
READ_ONLY_TOOLS="read view cat glob grep search find ls list notebookread webfetch websearch"

# is_write_intent <tool_name> <has_write_field>
is_write_intent() {
  local tool_name="$1" has_write_field="$2"
  # An edit payload is write intent whatever the tool happens to be called.
  [[ "$has_write_field" == "true" ]] && return 0
  local lowered t
  lowered="$(printf '%s' "$tool_name" | tr '[:upper:]' '[:lower:]')"
  for t in $READ_ONLY_TOOLS; do
    [[ "$lowered" == "$t" ]] && return 1
  done
  return 0
}

is_post_event() {
  case "$(printf '%s' "$EVENT" | tr '[:upper:]' '[:lower:]')" in
    posttooluse) return 0 ;;
  esac
  return 1
}

run_hook_mode() {
  local stdin_json
  stdin_json="$(cat)"

  local tool_name path command has_write_field
  tool_name="$(echo "$stdin_json" | jq -r '.toolName // .tool_name // empty')"
  path="$(echo "$stdin_json" | jq -r '.toolArgs.path // .toolArgs.file_path // .tool_input.path // .tool_input.file_path // empty')"
  command="$(echo "$stdin_json" | jq -r '.toolArgs.command // .tool_input.command // empty')"
  has_write_field="$(echo "$stdin_json" | jq -r '
    ((.tool_input // .toolArgs) // {})
    | if type == "object"
        and (has("new_string") or has("old_string") or has("content")
             or has("edits") or has("replace_all"))
      then "true" else "false" end')"

  if [[ -n "$command" ]]; then
    local matched
    if matched="$(match_denied_command "$command")"; then
      decide "true" "denied_commands" "$matched" "$command"
    else
      decide "false" "" "" "$command"
    fi
  elif [[ -n "$path" ]]; then
    # protected_paths gates writes, not reads. Denying a Read against a
    # protected path makes `block` tier unusable in practice — a developer
    # cannot even open the file to look at it — and the predictable response
    # is to remove the hook, which is the worst outcome for a governance tool.
    # denied_commands is unaffected: that branch is gated on `command`, above.
    if ! is_write_intent "$tool_name" "$has_write_field"; then
      decide "false" "" "" "$path"
    fi
    local matched
    if matched="$(match_protected_path "$path")"; then
      decide "true" "protected_paths" "$matched ($path)" "$path"
    else
      decide "false" "" "" "$path"
    fi
  else
    emit_decision "allow"
  fi
}

# postToolUse fires only for calls that actually ran, so there is nothing left
# to decide. Re-running the rules here would duplicate the audit line the
# preToolUse invocation already wrote (visible under `audit`/`warn`, where the
# call is allowed and therefore does complete). It records a completion and
# exits 0 with no decision body — PostToolUse is not a permission event on
# either platform.
run_post_hook_mode() {
  local stdin_json
  stdin_json="$(cat)"

  local tool_name target
  tool_name="$(echo "$stdin_json" | jq -r '.toolName // .tool_name // empty')"
  target="$(echo "$stdin_json" | jq -r '
    .toolArgs.path // .toolArgs.file_path // .toolArgs.command //
    .tool_input.path // .tool_input.file_path // .tool_input.command // empty')"

  log_audit "completed" "post_tool_use" "${tool_name:-unknown}" "$target"
  exit 0
}

run_ci_mode() {
  local -a changed_paths=()
  while IFS= read -r -d '' path; do
    changed_paths+=("$path")
  done

  # Accumulate every violation before deciding. decide()/emit_decision() always
  # exit, so calling decide inside the loop below would stop at the first
  # protected-path hit and never reach max_diff_files or require_disclosure —
  # which defeats the whole point of evaluating the diff in one pass.
  local -a v_codes=() v_details=() v_targets=()
  local governance_asset="" other_protected=""

  if [[ ${#changed_paths[@]} -gt 0 ]]; then
    local path matched
    for path in "${changed_paths[@]}"; do
      matched="$(match_protected_path "$path")" || matched=""
      if [[ -n "$matched" ]]; then
        v_codes+=("protected_paths")
        v_details+=("$matched ($path)")
        v_targets+=("$path")
      fi
      if match_governance_asset "$path" >/dev/null 2>&1; then
        governance_asset="$path"
      elif [[ -n "$matched" ]]; then
        other_protected="$path"
      fi
    done
  fi

  # Self-disable: a governance asset changed in the same diff as some other
  # protected path. Denies regardless of tier — see tier_outcome.
  local force_deny=""
  if [[ -n "$governance_asset" && -n "$other_protected" ]]; then
    force_deny="self_disable"
    v_codes+=("self_disable")
    v_details+=("$governance_asset changed alongside $other_protected")
    v_targets+=("$governance_asset")
  fi

  local file_count=${#changed_paths[@]}
  if [[ "$MAX_DIFF_FILES" -gt 0 && "$file_count" -gt "$MAX_DIFF_FILES" ]]; then
    v_codes+=("max_diff_files")
    v_details+=("$file_count > $MAX_DIFF_FILES")
    v_targets+=("$file_count files")
  fi

  if [[ "$REQUIRE_DISCLOSURE" == "true" ]]; then
    if [[ -z "$BASE_REF" ]]; then
      # A required control must not disappear because an optional flag was
      # left off. Without --base-ref there is no commit range to inspect, so
      # this is a violation in its own right, not a reason to skip the rule.
      v_codes+=("require_disclosure")
      v_details+=("require_disclosure is enabled but --base-ref was not given, so the commit range could not be checked")
      v_targets+=("(no base-ref)")
    elif ! git log "${BASE_REF}..HEAD" --format=%B 2>/dev/null \
        | grep -qiE 'co-authored-by:.*(copilot|claude)|ai-generated|ai-assisted'; then
      v_codes+=("require_disclosure")
      v_details+=("no AI-attribution trailer found in ${BASE_REF}..HEAD")
      v_targets+=("commit range")
    fi
  fi

  if [[ ${#v_codes[@]} -eq 0 ]]; then
    decide "false" "" "" ""
  fi

  local outcome
  outcome="$(tier_outcome "$force_deny")"

  # One audit line per violation: the log has to show everything the diff
  # actually tripped, not just whichever rule happened to fire first.
  local i
  for ((i = 0; i < ${#v_codes[@]}; i++)); do
    log_audit "$outcome" "${v_codes[i]}" "${v_details[i]}" "${v_targets[i]}"
  done

  if [[ "$outcome" == "deny" ]]; then
    local reason="" seen_codes="" codes=""
    for ((i = 0; i < ${#v_codes[@]}; i++)); do
      [[ -n "$reason" ]] && reason="$reason; "
      reason="$reason$(reason_string "${v_codes[i]}" "${v_details[i]}")"
      case " $seen_codes " in
        *" ${v_codes[i]} "*) ;;
        *)
          seen_codes="${seen_codes:+$seen_codes }${v_codes[i]}"
          codes="${codes:+$codes,}${v_codes[i]}"
          ;;
      esac
    done
    emit_decision "deny" "$reason" "$codes"
  fi

  emit_decision "allow"
}

main() {
  # postToolUse records a completion and nothing else — no policy needed, and a
  # policy_load_failed deny would be meaningless for a call that already ran.
  if [[ "$MODE" == "hook" ]] && is_post_event; then
    run_post_hook_mode
  fi

  load_policy
  case "$MODE" in
    hook) run_hook_mode ;;
    ci) run_ci_mode ;;
    *) usage ;;
  esac
}

if [[ "$SOURCE_ONLY" -eq 0 ]]; then
  main "$@"
fi

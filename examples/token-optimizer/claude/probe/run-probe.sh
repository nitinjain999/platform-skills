#!/usr/bin/env bash
# Records whether Claude Code delegation actually works on THIS client version.
# Frontmatter parsing is not evidence of an execution model — this probe answers
# three separate questions and writes the answers to fixture.json.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/fixture.json"

CLIENT_VERSION="$(claude --version 2>/dev/null | head -1)"
[[ -n "$CLIENT_VERSION" ]] || { echo "claude CLI not found on PATH"; exit 1; }

# The requested model has to be read from THIS installation, not hardcoded.
# A literal "haiku" here made the fixture assert a model the user may never have
# chosen: setup rewrites the installed agent's `model:` to whatever was picked,
# so a user on gpt-5-mini got a fixture claiming haiku was requested. That
# defeats the whole point of separating "requested" from "observed".
find_up() {
  # find_up <relative-path> -> absolute path on stdout, or non-zero
  local rel="${1:?}" dir="$PWD"
  while :; do
    if [[ -e "$dir/$rel" ]]; then printf '%s' "$dir/$rel"; return 0; fi
    if [[ "$dir" == "/" || -z "$dir" ]]; then return 1; fi
    dir="$(dirname "$dir")"
  done
}

CONFIG_FILE="${TOKEN_OPTIMIZER_CONFIG:-}"
if [[ -z "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$(find_up .token-optimizer.yaml)" || CONFIG_FILE=""
fi
AGENT_FILE="${TOKEN_OPTIMIZER_AGENT:-}"
if [[ -z "$AGENT_FILE" ]]; then
  AGENT_FILE="$(find_up .claude/agents/platform-bulk-reader.md)" || AGENT_FILE=""
fi

MODEL_CONFIG=""
if [[ -n "$CONFIG_FILE" && -r "$CONFIG_FILE" ]]; then
  MODEL_CONFIG="$(awk '/^[[:space:]]*worker_model:[[:space:]]*/ {
      sub(/^[[:space:]]*worker_model:[[:space:]]*/, "")
      sub(/[[:space:]]*(#.*)?$/, ""); gsub(/^["'\'']|["'\'']$/, "")
      print; exit }' "$CONFIG_FILE")"
fi

MODEL_FRONTMATTER=""
if [[ -n "$AGENT_FILE" && -r "$AGENT_FILE" ]]; then
  # Only the first frontmatter block, so a `model:` mentioned in prose below it
  # cannot be mistaken for the declaration.
  MODEL_FRONTMATTER="$(awk '
      /^---[[:space:]]*$/ { n++; if (n >= 2) exit; next }
      n == 1 && /^model:[[:space:]]*/ {
        sub(/^model:[[:space:]]*/, ""); sub(/[[:space:]]*$/, "")
        gsub(/^["'\'']|["'\'']$/, ""); print; exit }' "$AGENT_FILE")"
fi

# Config is what the user asked for, so it wins. Frontmatter is the fallback for
# an install where the config is gone but the agent is still in place.
MODEL_SOURCE="none"
MODEL_REQUESTED="unknown"
if [[ -n "$MODEL_CONFIG" ]]; then
  MODEL_REQUESTED="$MODEL_CONFIG"; MODEL_SOURCE="config:$CONFIG_FILE"
elif [[ -n "$MODEL_FRONTMATTER" ]]; then
  MODEL_REQUESTED="$MODEL_FRONTMATTER"; MODEL_SOURCE="frontmatter:$AGENT_FILE"
fi

# A disagreement means setup's rewrite did not land. Record it rather than
# quietly preferring one value.
if [[ -n "$MODEL_CONFIG" && -n "$MODEL_FRONTMATTER" && "$MODEL_CONFIG" != "$MODEL_FRONTMATTER" ]]; then
  MODEL_SOURCE="$MODEL_SOURCE (FRONTMATTER DISAGREES: $MODEL_FRONTMATTER)"
fi

cat <<EOF
Probe: Claude Code delegation
Client:           $CLIENT_VERSION
Requested model:  $MODEL_REQUESTED ($MODEL_SOURCE)

This probe cannot be fully automated — questions 1 and 2 need a human to read a
real session transcript. Run the three checks below, then record the answers.

  1. WORKER INVOKED
     Ask the main agent to delegate a discovery question to platform-bulk-reader.
     In the transcript, confirm a subagent was actually dispatched — not the main
     agent answering in the worker's voice. Look for a distinct agent turn.

  2. INDEPENDENT CONTEXT
     In the same session, confirm the worker did not receive the parent
     conversation. Ask the worker something only the parent discussed. It should
     not know the answer.

  3. RETURN TO PARENT
     Confirm control and a bounded result came back to the parent, and that the
     parent continued the original task.

  4. RESOLVED MODEL
     Confirm which model the worker actually ran. This installation requests
     '$MODEL_REQUESTED'; an Auto session or a provider override can resolve
     something else. Record the resolved id and how you observed it.
EOF

read -r -p "1. Worker invoked?         (yes/no) " Q1
read -r -p "2. Independent context?    (yes/no) " Q2
read -r -p "3. Returned to parent?     (yes/no) " Q3
read -r -p "4. Resolved worker model:           " Q4
read -r -p "   How was that observed:           " Q4SRC

VERIFIED=false
[[ "$Q1" == "yes" && "$Q2" == "yes" && "$Q3" == "yes" ]] && VERIFIED=true

cat > "$OUT" <<EOF
{
  "probe_version": 1,
  "client": "claude-code",
  "client_version": "$CLIENT_VERSION",
  "recorded_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "worker_invoked": $([[ "$Q1" == "yes" ]] && echo true || echo false),
  "independent_context": $([[ "$Q2" == "yes" ]] && echo true || echo false),
  "returned_to_parent": $([[ "$Q3" == "yes" ]] && echo true || echo false),
  "delegation_verified": $VERIFIED,
  "worker_model_requested": "$MODEL_REQUESTED",
  "worker_model_requested_source": "$MODEL_SOURCE",
  "worker_model_resolved": "$Q4",
  "model_verification_source": "$Q4SRC"
}
EOF

echo ""
echo "Recorded to $OUT"
echo "delegation_verified = $VERIFIED"
echo ""
echo "This fixture is valid ONLY for $CLIENT_VERSION. A client upgrade"
echo "invalidates it and doctor will report delegation as unverified again."

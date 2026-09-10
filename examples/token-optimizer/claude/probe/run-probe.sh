#!/usr/bin/env bash
# Records whether Claude Code delegation actually works on THIS client version.
# Frontmatter parsing is not evidence of an execution model — this probe answers
# three separate questions and writes the answers to fixture.json.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/fixture.json"

CLIENT_VERSION="$(claude --version 2>/dev/null | head -1)"
[[ -n "$CLIENT_VERSION" ]] || { echo "claude CLI not found on PATH"; exit 1; }

cat <<EOF
Probe: Claude Code delegation
Client: $CLIENT_VERSION

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
     Confirm which model the worker actually ran. Frontmatter says 'haiku'; an
     Auto session or a provider override can resolve something else. Record the
     resolved id and how you observed it.
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
  "worker_model_requested": "haiku",
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

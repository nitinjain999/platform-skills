#!/usr/bin/env bash
# ai-governance-hook.sh — run the ai-governance policy gate only in projects
# that opted in by committing .ai-governance.yaml.
#
# evaluate.sh fails closed: with no policy file it denies every tool call.
# That is right inside a governed project and wrong everywhere else, and a
# plugin hook fires in every project the user opens. So this wrapper is the
# opt-in boundary: no policy file, no gate. With one, every decision is
# evaluate.sh's, unchanged, including fail-closed on a broken policy.
set -euo pipefail
project="${CLAUDE_PROJECT_DIR:-$PWD}"
policy="$project/.ai-governance.yaml"
if [ ! -f "$policy" ]; then
  # Not a governed project: let the tool call through without reading stdin.
  exit 0
fi
cd "$project"
exec bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/ai-governance-evaluate.sh" --mode=hook --platform=claude --policy="$policy" "$@"

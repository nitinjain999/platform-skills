#!/usr/bin/env bash
# On PATH while platform-guardrails is enabled, so the self-improve skill can
# call `learnings.sh <subcommand>` without copying the script by hand.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/learnings.sh" "$@"

#!/usr/bin/env bash
# Run the installed scanner; never fetch or install code from a Git hook.
set -euo pipefail

if ! command -v kingfisher >/dev/null 2>&1; then
  echo "Kingfisher is not on PATH. Install the pinned scanner before committing." >&2
  exit 127
fi

cd -- "$(git rev-parse --show-toplevel)"
exec kingfisher scan . --staged --quiet --no-update-check

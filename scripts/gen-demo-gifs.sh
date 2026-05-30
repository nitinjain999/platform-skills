#!/usr/bin/env bash
# Generate GIF recordings for all demo tape files.
# Run this locally before committing when you add or edit a demo.tape file.
#
# Usage: ./scripts/gen-demo-gifs.sh [domain]
#   domain — optional, e.g. "kubernetes-prod-review". Runs all domains if omitted.
#
# Requirements: vhs (brew install vhs)

set -euo pipefail

DEMO_DIR="examples/demo"
FILTER="${1:-}"

if ! command -v vhs &>/dev/null; then
  echo "ERROR: vhs is not installed."
  echo "Install it with: brew install vhs"
  exit 1
fi

TAPES=()
if [[ -n "$FILTER" ]]; then
  TAPES=("$DEMO_DIR/$FILTER/demo.tape")
else
  while IFS= read -r tape; do
    TAPES+=("$tape")
  done < <(find "$DEMO_DIR" -name "demo.tape" | sort)
fi

if [[ ${#TAPES[@]} -eq 0 ]]; then
  echo "No demo.tape files found in $DEMO_DIR"
  exit 1
fi

echo "Generating ${#TAPES[@]} GIF(s)..."
echo ""

PASS=0
FAIL=0

for tape in "${TAPES[@]}"; do
  dir=$(dirname "$tape")
  domain=$(basename "$dir")
  echo "── $domain"
  if (cd "$dir" && vhs demo.tape 2>&1 | tail -1); then
    echo "   ✅ $dir/demo.gif"
    PASS=$((PASS + 1))
  else
    echo "   ❌ failed"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "Done: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi

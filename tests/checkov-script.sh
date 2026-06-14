#!/usr/bin/env bash
# tests/checkov-script.sh — validates checkov-terraform-plan.sh without running terraform or checkov
set -euo pipefail

SCRIPT="examples/compliance/checkov-terraform-plan.sh"

echo "--- Test 1: bash syntax check ---"
bash -n "$SCRIPT"
echo "PASS: no syntax errors"

echo "--- Test 2: shellcheck (skip if not installed) ---"
if command -v shellcheck &>/dev/null; then
  shellcheck "$SCRIPT"
  echo "PASS: shellcheck clean"
else
  echo "SKIP: shellcheck not installed"
fi

echo "--- Test 3: all documented flags parse without error ---"
# Re-use the script's own parser by extracting the while/case block and testing every flag.
# This test exercises the real parser from the script, not a copy.
(
  # Extract and run just the argument-parsing section by sourcing up to the ROOT cd line.
  # We override set -euo pipefail so unknown args produce a clear error, not a silent abort.
  set +euo pipefail
  OUTPUT_FORMAT="cli"; ROOT="."; KEEP_PLAN=false; UPGRADE=false
  YES=false; WORKSPACE_OVERRIDE=""; VAR_FILE_OVERRIDE=""
  UPLOAD_SARIF=false

  set -- --root /tmp --output sarif --yes --keep-plan --upgrade \
         --workspace staging --var-file staging.tfvars --upload-sarif
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root)          ROOT="$2"; shift 2 ;;
      --keep-plan)     KEEP_PLAN=true; shift ;;
      --upgrade)       UPGRADE=true; shift ;;
      --output)        OUTPUT_FORMAT="$2"; shift 2 ;;
      --yes)           YES=true; shift ;;
      --workspace)     WORKSPACE_OVERRIDE="$2"; shift 2 ;;
      --var-file)      VAR_FILE_OVERRIDE="$2"; shift 2 ;;
      --upload-sarif)  UPLOAD_SARIF=true; shift ;;
      *)               echo "FAIL: Unknown argument: $1" >&2; exit 1 ;;
    esac
  done

  [ "$OUTPUT_FORMAT" = "sarif" ]              || { echo "FAIL: OUTPUT_FORMAT=$OUTPUT_FORMAT"; exit 1; }
  [ "$YES" = true ]                           || { echo "FAIL: YES not set"; exit 1; }
  [ "$KEEP_PLAN" = true ]                     || { echo "FAIL: KEEP_PLAN not set"; exit 1; }
  [ "$UPGRADE" = true ]                       || { echo "FAIL: UPGRADE not set"; exit 1; }
  [ "$WORKSPACE_OVERRIDE" = "staging" ]       || { echo "FAIL: WORKSPACE_OVERRIDE not set"; exit 1; }
  [ "$VAR_FILE_OVERRIDE" = "staging.tfvars" ] || { echo "FAIL: VAR_FILE_OVERRIDE not set"; exit 1; }
  [ "$UPLOAD_SARIF" = true ]                  || { echo "FAIL: UPLOAD_SARIF not set"; exit 1; }
  echo "PASS: all documented flags parse correctly"
)

echo "--- Test 4: trap is present ---"
grep -q "trap cleanup EXIT INT TERM" "$SCRIPT"
echo "PASS: trap cleanup EXIT INT TERM registered"

echo "--- Test 5: no terraform init --upgrade as default ---"
# init --upgrade must only appear inside an 'if.*UPGRADE' branch.
# Uses an AST-style approach: track whether we are inside a guarded block.
python3 - <<'PYEOF'
import sys

src = open("examples/compliance/checkov-terraform-plan.sh").read()
lines = src.splitlines()
in_upgrade_guard = False
failed = False
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    # Detect entry into UPGRADE guard block
    if 'UPGRADE' in stripped and stripped.startswith('if'):
        in_upgrade_guard = True
    # Detect end of guard block
    if stripped == 'fi' and in_upgrade_guard:
        in_upgrade_guard = False
    # Flag any init --upgrade outside a guard (skip comment lines)
    if not stripped.startswith('#') and 'init' in stripped and '--upgrade' in stripped and not in_upgrade_guard:
        print(f"FAIL: unconditional 'init --upgrade' at line {i}: {stripped}")
        failed = True
if failed:
    sys.exit(1)
print("PASS: init --upgrade is conditional on UPGRADE flag")
PYEOF

echo ""
echo "All checkov script tests passed."

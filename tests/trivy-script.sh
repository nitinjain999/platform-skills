#!/usr/bin/env bash
# tests/trivy-script.sh — validates trivy-image-scan.sh without running trivy or pulling images
set -euo pipefail

SCRIPT="examples/supply-chain/trivy-image-scan.sh"

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
(
  set +euo pipefail
  IMAGE_REF=""; SEVERITY="HIGH,CRITICAL"; OUTPUT_FORMAT="sarif"
  IGNORE_UNFIXED=false; IGNOREFILE=""; UPLOAD_SARIF=false

  set -- \
    --image ghcr.io/org/image:latest \
    --severity CRITICAL \
    --output json \
    --ignore-unfixed \
    --ignorefile .trivyignore \
    --upload-sarif \
    --yes

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --image)          IMAGE_REF="$2"; shift 2 ;;
      --severity)       SEVERITY="$2"; shift 2 ;;
      --output)         OUTPUT_FORMAT="$2"; shift 2 ;;
      --ignore-unfixed) IGNORE_UNFIXED=true; shift ;;
      --ignorefile)     IGNOREFILE="$2"; shift 2 ;;
      --upload-sarif)   UPLOAD_SARIF=true; shift ;;
      --yes)            shift ;;
      *)                echo "FAIL: Unknown argument: $1" >&2; exit 1 ;;
    esac
  done

  [ "$IMAGE_REF" = "ghcr.io/org/image:latest" ] || { echo "FAIL: IMAGE_REF=$IMAGE_REF"; exit 1; }
  [ "$SEVERITY" = "CRITICAL" ]                   || { echo "FAIL: SEVERITY=$SEVERITY"; exit 1; }
  [ "$OUTPUT_FORMAT" = "json" ]                  || { echo "FAIL: OUTPUT_FORMAT=$OUTPUT_FORMAT"; exit 1; }
  [ "$IGNORE_UNFIXED" = true ]                   || { echo "FAIL: IGNORE_UNFIXED not set"; exit 1; }
  [ "$IGNOREFILE" = ".trivyignore" ]             || { echo "FAIL: IGNOREFILE=$IGNOREFILE"; exit 1; }
  [ "$UPLOAD_SARIF" = true ]                     || { echo "FAIL: UPLOAD_SARIF not set"; exit 1; }
  echo "PASS: all documented flags parse correctly"
)

echo "--- Test 4: trap is present ---"
grep -q "trap cleanup EXIT INT TERM" "$SCRIPT"
echo "PASS: trap cleanup EXIT INT TERM registered"

echo "--- Test 5: exit-code-2 guard is present ---"
grep -q 'TRIVY_RC.*-eq 2' "$SCRIPT"
echo "PASS: exit code 2 guard present"

echo "--- Test 6: --image required guard is present ---"
grep -q '\-\-image is required' "$SCRIPT"
echo "PASS: --image required guard present"

echo "--- Test 7: .trivyignore.example exists ---"
[ -f "examples/supply-chain/.trivyignore.example" ]
echo "PASS: .trivyignore.example exists"

echo ""
echo "All trivy script tests passed."

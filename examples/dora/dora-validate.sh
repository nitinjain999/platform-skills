#!/usr/bin/env bash
# Run from repository root: bash examples/dora/dora-validate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
FAILURES=()

# Colour helpers (no-op if not a terminal)
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  NC='\033[0m'
else
  RED='' GREEN='' NC=''
fi

pass() { echo -e "${GREEN}PASS${NC}  $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}FAIL${NC}  $1 — $2"; FAIL=$((FAIL + 1)); FAILURES+=("$1"); }

# ---------------------------------------------------------------------------
# YAML validation — requires yq v4+
# ---------------------------------------------------------------------------
if ! command -v yq &>/dev/null; then
  echo "WARNING: yq not found — skipping YAML validation" >&2
else
  for yaml_file in "${SCRIPT_DIR}"/*.yaml; do
    filename="$(basename "${yaml_file}")"
    if yq eval 'true' "${yaml_file}" &>/dev/null; then
      pass "${filename}"
    else
      fail "${filename}" "yq reported invalid YAML"
    fi
  done
fi

# ---------------------------------------------------------------------------
# JSON validation — prefer jq, fall back to python3
# Covers grafana-dashboard.json and amp-variant/*.json
# ---------------------------------------------------------------------------
validate_json() {
  local json_file="$1"
  local filename
  filename="$(basename "${json_file}")"
  if command -v jq &>/dev/null; then
    if jq . "${json_file}" &>/dev/null; then
      pass "${filename}"
    else
      fail "${filename}" "jq reported invalid JSON"
    fi
  elif command -v python3 &>/dev/null; then
    if python3 -c "import json, sys; json.load(sys.stdin)" < "${json_file}" &>/dev/null; then
      pass "${filename}"
    else
      fail "${filename}" "python3 reported invalid JSON"
    fi
  else
    echo "WARNING: neither jq nor python3 found — skipping JSON validation" >&2
  fi
}

validate_json "${SCRIPT_DIR}/grafana-dashboard.json"

# ---------------------------------------------------------------------------
# AMP variant — YAML and JSON files
# ---------------------------------------------------------------------------
AMP_DIR="${SCRIPT_DIR}/amp-variant"
if [[ -d "$AMP_DIR" ]]; then
  if ! command -v yq &>/dev/null; then
    echo "WARNING: yq not found — skipping amp-variant YAML validation" >&2
  else
    for yaml_file in "${AMP_DIR}"/*.yaml; do
      [[ -e "$yaml_file" ]] || continue
      filename="amp-variant/$(basename "${yaml_file}")"
      if yq eval 'true' "${yaml_file}" &>/dev/null; then
        pass "${filename}"
      else
        fail "${filename}" "yq reported invalid YAML"
      fi
    done
  fi
  for json_file in "${AMP_DIR}"/*.json; do
    [[ -e "$json_file" ]] || continue
    validate_json "${json_file}"
  done
  # Verify the Terraform file is present (syntax validation requires terraform init;
  # we only check existence here so the validator passes without network access).
  tf_file="${AMP_DIR}/amp-workspace.tf"
  if [[ -f "$tf_file" ]]; then
    pass "amp-variant/amp-workspace.tf"
  else
    fail "amp-variant/amp-workspace.tf" "file missing"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
  echo ""
  echo "Failed files:"
  for f in "${FAILURES[@]}"; do
    echo "  - ${f}"
  done
  exit 1
fi

#!/usr/bin/env bash
# examples/supply-chain/trivy-image-scan.sh
#
# SCOPE: CI helper script — container image CVE scan with severity gate,
# SARIF output, and optional upload to GitHub Security tab.
#
# This script is intentionally narrower than /platform-skills:trivy (which is
# the source of truth for the full command). It does NOT implement fs/repo/sbom/k8s
# modes; those are slash-command concerns. Use this script directly in CI jobs
# where you need a self-contained Bash executable for image scanning.
#
# Usage:
#   ./trivy-image-scan.sh \
#     --image <ref>                   Image to scan (required)
#     [--severity HIGH,CRITICAL]      Severity floor (default: HIGH,CRITICAL)
#     [--output sarif|json|table]     Output format (default: sarif in CI, table locally)
#     [--ignore-unfixed]              Suppress CVEs with no upstream fix
#     [--ignorefile .trivyignore]     Path to .trivyignore (default: .trivyignore if present)
#     [--upload-sarif]                Upload trivy-results.sarif to GitHub Security tab
#                                     (requires gh CLI + security-events: write permission)
#     [--yes]                         Skip interactive prompts
#
# Requirements: trivy >= 0.50.0
# Optional:     gh CLI (for --upload-sarif only)

set -euo pipefail

IMAGE_REF=""
SEVERITY="HIGH,CRITICAL"
OUTPUT_FORMAT="sarif"
IGNORE_UNFIXED=false
IGNOREFILE=""
UPLOAD_SARIF=false
SARIF_FILE="trivy-results.sarif"
JSON_FILE="trivy-results.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)          IMAGE_REF="$2"; shift 2 ;;
    --severity)       SEVERITY="$2"; shift 2 ;;
    --output)         OUTPUT_FORMAT="$2"; shift 2 ;;
    --ignore-unfixed) IGNORE_UNFIXED=true; shift ;;
    --ignorefile)     IGNOREFILE="$2"; shift 2 ;;
    --upload-sarif)   UPLOAD_SARIF=true; shift ;;
    --yes)            shift ;;  # accepted for script compatibility; no interactive prompts in this script
    *)                echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- Validate required inputs ---
if [[ -z "$IMAGE_REF" ]]; then
  echo "ERROR: --image is required" >&2
  echo "Usage: $0 --image ghcr.io/org/image:tag [options]" >&2
  exit 1
fi

# --- Bootstrap check ---
if ! command -v trivy &>/dev/null; then
  echo "ERROR: trivy not found. Run /platform-skills:trivy to install it." >&2
  exit 1
fi

# Minimum version guard
MIN_VERSION="0.50.0"
CURRENT=$(trivy --version 2>/dev/null | awk '/Version:/{print $2}')
if [[ -n "$CURRENT" ]]; then
  if ! printf '%s\n%s\n' "$MIN_VERSION" "$CURRENT" | sort -V -C; then
    echo "ERROR: trivy >= $MIN_VERSION required (found $CURRENT)" >&2
    exit 1
  fi
fi

# --- Auto-detect .trivyignore ---
if [[ -z "$IGNOREFILE" && -f ".trivyignore" ]]; then
  IGNOREFILE=".trivyignore"
fi

# --- Guaranteed cleanup via trap ---
# shellcheck disable=SC2317  # cleanup() is called via trap, not directly
cleanup() {
  : # SARIF and JSON are kept for CI artifact upload; no temp files to remove
}
trap cleanup EXIT INT TERM

# --- Build trivy command ---
TRIVY_ARGS=()
TRIVY_ARGS+=(image --severity "$SEVERITY" --exit-code 1 --vuln-type os,library)

if [[ "$OUTPUT_FORMAT" == "sarif" ]]; then
  TRIVY_ARGS+=(--format sarif --output "$SARIF_FILE")
elif [[ "$OUTPUT_FORMAT" == "json" ]]; then
  TRIVY_ARGS+=(--format json --output "$JSON_FILE")
else
  TRIVY_ARGS+=(--format table)
fi

if [[ "$IGNORE_UNFIXED" == true ]]; then
  TRIVY_ARGS+=(--ignore-unfixed)
fi

if [[ -n "$IGNOREFILE" ]]; then
  TRIVY_ARGS+=(--ignorefile "$IGNOREFILE")
fi

TRIVY_ARGS+=("$IMAGE_REF")

echo "INFO: Scanning image: $IMAGE_REF"
echo "INFO: Severity floor: $SEVERITY"
[[ "$IGNORE_UNFIXED" == true ]] && echo "WARN: --ignore-unfixed is enabled — un-patchable CVEs are suppressed"
[[ -n "$IGNOREFILE" ]] && echo "INFO: Using ignorefile: $IGNOREFILE"

# --- Run scan ---
set +e
trivy "${TRIVY_ARGS[@]}"
TRIVY_RC=$?
set -e

# exit code 2 = scan error (auth failure, image not found) — never silently pass
if [[ "$TRIVY_RC" -eq 2 ]]; then
  echo "ERROR: Trivy scan failed (exit code 2) — check image ref, registry auth, or network." >&2
  exit 2
fi

# --- Optional SARIF upload ---
if [[ "$UPLOAD_SARIF" == true ]]; then
  if [[ "$OUTPUT_FORMAT" != "sarif" ]]; then
    echo "WARN: --upload-sarif requires --output sarif; skipping upload" >&2
  elif [[ ! -f "$SARIF_FILE" ]]; then
    echo "WARN: $SARIF_FILE not found; skipping upload" >&2
  elif ! command -v gh &>/dev/null; then
    echo "WARN: gh CLI not found; skipping SARIF upload" >&2
  else
    echo "INFO: Uploading $SARIF_FILE to GitHub Security tab..."
    gh api \
      --method POST \
      -H "Accept: application/vnd.github+json" \
      "/repos/$(gh repo view --json owner,name -q '.owner.login + "/" + .name')/code-scanning/sarifs" \
      --field commit_sha="$(git rev-parse HEAD)" \
      --field ref="$(git symbolic-ref HEAD 2>/dev/null || echo refs/heads/main)" \
      --field sarif="$(gzip -c "$SARIF_FILE" | base64 -w0)" \
      --field tool_name="Trivy"
    echo "INFO: SARIF upload complete"
  fi
fi

exit "$TRIVY_RC"

#!/usr/bin/env bash
# examples/compliance/checkov-terraform-plan.sh
#
# SCOPE: CI helper script — plan-mode Terraform scanning with guaranteed cleanup.
# This script is intentionally narrower than /platform-skills:checkov (which is the
# source of truth for the full command). It does NOT implement --bot PR comment output
# or --no-precommit hook detection; those are slash-command concerns. Use this script
# directly in CI jobs where you need a self-contained Bash executable.
#
# Usage:
#   ./checkov-terraform-plan.sh \
#     [--root <path>]              Terraform root directory (default: .)
#     [--output sarif|json|junitxml|all]  Output format (default: cli+json — JSON always written)
#     [--keep-plan]                Retain tfplan.binary/tfplan.json after scan
#     [--upgrade]                  Pass --upgrade to terraform init
#     [--yes]                      Skip interactive prompts (workspace, var-file)
#     [--workspace <name>]         Select Terraform workspace before planning
#     [--var-file <path>]          Use this .tfvars file (skips menu)
#     [--upload-sarif]             Upload checkov-results.sarif to GitHub Security tab
#                                  (requires gh CLI + code-scanning write permission)
#
# Requirements: terraform, checkov >= 2.3.0, jq, python3
# Optional:     gh CLI (for --upload-sarif only)

set -euo pipefail

ROOT="."
KEEP_PLAN=false
UPGRADE=false
OUTPUT_FORMAT="cli"
YES=false
WORKSPACE_OVERRIDE=""
VAR_FILE_OVERRIDE=""
UPLOAD_SARIF=false

# Proper argument parsing — positional-safe
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
    *)               echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Resolve to absolute path so -chdir works from any working directory
ROOT="$(cd "$ROOT" && pwd)"

# Resolve the git repo root independently — Terraform root and git root are not always the same.
# Used for .gitignore updates and SARIF upload git commands.
REPO_ROOT=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$ROOT")

# Derive a slug from ROOT relative to REPO_ROOT for output file naming.
# With --root terraform/aws, output files become checkov-results-terraform-aws.json etc.,
# avoiding overwrite collisions when scanning multiple roots in sequence.
ROOT_REL=$(realpath --relative-to="$REPO_ROOT" "$ROOT" 2>/dev/null || basename "$ROOT")
ROOT_SLUG=$(echo "$ROOT_REL" | tr '/' '-' | tr -cd '[:alnum:]-_')
[ -z "$ROOT_SLUG" ] || [ "$ROOT_SLUG" = "." ] && ROOT_SLUG="root"
RESULTS_PREFIX="${ROOT}/checkov-results-${ROOT_SLUG}"

# --- Guaranteed cleanup via trap (runs on exit, error, Ctrl+C, or SIGTERM) ---
# shellcheck disable=SC2317,SC2329  # cleanup() is called via trap, not directly
cleanup() {
  if [ "$KEEP_PLAN" = false ]; then
    rm -f "${ROOT}/tfplan.binary" "${ROOT}/tfplan.json"
    echo "INFO: Plan files cleaned up (use --keep-plan to retain)"
  fi
}
trap cleanup EXIT INT TERM

# --- Bootstrap checks ---
if ! command -v checkov &>/dev/null; then
  echo "ERROR: checkov not found. Run /platform-skills:checkov to install it." >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq not found. Install with: brew install jq (macOS) or apt-get install -y jq" >&2
  exit 1
fi

# --- Checkov minimum version check ---
# sort -V is GNU-only and absent on default macOS sort; use Python for portable semver compare.
CHECKOV_VERSION=$(checkov --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
REQUIRED="2.3.0"
if ! python3 -c "
v = '${CHECKOV_VERSION}'; r = '${REQUIRED}'
import sys
sys.exit(0 if tuple(int(x) for x in v.split('.')) >= tuple(int(x) for x in r.split('.')) else 1)
" 2>/dev/null; then
  echo "ERROR: checkov ${CHECKOV_VERSION} < required ${REQUIRED}. Run: pip3 install -U checkov" >&2
  exit 1
fi

# --- gitignore protection ---
# Update repo-root .gitignore with glob patterns that cover all slug variants.
for entry in "tfplan.json" "tfplan.binary" "*.tfplan" "checkov-results-*.json" "checkov-results-*.sarif" "checkov-results-*.xml"; do
  grep -qF "$entry" "${REPO_ROOT}/.gitignore" 2>/dev/null || echo "$entry" >> "${REPO_ROOT}/.gitignore"
done

# --- Cloud credential preflight ---
if grep -r 'hashicorp/aws' "$ROOT" --include="*.tf" -l &>/dev/null; then
  if ! command -v aws &>/dev/null; then
    echo "ERROR: AWS provider detected but 'aws' CLI not installed. Install: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html" >&2; exit 1
  fi
  aws sts get-caller-identity --output text &>/dev/null || { echo "ERROR: AWS credentials not configured. Run: aws sso login or aws configure" >&2; exit 1; }
fi
if grep -r 'hashicorp/azurerm' "$ROOT" --include="*.tf" -l &>/dev/null; then
  if ! command -v az &>/dev/null; then
    echo "ERROR: azurerm provider detected but 'az' CLI not installed. Install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli" >&2; exit 1
  fi
  az account show &>/dev/null || { echo "ERROR: Azure credentials not configured. Run: az login" >&2; exit 1; }
fi
if grep -r 'hashicorp/google' "$ROOT" --include="*.tf" -l &>/dev/null; then
  if ! command -v gcloud &>/dev/null; then
    echo "ERROR: google provider detected but 'gcloud' CLI not installed. Install: https://cloud.google.com/sdk/docs/install" >&2; exit 1
  fi
  gcloud auth application-default print-access-token &>/dev/null || { echo "ERROR: GCP credentials not configured. Run: gcloud auth application-default login" >&2; exit 1; }
fi

# --- GitHub module auth via gh CLI ---
# Token is scoped to the terraform/checkov invocations only — never printed or exported
# to the broader shell session. Storing in a variable that is passed inline keeps it
# out of 'ps aux' output and avoids leaking it via shell history or sub-processes.
_GITHUB_PAT_VALUE=""
if grep -rE 'source[[:space:]]*=[[:space:]]*"(github\.com/|git::https://github\.com/)' "$ROOT" --include="*.tf" -l &>/dev/null; then
  if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    _GITHUB_PAT_VALUE=$(gh auth token)
    echo "INFO: GitHub PAT obtained from gh CLI for private module resolution"
  elif [ -n "${GITHUB_PAT:-}" ]; then
    _GITHUB_PAT_VALUE="${GITHUB_PAT}"
  else
    echo "ERROR: Private GitHub modules detected but no auth found. Run: gh auth login" >&2
    exit 1
  fi
fi

# --- terraform init (plain — scan must not mutate .terraform.lock.hcl) ---
# Pass --upgrade only when the user explicitly requested it via --upgrade flag.
if [ ! -d "${ROOT}/.terraform" ]; then
  echo "INFO: .terraform/ not found — running terraform init"
  if [ "$UPGRADE" = true ]; then
    terraform -chdir="$ROOT" init --upgrade
  else
    terraform -chdir="$ROOT" init
  fi
fi

# --- Workspace awareness ---
if [ -n "$WORKSPACE_OVERRIDE" ]; then
  terraform -chdir="$ROOT" workspace select "$WORKSPACE_OVERRIDE"
  echo "INFO: Switched to workspace: $WORKSPACE_OVERRIDE"
fi
WORKSPACE=$(terraform -chdir="$ROOT" workspace show 2>/dev/null || echo "default")
echo "INFO: Current Terraform workspace: $WORKSPACE"
if [ "$YES" = false ]; then
  read -r -p "Continue planning against workspace '$WORKSPACE'? (y/N): " confirm
  [ "$confirm" = "y" ] || { echo "Aborted."; exit 0; }
else
  echo "WARN: skipping workspace confirmation (--yes)"
fi

# --- Variable file detection ---
VAR_FILE_ARGS=""
if [ -n "$VAR_FILE_OVERRIDE" ]; then
  VAR_FILE_ARGS="-var-file=${VAR_FILE_OVERRIDE}"
  echo "INFO: Using variable file: ${VAR_FILE_OVERRIDE}"
else
  TFVARS=$(find "$ROOT" -maxdepth 1 -name "*.tfvars" | sort)
  if [ -n "$TFVARS" ]; then
    if [ "$YES" = true ]; then
      # Non-interactive: use the first found var file
      VAR_FILE_ARGS="-var-file=$(echo "$TFVARS" | head -1)"
      echo "WARN: --yes set — auto-selecting var file: $(echo "$TFVARS" | head -1)"
    else
      echo "Variable files found:"
      i=1
      declare -a TFVAR_LIST
      while IFS= read -r f; do
        TFVAR_LIST[i]="$f"
        echo "  $i. $f"
        i=$((i+1))
      done <<< "$TFVARS"
      NONE_OPT=$i
      echo "  ${NONE_OPT}. None (use defaults)"
      read -r -p "Select [default: 1]: " choice
      choice="${choice:-1}"
      if [ "$choice" != "$NONE_OPT" ] && [ -n "${TFVAR_LIST[$choice]:-}" ]; then
        VAR_FILE_ARGS="-var-file=${TFVAR_LIST[$choice]}"
        echo "INFO: Using variable file: ${TFVAR_LIST[$choice]}"
      fi
    fi
  fi
fi

# --- Plan (all terraform commands use -chdir to target the selected root) ---
echo "INFO: Running terraform plan..."
# shellcheck disable=SC2086
terraform -chdir="$ROOT" plan $VAR_FILE_ARGS --out tfplan.binary

# --- Convert to JSON ---
echo "INFO: Converting plan to JSON..."
terraform -chdir="$ROOT" show -json tfplan.binary | jq '.' > "${ROOT}/tfplan.json"

# --- Build output flags ---
# Output files use slug-prefixed absolute paths (e.g. checkov-results-terraform-aws.json)
# so multiple root scans don't overwrite each other. All paths are absolute under ROOT.
OUTPUT_FLAGS="-o cli -o json --output-file-path console,${RESULTS_PREFIX}.json"
case "$OUTPUT_FORMAT" in
  json)     : ;;  # already set above
  sarif)    OUTPUT_FLAGS="-o cli -o json -o sarif --output-file-path console,${RESULTS_PREFIX}.json,${RESULTS_PREFIX}.sarif" ;;
  junitxml) OUTPUT_FLAGS="-o cli -o json -o junitxml --output-file-path console,${RESULTS_PREFIX}.json,${RESULTS_PREFIX}.xml" ;;
  all)      OUTPUT_FLAGS="-o cli -o json -o sarif -o junitxml --output-file-path console,${RESULTS_PREFIX}.json,${RESULTS_PREFIX}.sarif,${RESULTS_PREFIX}.xml" ;;
esac

# --- External checks ---
EXTERNAL_CHECKS=""
[ -d "${ROOT}/custom-checks" ] && EXTERNAL_CHECKS="--external-checks-dir ${ROOT}/custom-checks"

# --- Baseline ---
BASELINE=""
[ -f "${ROOT}/.checkov.baseline" ] && BASELINE="--baseline ${ROOT}/.checkov.baseline"

# --- Scan ---
echo "INFO: Running Checkov plan scan..."
set +e
# GITHUB_PAT is passed inline via env (not exported) to scope it to this process only.
# Only inject when non-empty to avoid overriding a user-provided GITHUB_PAT with empty string.
_pat_env=()
[ -n "${_GITHUB_PAT_VALUE}" ] && _pat_env=("GITHUB_PAT=${_GITHUB_PAT_VALUE}")
# shellcheck disable=SC2086
env "${_pat_env[@]}" checkov -f "${ROOT}/tfplan.json" \
  --repo-root-for-plan-enrichment "$ROOT" \
  --deep-analysis \
  --compact \
  --quiet \
  $EXTERNAL_CHECKS \
  $BASELINE \
  $OUTPUT_FLAGS
CHECKOV_EXIT=$?
set -e

case $CHECKOV_EXIT in
  0) echo "INFO: Checkov — CLEAN (all checks passed)" ;;
  1) echo "WARN: Checkov — findings detected (see output above)" ;;
  2) echo "ERROR: Checkov tool error — check flags and version" >&2; exit 2 ;;
esac

# --- Optional SARIF upload to GitHub Security tab ---
# Only runs when --upload-sarif is explicitly passed. Generating SARIF (--output sarif)
# and publishing code-scanning alerts are separate actions with different permissions.
# The GitHub Actions OIDC token needs security-events:write; a personal gh auth session
# needs the same scope. Never upload automatically — make it an explicit CI choice.
if [ "$UPLOAD_SARIF" = true ]; then
  if [[ "$OUTPUT_FORMAT" != "sarif" && "$OUTPUT_FORMAT" != "all" ]]; then
    echo "ERROR: --upload-sarif requires --output sarif or --output all" >&2; exit 1
  fi
  if ! command -v gh &>/dev/null || ! gh auth status &>/dev/null 2>&1; then
    echo "ERROR: --upload-sarif requires gh CLI authenticated (gh auth login)" >&2; exit 1
  fi
  REPO=$(git -C "$ROOT" remote get-url origin | sed 's|.*github.com[:/]||;s|\.git$||')
  COMMIT_SHA=$(git -C "$ROOT" rev-parse HEAD)
  REF=$(git -C "$ROOT" symbolic-ref HEAD 2>/dev/null || echo "refs/tags/$(git -C "$ROOT" describe --tags --exact-match 2>/dev/null)")
  # GitHub requires gzip-compressed, Base64-encoded SARIF.
  # tr -d '\n' strips line-wrapping added by GNU base64 (not present on macOS base64).
  SARIF_PAYLOAD=$(gzip -c "${RESULTS_PREFIX}.sarif" | base64 | tr -d '\n')
  echo "INFO: Uploading SARIF to GitHub Security tab..."
  gh api "repos/${REPO}/code-scanning/sarifs" \
    --method POST \
    --field sarif="$SARIF_PAYLOAD" \
    --field commit_sha="$COMMIT_SHA" \
    --field ref="$REF"
  echo "INFO: SARIF uploaded — https://github.com/${REPO}/security/code-scanning"
fi

exit $CHECKOV_EXIT

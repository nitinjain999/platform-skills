#!/usr/bin/env bash
# sync-fluxcd-skills.sh
# Downloads the three Flux CD GitOps skills from the upstream fluxcd/agent-skills
# repository into skills/ — preserving each skill's self-contained directory tree
# (SKILL.md, assets/schemas/, references/, scripts/).
#
# Attribution: files downloaded from https://github.com/fluxcd/agent-skills
# License: Apache-2.0 (same as this repository)
#
# Usage:
#   bash scripts/sync-fluxcd-skills.sh              # fetch from main
#   FLUXCD_REF=v0.0.2 bash scripts/sync-fluxcd-skills.sh  # fetch a specific tag/SHA
set -euo pipefail

UPSTREAM="fluxcd/agent-skills"
FLUXCD_REF="${FLUXCD_REF:-main}"
BASE_URL="https://raw.githubusercontent.com/${UPSTREAM}/${FLUXCD_REF}"
API_URL="https://api.github.com/repos/${UPSTREAM}/git/trees/${FLUXCD_REF}?recursive=1"
REPO_ROOT="$(git rev-parse --show-toplevel)"

SKILLS=(
  "skills/gitops-knowledge"
  "skills/gitops-repo-audit"
  "skills/gitops-cluster-debug"
)

echo "🔄 Syncing Flux CD GitOps skills from ${UPSTREAM}@${FLUXCD_REF}"
echo ""

# Fetch the full tree from the upstream repo via GitHub API
echo "📋 Fetching upstream file tree..."
TREE=$(curl -sf "${API_URL}" | jq -r '.tree[] | select(.type == "blob") | .path')

if [ -z "$TREE" ]; then
  echo "❌ Failed to fetch file tree from ${UPSTREAM}"
  echo "   Check your network connection or GitHub API rate limits."
  exit 1
fi

TOTAL=0
UPDATED=0

for skill in "${SKILLS[@]}"; do
  echo "📦 Syncing ${skill}..."

  # Filter files belonging to this skill (exclude evals/ — not needed at runtime)
  SKILL_FILES=$(echo "$TREE" | grep "^${skill}/" | grep -v "^${skill}/evals/")

  while IFS= read -r remote_path; do
    local_path="${REPO_ROOT}/${remote_path}"
    local_dir="$(dirname "$local_path")"

    mkdir -p "$local_dir"

    # Download into a temp file first so a failed download doesn't clobber the existing file
    tmp_file=$(mktemp)
    if curl -sf "${BASE_URL}/${remote_path}" -o "$tmp_file"; then
      if [ -f "$local_path" ] && diff -q "$local_path" "$tmp_file" > /dev/null 2>&1; then
        : # unchanged — skip
      else
        mv "$tmp_file" "$local_path"
        echo "  ✅ ${remote_path}"
        UPDATED=$((UPDATED + 1))
      fi
    else
      echo "  ⚠️  Failed to download: ${remote_path}"
      rm -f "$tmp_file"
    fi

    rm -f "$tmp_file" 2>/dev/null || true
    TOTAL=$((TOTAL + 1))
  done <<< "$SKILL_FILES"
done

echo ""
echo "✅ Sync complete — ${UPDATED} file(s) updated out of ${TOTAL} checked"
echo "   Upstream: https://github.com/${UPSTREAM}/tree/${FLUXCD_REF}"

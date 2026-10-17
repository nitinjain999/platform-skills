#!/usr/bin/env bash
# Single source of truth for the marketplace pin gate.
#
# Every plugin entry in .claude-plugin/marketplace.json must carry
# source.sha, the commit installers download. Without one, a git-based source
# follows its branch, so whatever is merged to main reaches new installs with
# no tag and no release gate, and the plugin's version string no longer names
# one tree. platform-guardrails shipped like that in 1.44.0 (`ref: main`, no
# sha); release.yml checked only plugins[0], so nothing noticed.
#
# Usage:
#   bash tests/marketplace-pins.sh                       structure only (PR gate)
#   bash tests/marketplace-pins.sh --release <commit>    full check at a tag (release.yml)
#   --file <path>                                        a different marketplace.json (tests)
#
# Structure: every entry has an object source with a 40-character lowercase
# sha. A missing or malformed sha fails; it is never skipped.
#
# --release <commit>, per entry:
#   - the sha is reachable from the tagged commit, and
#   - nothing but marketplace.json differs between the sha and the tag.
# A commit cannot contain its own hash, so the pin always points at an earlier
# commit; anything else that differs is content the release does not ship.
# v1.38.0 shipped the pre-fix azure example exactly that way, 1 commit behind.
# The fix is always the same: land content first, then bump every sha to that
# merge commit in a PR that touches only marketplace.json, then tag.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE=".claude-plugin/marketplace.json"
RELEASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file) FILE="${2:?--file needs a path}"; shift 2 ;;
    --release) RELEASE="${2:?--release needs a commit}"; shift 2 ;;
    *) echo "usage: $0 [--file <marketplace.json>] [--release <commit>]" >&2; exit 2 ;;
  esac
done

ERRORS=0
fail() { echo "❌ $1"; ERRORS=$((ERRORS + 1)); }

if ! jq -e '.plugins | type == "array" and length > 0' "$FILE" >/dev/null 2>&1; then
  echo "❌ $FILE has no plugins array"
  exit 1
fi

if [ -n "$RELEASE" ]; then
  TAG_COMMIT="$(git rev-parse --verify "${RELEASE}^{commit}")" || { echo "❌ --release $RELEASE is not a commit"; exit 1; }
fi

# name<TAB>sha per entry; a string source or a missing sha yields an empty sha.
while IFS=$'\t' read -r name sha; do
  if ! printf '%s' "$sha" | grep -qE '^[0-9a-f]{40}$'; then
    fail "plugin \"$name\" has no 40-character source.sha (got \"$sha\"); an unpinned source ships whatever its branch holds"
    continue
  fi
  if [ -z "$RELEASE" ]; then
    echo "✅ $name pinned to $sha"
    continue
  fi
  if ! git merge-base --is-ancestor "$sha" "$TAG_COMMIT" 2>/dev/null; then
    fail "plugin \"$name\" source.sha $sha is not reachable from the tagged commit $TAG_COMMIT"
    continue
  fi
  excluded="$(git diff --name-only "$sha" "$TAG_COMMIT" -- . ':(exclude).claude-plugin/marketplace.json')"
  if [ -n "$excluded" ]; then
    fail "plugin \"$name\" source.sha $sha excludes content present in the tag $TAG_COMMIT:"
    printf '%s\n' "$excluded" | sed 's/^/  /'
    continue
  fi
  echo "✅ $name source.sha $sha ships the tagged content"
done < <(jq -r '.plugins[] | [.name, (if (.source | type) == "object" then (.source.sha // "") else "" end)] | @tsv' "$FILE")

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "Land content first and merge it, then set every plugin's source.sha to that"
  echo "merge commit in a PR that touches only .claude-plugin/marketplace.json, then tag."
  exit 1
fi

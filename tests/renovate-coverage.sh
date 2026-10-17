#!/usr/bin/env bash
# Renovate coverage gate: every tool version pinned in a workflow or example
# must be one Renovate can see.
#
# The built-in managers read `uses:` refs, a fixed list of setup-action inputs,
# Helm/Flux/Terraform/npm manifests. They do not read a version in an env block
# (`ZIZMOR_VERSION: 1.29.0`) or a version inside a download URL. Those pins went
# stale silently: zizmor sat two minors behind under a comment claiming
# "Renovate keeps it current", and validate.yml installed an unverified
# kubeconform v0.6.4 next to a checksum-verified v0.8.0.
#
# The fix is the annotation that renovate.json's custom regex manager reads:
#
#   # renovate: datasource=<datasource> depName=<name> [extractVersion=...]
#   TOOL_VERSION: v1.2.3
#   TOOL_SHA256: <64 hex>        optional; updated with the version
#
# Checks, each a failure (never a skip):
#   1. a `*_VERSION:` line with a literal version has the annotation directly above
#   2. an annotation is directly followed by a `key: value` line
#   3. no download URL hard-codes a release version (`releases/download/v1.2.3`);
#      build it from an annotated variable instead
#
# Scope: .github/workflows/*.{yml,yaml,md} (gh-aw sources included, generated
# *.lock.yml excluded), examples/**/*.{yml,yaml}, assets/*.yml. The fixture paths
# renovate.json lists in ignorePaths are excluded here too: they are outdated or
# broken on purpose.
#
# Usage: bash tests/renovate-coverage.sh [--root <dir>]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:?--root needs a directory}"; shift 2 ;;
    *) echo "usage: $0 [--root <dir>]" >&2; exit 2 ;;
  esac
done
cd "$ROOT"

EXCLUDE='\.lock\.yml$|^examples/(pr-review|triage)/|^examples/demo/[^/]+/bad\.|(^|/)(\.terraform|node_modules)/'
SCOPE='^\.github/workflows/[^/]+\.(ya?ml|md)$|^(examples|assets)/.+\.ya?ml$'

# Tracked files only in a checkout, so a local `terraform init` download or an
# untracked scratch file cannot fail the gate; a plain directory (fixtures) is walked.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  all="$(git ls-files)"
else
  all="$(find . -type f | sed 's|^\./||')"
fi
files="$(printf '%s\n' "$all" | grep -E "$SCOPE" | grep -vE "$EXCLUDE" | sort -u || true)"

if [ -z "$files" ]; then
  echo "❌ no workflow or example files found under $ROOT; refusing to pass an empty scan"
  exit 1
fi

count="$(printf '%s\n' "$files" | wc -l | tr -d ' ')"
echo "Checking Renovate can see every pinned tool version ($count files)..."

# One awk pass over every file. FNR == 1 marks a new file; a dangling
# annotation on the last line of the previous file is reported there and at END.
# shellcheck disable=SC2016  # the awk program is single-quoted on purpose
findings="$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 awk '
  function dangling() {
    if (pending) { printf "%s:%d: renovate annotation is not followed by a key: value line\n", pfile, pline; pending = 0 }
  }
  FNR == 1 { dangling(); prev = "" }
  {
    if (pending) {
      if ($0 !~ /^[ \t]*[A-Za-z0-9_-]+[ \t]*:[ \t]*[^ \t]/) dangling()
      pending = 0
    }
    annotated = (prev ~ /^[ \t]*# renovate: datasource=[^ ]+ depName=[^ ]+/)
    if ($0 ~ /^[ \t]*# renovate: datasource=[^ ]+ depName=[^ ]+/) { pending = 1; pfile = FILENAME; pline = FNR }
    if ($0 ~ /^[ \t]*[A-Z0-9_]+_VERSION[ \t]*:[ \t]*["\047]?v?[0-9]/ && !annotated)
      printf "%s:%d: version pin has no renovate annotation above it: %s\n", FILENAME, FNR, $0
    if ($0 ~ /releases\/download\/v?[0-9]/)
      printf "%s:%d: download URL hard-codes a release version: %s\n", FILENAME, FNR, $0
    prev = $0
  }
  END { dangling() }
')" || { echo "❌ the coverage scan itself failed"; exit 1; }

if [ -n "$findings" ]; then
  printf '%s\n' "$findings" | sed 's/^/❌ /'
  echo "Add '# renovate: datasource=<datasource> depName=<name>' on the line above the pin (see renovate.json customManagers)."
  exit 1
fi

echo "✅ every pinned tool version is visible to Renovate"

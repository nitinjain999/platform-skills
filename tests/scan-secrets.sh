#!/usr/bin/env bash
# Single source of truth for the credential scan.
#
# This logic previously existed as four inline `run:` blocks — two in
# validate.yml (the PR gate) and two in release.yml (the release gate). The two
# copies drifted, and because the release gate only executes when a tag is
# pushed, the drift was invisible until it blocked a release. Both workflows now
# call this script instead, so there is nothing left to drift.
#
# The patterns and filters are carried over unchanged. Two deliberate
# differences from the inline versions:
#
#   1. The file list comes from `git ls-files`, not a `grep -r` walk of the
#      working tree. In CI these are equivalent — the scan runs immediately
#      after a fresh checkout, so tracked files are the only files. Locally they
#      are not: a `grep -r` walk also reads gitignored build output such as
#      website/build, which buries the result in minified JavaScript and makes
#      the script useless as a pre-push check. Scanning what is committed is
#      also the more honest question to ask.
#   2. This file excludes itself, because it carries the patterns (see below).
#
# One consequence of (1) worth knowing when running this locally: a brand-new
# file is only scanned once git knows about it (`git add`, or `git add -N`). In
# CI this never bites, because the checkout has everything already tracked.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FAILURES=0

# Path exclusions, each for a reason:
#   node_modules/            — not source
#   examples/                — templates; sensitive values always use var.xxx
#   *.md                     — prose (CHANGELOG.md and QUALITY_ASSURANCE.md were
#                              the original offenders; *.md now covers them)
#   *.lock.yml               — gh-aw generated workflows. Machine-generated
#                              mega-lines self-match, e.g. keyserver.ubuntu.com
#                              supplying "key" plus an imageTag=sha256:... value.
#                              Their .md sources are covered by check 2, so
#                              excluding them costs no coverage.
#   release.yml, validate.yml — retained defensively. They no longer carry the
#                              patterns now that this script does, but if one is
#                              ever inlined there again it would self-match,
#                              which is exactly how this broke.
#   scan-secrets.sh          — this file. The broad pattern matches the tighter
#                              pattern in check 2: the keyword supplies the
#                              keyword, [:=] supplies the "=", ["]? the opening
#                              quote, and the pattern's own closing quote the
#                              closing quote. Any file holding either regex must
#                              be excluded from this one.
EXCLUDE_RE='(^|/)node_modules/|(^|/)examples/|\.md$|\.lock\.yml$|(^|/)(release|validate)\.yml$|(^|/)scan-secrets\.sh$'

# --- Check 1: broad heuristic scan across tracked files ---------------------
scan_repository() {
  local files matches
  files=$(git ls-files | grep -vE "$EXCLUDE_RE" || true)

  if [ -z "$files" ]; then
    echo "ℹ️  No files to scan"
    return 0
  fi

  # -I skips binary files rather than reporting "Binary file ... matches", which
  # would otherwise be an unfixable finding. NUL-delimited so a path containing
  # a space cannot split into two arguments.
  matches=$(printf '%s\n' "$files" | tr '\n' '\0' | \
     xargs -0 grep -IHnE '(password|secret|key|token|apikey).*=.*["\x27][^"\x27]{8,}["\x27]' | \
     grep -v 'matrix\.' | \
     grep -v 'vars\.' | \
     grep -v 'secrets\.' | \
     grep -v 'backend-config=' | \
     grep -v 'token.actions.githubusercontent.com' || true)

  if [ -n "$matches" ]; then
    echo "⚠️  Potential secrets found in code:"
    echo "$matches"
    echo ""
    echo "Review above matches to ensure they are not real secrets"
    return 1
  fi

  echo "✅ No obvious secrets detected"
}

# --- Check 2: agentic workflow sources -------------------------------------
#
# Check 1 excludes *.md (prose) and *.lock.yml (generated). Together those would
# leave gh-aw workflow sources with NO credential coverage, even though they are
# executable CI with secrets access: a hard-coded value in frontmatter or
# pre-steps compiles straight into the .lock.yml. So scan
# .github/workflows/**/*.md explicitly, with a tighter pattern (keyword +
# separator + a long literal value) that does not self-match.
scan_agentic_sources() {
  local sources found
  sources=$(git ls-files -- '.github/workflows/*.md' || true)

  if [ -z "$sources" ]; then
    echo "ℹ️  No agentic workflow sources found"
    return 0
  fi

  found=$(printf '%s\n' "$sources" | tr '\n' '\0' | \
     xargs -0 grep -IHnE '(password|secret|key|token|apikey)[[:space:]]*[:=][[:space:]]*["]?[A-Za-z0-9/+_-]{16,}' | \
     grep -v 'secrets\.' | \
     grep -v 'vars\.' | \
     grep -v 'github\.token' || true)

  if [ -n "$found" ]; then
    echo "❌ Potential hard-coded credential in agentic workflow source:"
    echo "$found"
    echo ""
    echo "Reference secrets as \${{ secrets.NAME }} instead of inlining values."
    return 1
  fi

  echo "✅ No hard-coded credentials in agentic workflow sources"
}

# Run both checks before deciding. Exiting on the first failure would hide the
# second, which costs an extra CI round trip to discover.
scan_repository || FAILURES=$((FAILURES + 1))
scan_agentic_sources || FAILURES=$((FAILURES + 1))

if [ "$FAILURES" -gt 0 ]; then
  echo ""
  echo "❌ $FAILURES credential scan(s) reported findings"
  exit 1
fi

echo "✅ Credential scans passed"

#!/usr/bin/env bash
# Gate for plugins/platform-skills/, the folder the Claude plugin directory lists.
# scripts/build-plugin.sh generates it; this checks the committed copy.
#
# Checks, each a failure (never a skip):
#   1. the folder's plugin.json version equals the root manifest's, so a release
#      PR that bumps the version cannot skip the rebuild
#   2. it stays inside the directory's inspection limits, past which a version is
#      held for review: at most 480 files (the directory inspects 512; the rest
#      is headroom), no file over 256 KiB except images, only text, PNG, JPEG,
#      GIF, WebP and font files
#   3. nothing that stops validation: no symlinks, no OS metadata files, no name
#      with a colon, a trailing dot or space, or a Windows device name, and no two
#      names that differ only by case; and no file that .gitignore keeps out of a
#      commit (`secrets/` dropped skills/secrets/ that way: the folder passed
#      here on disk and failed in CI's clone). Checked when the folder is in
#      this repository, so not for a --dir copy elsewhere
#   4. a README.md of at least 40 words outside code blocks, a LICENSE, and no
#      CLAUDE.md (the directory warns that a plugin's CLAUDE.md is never loaded)
#   5. every $CLAUDE_PLUGIN_ROOT/<path> a shipped file runs exists in the folder:
#      an installed plugin has nothing outside it
#   6. the folder matches a fresh build. Without --strict a mismatch is reported,
#      not failed: the folder is rebuilt in the release PR, so between releases
#      it lags the source by design. validate.yml passes --strict when a PR
#      touches the folder or the root manifest, and release.yml on every tag.
#   7. no credential-shaped literal in what the next release ships: a vendor
#      token prefix (ghp_, github_pat_, AKIA, xox…, sk_live_, glpat-, AIza, a
#      PEM private key) or a credential-named key or flag (token, secret,
#      password, api key, access key) given a 16+ character value that mixes
#      letters and digits. The directory blocks such a file as SECRET_IN_SCRIPT
#      even when the value is a sample: 1.45.2 was blocked on a 32-hex example
#      lock_token in references/triage.md. Values containing EXAMPLE, xxxx,
#      YOUR_, placeholder, REDACTED, dummy or fake pass, as the directory's do.
#      Scans the fresh build, so a source fix passes here before the release
#      PR rebuilds the folder.
#
# Usage: bash tests/plugin-folder.sh [--strict] [--dir <folder>]
#   --dir  check another folder (mutation tests); the fresh build still comes
#          from this repository
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIR="$ROOT/plugins/platform-skills"
STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --dir) DIR="${2:?--dir needs a folder}"; shift 2 ;;
    *) echo "usage: $0 [--strict] [--dir <folder>]" >&2; exit 2 ;;
  esac
done

MAX_FILES=480
MAX_BYTES=262144
IMAGE='\.(png|jpe?g|gif|webp|woff2?|ttf|otf)$'

ERRORS=0
fail() { echo "❌ $1"; ERRORS=$((ERRORS + 1)); }

if [ ! -f "$DIR/.claude-plugin/plugin.json" ]; then
  echo "❌ $DIR/.claude-plugin/plugin.json is missing; run: bash scripts/build-plugin.sh"
  exit 1
fi

# 1. version
root_version="$(jq -r '.version' .claude-plugin/plugin.json)"
folder_version="$(jq -r '.version' "$DIR/.claude-plugin/plugin.json")" || folder_version="<invalid JSON>"
if [ "$folder_version" = "$root_version" ]; then
  echo "✅ plugin.json version $folder_version matches the root manifest"
else
  fail "folder plugin.json is version $folder_version, the root manifest $root_version; run: bash scripts/build-plugin.sh"
fi

# 2. inspection limits
files="$(cd "$DIR" && find . -type f | sed 's|^\./||' | sort)"
count="$(printf '%s\n' "$files" | grep -c . || true)"
if [ "$count" -le "$MAX_FILES" ]; then
  echo "✅ $count files (budget $MAX_FILES; the directory holds a version above 512)"
else
  fail "$count files, over the $MAX_FILES budget; the directory inspects only 512. Ship fewer examples or split the plugin"
fi

while IFS= read -r f; do
  if printf '%s\n' "$f" | grep -qiE "$IMAGE"; then
    continue
  fi
  size="$(wc -c < "$DIR/$f" | tr -d ' ')"
  if [ "$size" -gt "$MAX_BYTES" ]; then
    fail "$f is $size bytes; the directory holds a version with a non-image file over 256 KiB"
  fi
  if [ "$size" -gt 0 ] && ! grep -Iq '' "$DIR/$f"; then
    fail "$f is binary; the directory holds any binary that is not an image or font"
  fi
done <<< "$files"

# 3. names and entries that stop validation
links="$(find "$DIR" -type l)"
[ -z "$links" ] || fail "symlinks are not loaded from a directory install: $links"
junk="$(printf '%s\n' "$files" | grep -E '(^|/)(\.DS_Store|Thumbs\.db|desktop\.ini|__MACOSX)(/|$)' || true)"
[ -z "$junk" ] || fail "OS metadata files block validation: $junk"
bad_names="$(printf '%s\n' "$files" | tr '/' '\n' | sort -u \
  | grep -iE ':|[. ]$|^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$' || true)"
[ -z "$bad_names" ] || fail "names Windows or macOS cannot hold: $bad_names"
case_clash="$(printf '%s\n' "$files" | tr '[:upper:]' '[:lower:]' | sort | uniq -d)"
[ -z "$case_clash" ] || fail "paths that differ only by case: $case_clash"
[ -n "$links$junk$bad_names$case_clash" ] || echo "✅ no symlinks, OS metadata files or unportable names"

case "$DIR/" in
  "$ROOT"/*)
    ignored="$(git ls-files --others --ignored --exclude-standard -- "$DIR")"
    if [ -z "$ignored" ]; then
      echo "✅ .gitignore keeps no file of the folder out of a commit"
    else
      fail "files .gitignore keeps out of a commit, so a clone lacks them; re-include them in .gitignore: $ignored"
    fi
    ;;
esac

# 4. listing files
if [ -f "$DIR/README.md" ]; then
  words="$(awk '/^```/ { fence = !fence; next } !fence' "$DIR/README.md" | wc -w | tr -d ' ')"
  if [ "$words" -ge 40 ]; then
    echo "✅ README.md has $words words outside code blocks"
  else
    fail "README.md has $words words outside code blocks; the directory needs 40"
  fi
else
  fail "README.md is missing; the directory blocks a plugin without one"
fi
[ -f "$DIR/LICENSE" ] || fail "LICENSE is missing"
[ ! -e "$DIR/CLAUDE.md" ] || fail "CLAUDE.md at the plugin root is never loaded; move its content into a skill"

# 5. runtime paths
missing=""
while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ -e "$DIR/$p" ] || missing="$missing $p"
done < <(grep -rhoE '\$\{?CLAUDE_PLUGIN_ROOT\}?/[A-Za-z0-9_./-]+' "$DIR" \
  | sed -E 's|^\$\{?CLAUDE_PLUGIN_ROOT\}?/||; s|[./]+$||' | sort -u || true)
if [ -z "$missing" ]; then
  echo "✅ every \$CLAUDE_PLUGIN_ROOT path a shipped file runs is in the folder"
else
  fail "shipped files run paths the folder lacks:$missing"
fi

# 6. freshness
fresh="$(mktemp -d)"
trap 'rm -rf "$fresh"' EXIT
bash scripts/build-plugin.sh --out "$fresh/plugin" >/dev/null
drift="$(diff -rq "$fresh/plugin" "$DIR" | sed -E "s|$fresh/plugin|<fresh build>|g; s|$DIR|<folder>|g" || true)"
if [ -z "$drift" ]; then
  echo "✅ the folder matches a fresh build"
elif [ "$STRICT" -eq 1 ]; then
  fail "the folder differs from a fresh build; edit the source, then run: bash scripts/build-plugin.sh"
  printf '%s\n' "$drift" | head -n 20 | sed 's/^/  /'
else
  echo "ℹ️  the folder lags the source by $(printf '%s\n' "$drift" | grep -c .) file(s); the release PR rebuilds it (bash scripts/build-plugin.sh)"
fi

# 7. credential-shaped literals
vendor='(gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|A(KI|SI)A[0-9A-Z]{16}|xox[abposr]-[0-9A-Za-z-]{10,}|sk_(live|test)_[0-9A-Za-z]{16,}|glpat-[0-9A-Za-z_-]{20,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----)'
named='([A-Za-z0-9_-]*(token|secret|password|passwd|api[_-]?key|access[_-]?key)[A-Za-z0-9_-]*["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?|--[a-z-]*(token|secret|password|api-key)[[:space:]]+["'"'"']?)[A-Za-z0-9+/_-]{16,}'
# grep exits 1 on no match; anything above 1 is a failed scan and must fail closed.
scan() { local rc=0; grep "$@" "$fresh/plugin" || rc=$?; [ "$rc" -le 1 ] || { echo "grep failed ($rc)" >&2; return 2; }; }
# Capture each scan on its own: $(…) strips trailing newlines, so joining two
# substitutions in one string glues the last hit of one to the first of the next.
if ! vendor_hits="$(scan -rnoIE "$vendor")" || ! named_hits="$(scan -rnoiIE "$named")"; then
  fail "the credential scan itself failed"
else
  creds="$(printf '%s\n%s\n' "$vendor_hits" "$named_hits" | grep . | sed "s|^$fresh/plugin/||" | awk -F: '{
      m = $0; sub(/^[^:]*:[0-9]+:/, "", m)
      v = m; sub(/^.*[:= ][[:space:]]*["\047]?/, "", v)
      if (v ~ /EXAMPLE|example|[xX]{4}|YOUR_|[Pp]laceholder|REDACTED|[Dd]ummy|[Ff]ake/) next
      if (m ~ /^(gh[pousr]_|github_pat_|A(KI|SI)A|xox|sk_(live|test)_|glpat-|AIza|-----BEGIN)/) { print; next }
      d = gsub(/[0-9]/, "&", v); l = gsub(/[A-Za-z]/, "&", v)
      if (d >= 3 && l >= 3) print
    }')"
  if [ -z "$creds" ]; then
    echo "✅ no credential-shaped literal in what the next release ships"
  else
    fail "credential-shaped literals the directory blocks as SECRET_IN_SCRIPT; use a placeholder such as <token> or YOUR_TOKEN:"
    printf '%s\n' "$creds" | head -n 20 | sed 's/^/  /'
  fi
fi

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS plugin folder check(s) failed"
  exit 1
fi
echo "PASS: plugin folder checks passed"

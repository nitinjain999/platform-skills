#!/usr/bin/env bash
# tests/token-optimizer-script.sh — validates optimize.sh without a live client session
set -euo pipefail

SCRIPT="examples/token-optimizer/optimize.sh"

echo "--- Test 1: bash syntax check ---"
bash -n "$SCRIPT"
echo "PASS: no syntax errors"

echo "--- Test 2: bash 3.2 syntax check ---"
if [ -x /bin/bash ]; then
  /bin/bash -n "$SCRIPT"
  echo "PASS: parses under $(/bin/bash --version | head -1)"
else
  echo "SKIP: /bin/bash not present"
fi

echo "--- Test 3: shellcheck (skip if not installed) ---"
if command -v shellcheck &>/dev/null; then
  shellcheck -S warning "$SCRIPT"
  echo "PASS: shellcheck clean"
else
  echo "SKIP: shellcheck not installed"
fi

echo "--- Test 4: --help exits 0 ---"
bash "$SCRIPT" --help >/dev/null
echo "PASS: --help works"

echo "--- Test 5: every documented platform renders valid JSON on redirect ---"
# emit_redirect RETURNS the exit code the caller should use: 0 for real clients,
# where the JSON deny decides, and 2 for --platform=none, the scriptable dry-run
# signal. Under `set -e` an unguarded command substitution would abort here on
# the `none` case, so the return code is captured rather than allowed to
# propagate, and asserted below.
for platform in claude copilot vscode none; do
  rc=0
  out="$(bash -c '
    source '"$SCRIPT"' --source-only
    PLATFORM="'"$platform"'"
    WORKER_AGENT="platform-bulk-reader"
    emit_redirect "test reason"
  ')" || rc=$?
  printf '%s' "$out" | jq empty
  case "$platform" in
    none) [ "$rc" -eq 2 ] || { echo "FAIL: $platform should signal 2, got $rc"; exit 1; } ;;
    *)    [ "$rc" -eq 0 ] || { echo "FAIL: $platform should signal 0, got $rc"; exit 1; } ;;
  esac
  echo "PASS: $platform renders valid JSON and signals $rc"
done

echo "--- Test 5b: a payload-controlled newline in the path still yields valid JSON ---"
out="$(bash -c '
  source '"$SCRIPT"' --source-only
  PLATFORM="claude"
  WORKER_AGENT="platform-bulk-reader"
  SUMMARY_WORDS=600
  MAX_DELEGATIONS_PER_TASK=3
  MAX_WORKER_RETRIES=1
  MAX_WORKER_SECONDS=120
  emit_redirect "$(printf "line1\nline2\twith\ttabs\rand\\\\backslash")"
')" || true
printf '%s' "$out" | jq empty
echo "PASS: control characters in the reason are escaped"

echo "--- Test 6: fails open with no config ---"
rc=0
echo '{}' | bash "$SCRIPT" --mode=hook --platform=claude --config=/nonexistent.yaml >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: expected exit 0, got $rc"; exit 1; }
echo "PASS: fails open"

echo "--- Test 7: pass emits nothing on stdout ---"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'one\ntwo\n' > "$tmp/tiny.tf"
out="$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$tmp/tiny.tf" \
  | bash "$SCRIPT" --mode=hook --platform=claude --config=/nonexistent.yaml 2>/dev/null)"
[ -z "$out" ] || { echo "FAIL: pass must emit nothing, got: $out"; exit 1; }
echo "PASS: pass is silent"

echo "--- Test 8: running in an unconfigured directory creates nothing ---"
clean="$(mktemp -d)"
( cd "$clean" && printf '{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"}}' \
  | bash "$OLDPWD/$SCRIPT" --mode=hook --platform=claude --config=/nope.yaml >/dev/null 2>&1 ) || true
created="$(find "$clean" -mindepth 1 | wc -l | tr -d ' ')"
rm -rf "$clean"
[ "$created" -eq 0 ] || { echo "FAIL: created $created path(s) in an unconfigured directory"; exit 1; }
echo "PASS: no directory pollution"

echo "✅ token-optimizer script checks passed"

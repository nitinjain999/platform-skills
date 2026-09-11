#!/usr/bin/env bash
# Regression tests for every defect reported in the second review.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPT="$SCRIPT_DIR/optimize.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf 'FAIL %s\n     expected=[%s] actual=[%s]\n' "$1" "$2" "$3"; }
eq(){ [[ "$2" == "$3" ]] && ok "$1" || no "$1" "$2" "$3"; }

W="$(mktemp -d)"; CLEANUP_DIRS="$W"; trap 'rm -rf $CLEANUP_DIRS' EXIT
cd "$W"
mkdir -p .token-optimizer/state
awk 'BEGIN{for(i=1;i<=40;i++) print "line " i}'     > small.tf
awk 'BEGIN{for(i=1;i<=1000;i++) print "line " i}'   > large.tf
awk 'BEGIN{for(i=1;i<=100000;i++) print "line " i}' > huge.tf
awk 'BEGIN{s="";for(i=1;i<=51200;i++) s=s "x"; print s}' > min.js
awk 'BEGIN{s="";for(i=1;i<=40000;i++) s=s "y"; for(i=1;i<=5;i++) print s; for(i=1;i<=50;i++) print "tiny"}' > fatlines.js
# terminated lines then an UNTERMINATED 50 KiB final line
{ printf 'a\nb\nc\n'; awk 'BEGIN{s="";for(i=1;i<=51200;i++) s=s "z"; printf "%s", s}'; } > unterm.txt

cfg(){ cat > "$W/$1"; }
cfg redirect.yaml <<'Y'
version: 1
mode: redirect
worker_agent: platform-bulk-reader
max_lines: 350
max_bytes: 32768
max_range_ratio: 80
exempt_agent_types:
  - platform-bulk-reader
log: /dev/null
state_dir: .token-optimizer/state
Y
cfg disabled.yaml <<'Y'
version: 1
enabled: false
mode: redirect
max_lines: 350
max_bytes: 32768
log: /dev/null
state_dir: .token-optimizer/state
Y
cfg badthresh.yaml <<'Y'
version: 1
mode: redirect
max_lines: -1
max_bytes: 32768
log: /dev/null
state_dir: .token-optimizer/state
Y
cfg future.yaml <<'Y'
version: 99
mode: redirect
max_lines: 1
log: /dev/null
Y

hook(){ # hook <payload> <platform> <config>
  printf '%s' "$1" | bash "$OPT" --mode=hook --platform="$2" --config="$W/$3" 2>/dev/null
}
hookrc(){ printf '%s' "$1" | bash "$OPT" --mode=hook --platform="$2" --config="$W/$3" >/dev/null 2>&1; echo $?; }

BIG="{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$W/large.tf\"},\"session_id\":\"S-A\"}"
BIG_B="{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$W/large.tf\"},\"session_id\":\"S-B\"}"
SMALL="{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$W/small.tf\"},\"session_id\":\"S-A\"}"
WORKER="{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$W/large.tf\"},\"agent_type\":\"platform-bulk-reader\",\"session_id\":\"S-A\"}"

echo "=== P1 #1: enabled:false actually disables ==="
eq "enabled:false exits 0"        "0"  "$(hookrc "$BIG" claude disabled.yaml)"
eq "enabled:false emits nothing"  ""   "$(hook   "$BIG" claude disabled.yaml)"
out="$(hook "$BIG" claude redirect.yaml)"
eq "control: enabled absent denies" "0" "$(printf '%s' "$out" | jq empty >/dev/null 2>&1; echo $?)"
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null && ok "control: redirect emits JSON deny" || no "control: redirect emits JSON deny" "present" "absent"

echo "=== P1 #2: bounded recovery, per session, requires persistence ==="
rm -f .token-optimizer/state/*
out1="$(hook "$BIG" claude redirect.yaml)"
eq "session A attempt 1 denies"   "0"  "$(hookrc "$BIG" claude redirect.yaml)"
printf '%s' "$out1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null && ok "session A attempt 1 emits deny" || no "session A attempt 1 emits deny" "present" "absent"
eq "session A attempt 2 proceeds" "0"  "$(hookrc "$BIG" claude redirect.yaml)"
out2="$(hook "$BIG" claude redirect.yaml)"
eq "session A attempt 2 emits nothing" "" "$out2"
eq "session A attempt 3 proceeds" "0"  "$(hookrc "$BIG" claude redirect.yaml)"
out3="$(hook "$BIG_B" claude redirect.yaml)"
eq "session B still gets its own first denial" "0" "$(hookrc "$BIG_B" claude redirect.yaml)"
printf '%s' "$out3" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null && ok "session B first attempt emits deny" || no "session B first attempt emits deny" "present" "absent"
eq "session B second proceeds"    "0"  "$(hookrc "$BIG_B" claude redirect.yaml)"
# No state dir -> cannot bound -> must not deny at all
cfg nostate.yaml <<Y
version: 1
mode: redirect
max_lines: 350
max_bytes: 32768
log: /dev/null
state_dir: $W/absent_dir
Y
eq "no state dir: never denies (no deadlock)" "0" "$(hookrc "$BIG" claude nostate.yaml)"
eq "no state dir: repeat also 0"              "0" "$(hookrc "$BIG" claude nostate.yaml)"
# No session id at all -> cannot scope state -> must not deny
NOSESS="{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$W/large.tf\"}}"
nosess_rc="$( unset TOKEN_OPTIMIZER_SESSION CLAUDE_SESSION_ID COPILOT_SESSION_ID
  printf '%s' "$NOSESS" | bash "$OPT" --mode=hook --platform=claude --config="$W/redirect.yaml" >/dev/null 2>&1
  echo $? )"
eq "no session id: never denies" "0" "$nosess_rc"

echo "=== P1 #3: platform caps the mode ==="
rm -f .token-optimizer/state/*
eq "copilot never redirects"          "0"  "$(hookrc "$BIG" copilot redirect.yaml)"
eq "copilot emits nothing"            ""   "$(hook   "$BIG" copilot redirect.yaml)"
eq "vscode never redirects"           "0"  "$(hookrc "$BIG" vscode  redirect.yaml)"
rm -f .token-optimizer/state/*
out_claude="$(hook "$BIG" claude redirect.yaml)"
eq "claude exits 0"                   "0"  "$(hookrc "$BIG" claude redirect.yaml)"
printf '%s' "$out_claude" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null && ok "claude emits deny envelope" || no "claude emits deny envelope" "present" "absent"

echo "=== P2 #4: classify args, defaults, unterminated line ==="
eq "classify 40-line window of 1000 passes" "pass" \
   "$(bash "$OPT" --mode=classify --path="$W/large.tf" --limit=40 --config="$W/redirect.yaml" 2>/dev/null)"
eq "classify whole 1000-line file oversized" "oversized" \
   "$(bash "$OPT" --mode=classify --path="$W/large.tf" --config="$W/redirect.yaml" 2>/dev/null)"
eq "classify offset+limit window passes" "pass" \
   "$(bash "$OPT" --mode=classify --path="$W/large.tf" --offset=500 --limit=40 --config="$W/redirect.yaml" 2>/dev/null)"
eq "unterminated 50KiB final line is caught" "oversized" \
   "$(bash "$OPT" --mode=classify --path="$W/unterm.txt" --config="$W/redirect.yaml" 2>/dev/null)"
eq "unterminated final line via offset is caught" "oversized" \
   "$(bash "$OPT" --mode=classify --path="$W/unterm.txt" --offset=3 --limit=1 --config="$W/redirect.yaml" 2>/dev/null)"
eq "5-line range of fat lines oversized" "oversized" \
   "$(bash "$OPT" --mode=classify --path="$W/fatlines.js" --limit=5 --config="$W/redirect.yaml" 2>/dev/null)"
eq "70000 of 100000 oversized" "oversized" \
   "$(bash "$OPT" --mode=classify --path="$W/huge.tf" --limit=70000 --config="$W/redirect.yaml" 2>/dev/null)"
eq "minified whole file oversized" "oversized" \
   "$(bash "$OPT" --mode=classify --path="$W/min.js" --config="$W/redirect.yaml" 2>/dev/null)"
# claude default_read_limit auto-applies
out="$(bash "$OPT" --mode=explain --platform=claude --path="$W/huge.tf" --config="$W/redirect.yaml" 2>/dev/null)"
eq "claude default_read_limit auto 2000" "2000" "$(printf '%s\n' "$out" | awk -F': +' '/default_read_limit/{print $2+0}')"
out2="$(bash "$OPT" --mode=explain --platform=copilot --path="$W/huge.tf" --config="$W/redirect.yaml" 2>/dev/null)"
eq "copilot default_read_limit unknown" "unknown" "$(printf '%s\n' "$out2" | awk -F': +' '/default_read_limit/{print $2}' | cut -d' ' -f1)"

echo "=== P2 #5: DEGRADED propagates; config validated ==="
bash -c 'source '"$OPT"' --source-only; DEGRADED=0; normalize_payload "{not json"; echo "rc=$?"; echo "DEGRADED=$DEGRADED"' \
  > "$W/deg.out" 2>/dev/null
eq "normalize_payload returns 1"       "rc=1"       "$(sed -n 1p "$W/deg.out")"
eq "DEGRADED reaches the caller"       "DEGRADED=1" "$(sed -n 2p "$W/deg.out")"
eq "malformed payload never denies"    "0"  "$(hookrc '{not json' claude redirect.yaml)"
eq "max_lines:-1 does not deny a small read" "0" "$(hookrc "$SMALL" claude badthresh.yaml)"
eq "future schema version does not deny"     "0" "$(hookrc "$BIG" claude future.yaml)"

echo "=== P2 #6: explain output and none-platform state suppression ==="
ex="$(bash "$OPT" --mode=explain --platform=claude --path="$W/large.tf" --config="$W/redirect.yaml" 2>/dev/null)"
for field in "requested lines" "requested bytes" "effective mode" "counts as whole file" "decision"; do
  printf '%s\n' "$ex" | grep -q "$field" && ok "explain prints '$field'" || no "explain prints '$field'" "present" "absent"
done
ex2="$(bash "$OPT" --mode=explain --platform=copilot --path="$W/large.tf" --config="$W/redirect.yaml" 2>/dev/null)"
printf '%s\n' "$ex2" | grep -q "capped to audit" && ok "explain shows the copilot cap reason" || no "explain cap reason" "present" "absent"
before="$(find .token-optimizer/state -type f 2>/dev/null | wc -l | tr -d ' ')"
printf '%s' "$BIG" | bash "$OPT" --mode=hook --platform=none --config="$W/redirect.yaml" >/dev/null 2>&1
after="$(find .token-optimizer/state -type f 2>/dev/null | wc -l | tr -d ' ')"
eq "platform=none writes no recovery state" "$before" "$after"

echo "=== unchanged guarantees ==="
rm -f .token-optimizer/state/*
eq "pass emits nothing"      ""  "$(hook "$SMALL" claude redirect.yaml)"
eq "worker read exempt"      "0" "$(hookrc "$WORKER" claude redirect.yaml)"
eq "worker read silent"      ""  "$(hook  "$WORKER" claude redirect.yaml)"
WRITE="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$W/large.tf\",\"new_string\":\"x\"},\"session_id\":\"S-A\"}"
eq "write not our concern"   "0" "$(hookrc "$WRITE" claude redirect.yaml)"
eq "missing config never denies" "0" "$(printf '%s' "$BIG" | bash "$OPT" --mode=hook --platform=claude --config=/nope.yaml >/dev/null 2>&1; echo $?)"
# repo-root pollution
CLEAN="$(mktemp -d)"; CLEANUP_DIRS="$CLEANUP_DIRS $CLEAN"; ( cd "$CLEAN"; printf '%s' "$BIG" | bash "$OPT" --mode=hook --platform=claude --config=/nope.yaml >/dev/null 2>&1 )
eq "unconfigured dir left untouched" "0" "$(find "$CLEAN" -mindepth 1 | wc -l | tr -d ' ')"

echo "=== classify_size globals survive the call (the subshell bug) ==="
ex="$(bash "$OPT" --mode=explain --platform=claude --path="$W/large.tf" --config="$W/redirect.yaml" 2>/dev/null)"
val(){ printf '%s\n' "$ex" | awk -F': +' -v k="$1" '$0 ~ "^"k {print $2; exit}'; }
eq "explain reports real total lines"     "1000" "$(val 'total lines')"
eq "explain reports real requested lines" "1000" "$(val 'requested lines')"
rb="$(val 'requested bytes')"; rb="${rb%% *}"
[[ "$rb" -gt 8000 ]] && ok "explain reports measured bytes ($rb)" || no "explain measured bytes" ">8000" "$rb"
case "$(val 'counts as whole file')" in yes*) ok "explain flags whole-file read" ;; *) no "explain whole-file flag" "yes" "$(val 'counts as whole file')" ;; esac

echo "=== cumulative counter is actually fed (was receiving 0) ==="
cfg cumul.yaml <<Y
version: 1
mode: audit
max_lines: 350
max_bytes: 32768
cumulative_lines: 100
cumulative_bytes: 1000
log: $W/cumul.log
state_dir: .token-optimizer/state
Y
: > "$W/cumul.log"
hookrc "$BIG" claude cumul.yaml >/dev/null
grep -q "cumulative_exceeded" "$W/cumul.log" \
  && ok "cumulative_exceeded is logged" || no "cumulative_exceeded is logged" "present" "absent"

echo "=== a whole-file shell read also counts toward cumulative ==="
: > "$W/cumul.log"; rm -f .token-optimizer/state/*
SHELLBIG="{\"tool_name\":\"bash\",\"toolArgs\":{\"command\":\"cat $W/large.tf\"},\"session_id\":\"S-C\"}"
hookrc "$SHELLBIG" claude cumul.yaml >/dev/null
grep -q "shell_full_read" "$W/cumul.log" && ok "shell full read logged" || no "shell full read logged" "present" "absent"
grep -q "cumulative_exceeded" "$W/cumul.log" && ok "shell read feeds cumulative" || no "shell read feeds cumulative" "present" "absent"

echo "=== worker budgets and evidence contract reach the model ==="
rm -f .token-optimizer/state/*
reason="$(hook "$BIG" claude redirect.yaml | jq -r '.hookSpecificOutput.permissionDecisionReason')"
for token in "complete|partial|blocked" "hash them yourself" "delegations for this task" "retries" "seconds"; do
  case "$reason" in *"$token"*) ok "redirect reason carries '$token'" ;; *) no "redirect reason carries '$token'" "present" "absent" ;; esac
done

echo "=== advisory mode is silent on both read and shell paths ==="
cfg advisory.yaml <<'Y'
version: 1
mode: advisory
max_lines: 350
max_bytes: 32768
log: /dev/null
state_dir: .token-optimizer/state
Y
adv_read_out="$(hook "$BIG" claude advisory.yaml)"
eq "advisory mode: Read emits nothing" "" "$adv_read_out"
SHELLBIG_ADV="{\"tool_name\":\"bash\",\"toolArgs\":{\"command\":\"cat $W/large.tf\"},\"session_id\":\"S-ADV\"}"
adv_shell_out="$(hook "$SHELLBIG_ADV" claude advisory.yaml)"
eq "advisory mode: shell emits nothing" "" "$adv_shell_out"

echo "=== json_escape handles newline in path ==="
rm -f .token-optimizer/state/*
mkdir -p "$W/bad"$'\n'"dir"
echo "line 1" > "$W/bad"$'\n'"dir/file.txt"
for i in {2..1000}; do echo "line $i"; done >> "$W/bad"$'\n'"dir/file.txt"
NEWLINE_PATH="{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$W/bad"$'\n'"dir/file.txt\"},\"session_id\":\"S-NL\"}"
nl_out="$(hook "$NEWLINE_PATH" claude redirect.yaml)"
printf '%s' "$nl_out" | jq empty >/dev/null 2>&1 && ok "newline in path produces valid JSON" || no "newline in path produces valid JSON" "valid" "invalid"
# audit mode should still log, so check via a real log file
cfg audit_log.yaml <<Y
version: 1
mode: audit
max_lines: 350
max_bytes: 32768
log: $W/audit.log
state_dir: .token-optimizer/state
Y
: > "$W/audit.log"
hookrc "$BIG" claude audit_log.yaml >/dev/null
count_audit_read="$(wc -l < "$W/audit.log" 2>/dev/null | tr -d ' ')"
eq "audit mode: Read logs one line" "1" "$count_audit_read"
: > "$W/audit.log"
SHELLBIG_AUD="{\"tool_name\":\"bash\",\"toolArgs\":{\"command\":\"cat $W/large.tf\"},\"session_id\":\"S-AUD\"}"
hookrc "$SHELLBIG_AUD" claude audit_log.yaml >/dev/null
count_audit_shell="$(wc -l < "$W/audit.log" 2>/dev/null | tr -d ' ')"
eq "audit mode: shell logs one line" "1" "$count_audit_shell"

echo "=== payload content cannot forge a field boundary (newline in file_path) ==="
# A newline-delimited parse let a file_path containing a newline shift every
# later field: the offset landed in limit, the session id was lost, and the
# truncated path failed classification so an oversized read passed unchallenged.
shift_out="$(bash -c 'source '"$OPT"' --source-only
  normalize_payload "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/a/b.tf\\nEXTRA\",\"offset\":7,\"limit\":9},\"agent_type\":\"w\",\"session_id\":\"S-SHIFT\"}"
  printf "%s|%s|%s|%s" "$P_OFFSET" "$P_LIMIT" "$P_AGENT_TYPE" "$P_SESSION"')"
eq "newline in path does not shift offset/limit/agent/session" "7|9|w|S-SHIFT" "$shift_out"
cmd_out="$(bash -c 'source '"$OPT"' --source-only
  normalize_payload "{\"toolName\":\"bash\",\"toolArgs\":{\"command\":\"cat /a/b.tf\\nrm -rf /\"},\"session_id\":\"S-CMD\"}"
  printf "%s" "$P_SESSION"')"
eq "multiline shell command does not shift the session id" "S-CMD" "$cmd_out"

echo "=== searches are sized by their output, never by the underlying file ==="
# A Grep with output_mode=count against a 1000-line file returns one number.
# Classifying it by file size denied it — a false positive that spends a
# delegation on nothing and makes the optimizer look broken.
grep_payload() { printf '{"tool_name":"Grep","tool_input":{"path":"%s/large.tf","pattern":"line"%s},"session_id":"S-G"}' "$W" "$1"; }
rm -f .token-optimizer/state/*
eq "grep output_mode=count is not denied"            "" "$(hook "$(grep_payload ',"output_mode":"count"')" claude redirect.yaml)"
eq "grep files_with_matches is not denied"           "" "$(hook "$(grep_payload ',"output_mode":"files_with_matches"')" claude redirect.yaml)"
eq "grep content with small head_limit is not denied" "" "$(hook "$(grep_payload ',"output_mode":"content","head_limit":10')" claude redirect.yaml)"
eq "unbounded content grep is not denied"            "" "$(hook "$(grep_payload ',"output_mode":"content"')" claude redirect.yaml)"
rm -f .token-optimizer/state/*
big_grep="$(hook "$(grep_payload ',"output_mode":"content","head_limit":900')" claude redirect.yaml)"
case "$big_grep" in *'"permissionDecision":"deny"'*) ok "grep content with head_limit above max_lines IS denied" ;; *) no "grep head_limit=900 denied" "deny envelope" "$big_grep" ;; esac
# control: the same file read wholesale must still be denied
rm -f .token-optimizer/state/*
whole="$(hook "$BIG" claude redirect.yaml)"
case "$whole" in *'"permissionDecision":"deny"'*) ok "control: a whole-file Read is still denied" ;; *) no "control: whole-file Read denied" "deny envelope" "$whole" ;; esac

echo "=== tool arguments sent as a JSON string are parsed, not discarded ==="
argstr="$(bash -c 'source '"$OPT"' --source-only
  normalize_payload "{\"toolName\":\"view\",\"toolArgs\":\"{\\\"path\\\":\\\"/x/large.tf\\\"}\"}"
  printf "%s" "$P_PATH"')"
eq "JSON-string toolArgs yields the path" "/x/large.tf" "$argstr"
malformed="$(bash -c 'source '"$OPT"' --source-only
  DEGRADED=0; normalize_payload "{\"toolName\":\"view\",\"toolArgs\":\"cat main.tf\"}" >/dev/null 2>&1
  printf "%s" "$DEGRADED"')"
eq "non-JSON string toolArgs degrades rather than passing silently" "1" "$malformed"

echo "=== search output is never sized from unrelated source bytes ==="
# 40,000 unrelated characters on line 1, then `needle` on line 2. A content search
# for needle with head_limit 10 returns 7 bytes, but sizing the first 10 SOURCE
# lines measured 40,008 and denied it.
{ awk 'BEGIN{s="";for(i=1;i<=40000;i++) s=s "x"; print s}'; echo "needle"; } > "$W/hay.txt"
hay_payload() { printf '{"tool_name":"Grep","tool_input":{"path":"%s/hay.txt","pattern":"needle","output_mode":"content","head_limit":%s},"session_id":"S-H"}' "$W" "$1"; }
rm -f .token-optimizer/state/*
eq "small head_limit on a huge-line file is not denied" "" "$(hook "$(hay_payload 10)" claude redirect.yaml)"
rm -f .token-optimizer/state/*
big_hay="$(hook "$(hay_payload 900)" claude redirect.yaml)"
case "$big_hay" in *'"permissionDecision":"deny"'*) ok "head_limit above max_lines is still denied" ;; *) no "head_limit=900 denied" "deny envelope" "$big_hay" ;; esac
# the same file read wholesale IS large, and must still be denied on real bytes
rm -f .token-optimizer/state/*
hay_read="$(hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$W/hay.txt\"},\"session_id\":\"S-H\"}" claude redirect.yaml)"
case "$hay_read" in *'"permissionDecision":"deny"'*) ok "a whole-file Read of the same file is denied on real bytes" ;; *) no "whole-file Read denied" "deny envelope" "$hay_read" ;; esac

echo "=== a search without a path is still classified ==="
# `[[ -n "$P_PATH" ]] || return 0` used to sit ABOVE the search branch. glob, list,
# codebase and usages routinely omit a path, and a repo-wide grep does too, so a
# pathless head_limit:900 returned before the line gate AND before the
# search_unsizable audit — it logged nothing at all, making the bypass invisible.
nopath() { printf '{"tool_name":"%s","tool_input":{"pattern":"x"%s},"session_id":"S-NP"}' "$1" "$2"; }
rm -f .token-optimizer/state/*
np_grep="$(hook "$(nopath Grep ',"output_mode":"content","head_limit":900')" claude redirect.yaml)"
case "$np_grep" in *'"permissionDecision":"deny"'*) ok "pathless grep with head_limit=900 IS denied" ;; *) no "pathless grep denied" "deny envelope" "$np_grep" ;; esac
rm -f .token-optimizer/state/*
np_glob="$(hook "$(nopath Glob ',"head_limit":900')" claude redirect.yaml)"
case "$np_glob" in *'"permissionDecision":"deny"'*) ok "pathless glob with head_limit=900 IS denied" ;; *) no "pathless glob denied" "deny envelope" "$np_glob" ;; esac
rm -f .token-optimizer/state/*
eq "pathless grep under max_lines is not denied" "" "$(hook "$(nopath Grep ',"output_mode":"content","head_limit":10')" claude redirect.yaml)"
eq "pathless unbounded grep is not denied"       "" "$(hook "$(nopath Grep ',"output_mode":"content"')" claude redirect.yaml)"
# a content read still needs a path — that requirement moved, it did not vanish
eq "a Read with no path is still a no-op" "" "$(hook '{"tool_name":"Read","tool_input":{},"session_id":"S-NP"}' claude redirect.yaml)"

echo "=== head_limit counts matches, so -A/-B/-C expansion counts too ==="
# head_limit bounds MATCHES, not emitted lines. 100 matches with -C 10 can emit
# ~2100 lines, which sailed through a max_lines:350 gate classified as "100".
ctx() { printf '{"tool_name":"Grep","tool_input":{"path":"%s/large.tf","pattern":"line","output_mode":"content","head_limit":100%s},"session_id":"S-CTX"}' "$W" "$1"; }
rm -f .token-optimizer/state/*
eq "head_limit=100 with no context is not denied" "" "$(hook "$(ctx '')" claude redirect.yaml)"
rm -f .token-optimizer/state/*
ctx_c="$(hook "$(ctx ',"-C":10')" claude redirect.yaml)"
case "$ctx_c" in *'"permissionDecision":"deny"'*) ok "head_limit=100 with -C 10 (bound 2200) IS denied" ;; *) no "-C 10 denied" "deny envelope" "$ctx_c" ;; esac
rm -f .token-optimizer/state/*
ctx_a="$(hook "$(ctx ',"-A":2')" claude redirect.yaml)"
case "$ctx_a" in *'"permissionDecision":"deny"'*) ok "head_limit=100 with -A 2 (bound 400) IS denied" ;; *) no "-A 2 denied" "deny envelope" "$ctx_a" ;; esac
# multiline lets ONE match span arbitrarily many lines and nothing in the request
# caps that, so it is unsizable: pass and audit rather than claim a bound.
rm -f .token-optimizer/state/*
eq "multiline search is unsizable, so not denied" "" "$(hook "$(printf '{"tool_name":"Grep","tool_input":{"path":"%s/large.tf","pattern":"line","output_mode":"content","head_limit":10,"multiline":true},"session_id":"S-CTX"}' "$W")" claude redirect.yaml)"
# the derivation is purely request-side: assert the arithmetic directly
ctx_bound="$(bash -c 'source '"$OPT"' --source-only; search_requested_lines content 100 10 10 false')"
eq "search_requested_lines expands 100 matches with -C 10 to 2200" "2200" "$ctx_bound"
ctx_plain="$(bash -c 'source '"$OPT"' --source-only; search_requested_lines content 100 0 0 false')"
eq "search_requested_lines leaves 100 matches with no context at 100" "100" "$ctx_plain"
ml_rc="$(bash -c 'source '"$OPT"' --source-only; search_requested_lines content 10 0 0 true >/dev/null; echo $?')"
eq "search_requested_lines reports multiline as unsizable" "1" "$ml_rc"
# and the line-only classifier must never report source bytes
lineonly="$(bash -c 'source '"$OPT"' --source-only; MAX_LINES=350; MAX_BYTES=32768
  classify_lines_only 10 >/dev/null; printf "%s|%s" "$REQ_LINES" "$REQ_BYTES"')"
eq "classify_lines_only reports no bytes at all" "10|0" "$lineonly"

echo "=== string tool arguments must decode to an OBJECT, not any JSON value ==="
# `try {ok:true, v:fromjson}` accepted a scalar or an array, so toolArgs "null",
# "[]" or "42" decoded "successfully", collapsed to {}, and passed with an empty
# path and no degradation — the same silent hole as an unparsed string.
for bad in 'null' '[]' '42' '"just a string"'; do
  d="$(bash -c 'source '"$OPT"' --source-only
    DEGRADED=0
    normalize_payload "{\"toolName\":\"view\",\"toolArgs\":\"'"$(printf '%s' "$bad" | sed 's/"/\\\\"/g')"'\"}" >/dev/null 2>&1
    printf "%s" "$DEGRADED"')"
  eq "toolArgs decoding to $bad degrades" "1" "$d"
done
okpath="$(bash -c 'source '"$OPT"' --source-only
  normalize_payload "{\"toolName\":\"view\",\"toolArgs\":\"{\\\"path\\\":\\\"/x/a.tf\\\"}\"}"
  printf "%s" "$P_PATH"')"
eq "a JSON object string still yields its path" "/x/a.tf" "$okpath"

echo
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1

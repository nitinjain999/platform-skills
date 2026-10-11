#!/usr/bin/env bash
# tests/plugin-evals.sh — run the claude plugin eval suite in plugin-evals/ and
# gate on a score floor and on regression against plugin-evals/baseline.json.
#
# Every run is a billed model call on the caller's credential. The suite is not
# wired into CI yet (no model credential in the repository); run it locally
# before merging a change to a covered domain, and see plugin-evals/README.md.
#
# Usage:
#   bash tests/plugin-evals.sh --changed origin/main   # only domains this branch touched (PR mode)
#   bash tests/plugin-evals.sh --all                   # every case (nightly mode)
# Options:
#   --runs N             runs per case per arm (default 1 for --changed, 2 for --all)
#   --ablation MODE      none | with-without (default none for --changed, with-without for --all)
#   --max-cost-usd X     hard ceiling for this invocation (default 3 for --changed,
#                        6 for --all: six cases cost about $2.40 per with+without
#                        run pair, so 2 runs is about $4.80)
#   --model M            pin the agent model (recommended in CI)
#   --judge-model M      pin the judge model (only llm/baseline graders use it)
#   --update-baseline    write the scores of this run to plugin-evals/baseline.json
#   --dry-run            print the selected tags and the claude command; no model call
#
# A case also fails when its tool_used Skill grader failed in any run of the
# with-plugin arm: a correct answer that did not come from the plugin is not a
# pass. Under with-without the CLI does not score that grader at all, so the
# check is made here rather than through the score.
#
# Exit codes: 0 pass or nothing to evaluate, 1 below floor / regressed / skill
# not fired / load error, 2 partial run (cost ceiling or credential), 3 bad usage
# or prerequisites.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
EVAL_DIR="plugin-evals"
BASELINE="$EVAL_DIR/baseline.json"

MODE="" BASE_REF="" RUNS="" ABLATION="" COST="" MODEL="" JUDGE="" UPDATE=0 DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --changed) MODE=changed; BASE_REF="${2:?--changed needs a base ref}"; shift 2 ;;
    --all) MODE=all; shift ;;
    --runs) RUNS="${2:?}"; shift 2 ;;
    --ablation) ABLATION="${2:?}"; shift 2 ;;
    --max-cost-usd) COST="${2:?}"; shift 2 ;;
    --model) MODEL="${2:?}"; shift 2 ;;
    --judge-model) JUDGE="${2:?}"; shift 2 ;;
    --update-baseline) UPDATE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 3 ;;
  esac
done
[ -n "$MODE" ] || { echo "choose --changed <base-ref> or --all" >&2; exit 3; }
[ "$MODE" = all ] && RUNS="${RUNS:-2}" ABLATION="${ABLATION:-with-without}" COST="${COST:-6}"
[ "$MODE" = changed ] && RUNS="${RUNS:-1}" ABLATION="${ABLATION:-none}" COST="${COST:-3}"

command -v claude >/dev/null 2>&1 || { echo "claude CLI not found" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found" >&2; exit 3; }

# Domain map: changed path (extended regex) -> eval tag. A change to anything
# that shapes every answer (the router skill, the manifest, the suite itself,
# this runner) runs every case.
DOMAIN_MAP='
^(skills/(fluxcd|gitops)/|references/fluxcd[^/]*\.md$|examples/fluxcd/)	fluxcd
^(skills/opa/|references/opa\.md$|examples/opa/)	opa
^(skills/(triage|pr-review)/|references/triage\.md$|examples/triage/)	triage
^(skills/(secrets|kubernetes)/|references/secrets\.md$)	secrets
^(skills/(kyverno|opa|kubernetes)/|references/kyverno\.md$)	kyverno
^(skills/(openshift|kubernetes)/|references/openshift\.md$)	openshift
^(skills/platform-skills/|SKILL\.md$|\.claude-plugin/plugin\.json$|plugin-evals/|tests/plugin-evals\.sh$)	ALL
'

TAGS=()
if [ "$MODE" = changed ]; then
  changed="$(git diff --name-only "$(git merge-base "$BASE_REF" HEAD)" HEAD)"
  all=0
  while IFS=$'\t' read -r re tag; do
    [ -z "$re" ] && continue
    if printf '%s\n' "$changed" | grep -qE "$re"; then
      if [ "$tag" = ALL ]; then all=1; else TAGS+=("$tag"); fi
    fi
  done <<< "$DOMAIN_MAP"
  if [ "$all" -eq 0 ] && [ "${#TAGS[@]}" -eq 0 ]; then
    echo "plugin-evals: no eval-covered domain changed since $BASE_REF; nothing to evaluate"
    exit 0
  fi
  [ "$all" -eq 1 ] && TAGS=()
fi

OUT_DIR="$(mktemp -d)"
RESULT="$OUT_DIR/result.json"
args=(claude plugin eval . --trust-plugin --no-publish --threshold 0
      --runs "$RUNS" --ablation "$ABLATION" --max-cost-usd "$COST" --json "$RESULT")
[ -n "$MODEL" ] && args+=(--model "$MODEL")
[ -n "$JUDGE" ] && args+=(--judge-model "$JUDGE")
[ "${#TAGS[@]}" -gt 0 ] && args+=(--tag "${TAGS[@]}")

echo "plugin-evals: ${TAGS[*]:-all cases} · runs=$RUNS · ablation=$ABLATION · ceiling \$$COST"
if [ "$DRY" -eq 1 ]; then printf '%q ' "${args[@]}"; echo; exit 0; fi
set +e
"${args[@]}"
rc=$?
set -e
# --threshold 0 means a non-zero exit is never a score verdict: 1 is a load or
# start failure, 2 a partial run. Scores are judged below, against the baseline.
if [ "$rc" -eq 2 ]; then echo "FAIL: partial run (cost ceiling or credential); scores not comparable" >&2; exit 2; fi
if [ "$rc" -ne 0 ]; then echo "FAIL: claude plugin eval exited $rc (case load or run start failure)" >&2; exit 1; fi

python3 -I - "$RESULT" "$BASELINE" "$UPDATE" <<'PY'
import json, sys
result_path, baseline_path, update = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
res = json.load(open(result_path))
try:
    base = json.load(open(baseline_path))
except FileNotFoundError:
    base = {"floor": 0.7, "tolerance": 0.15, "cases": {}}
floor, tol = base.get("floor", 0.7), base.get("tolerance", 0.15)
failures = 0
print(f"\n{'CASE':22} {'SCORE':>6} {'BASE':>6} {'DELTA_VS_NOPLUGIN':>18}  VERDICT")
for case in res.get("cases", []):
    name = case["name"]
    agg = case.get("aggregates", {})
    score = agg.get("score", 0.0)
    ref = base["cases"].get(name, {}).get("score")
    with_runs = case.get("arms", {}).get("with", [])
    errors = [r.get("error") for r in with_runs if r.get("error")]
    skill = {g["name"] for g in case.get("graders", [])
             if g.get("type") == "tool_used" and g.get("config", {}).get("tool") == "Skill"}
    fired = sum(1 for r in with_runs
                if any(g.get("name") in skill and g.get("passed") for g in r.get("graders", [])))
    verdict = "ok"
    if errors:
        verdict = f"FAIL run error: {errors[0]}"
    elif not skill:
        verdict = "FAIL no tool_used Skill grader in the result"
    elif fired < len(with_runs):
        verdict = f"FAIL plugin skill fired in {fired}/{len(with_runs)} runs"
    elif score < floor:
        verdict = f"FAIL below floor {floor}"
    elif ref is not None and score < ref - tol:
        verdict = f"FAIL regressed > {tol} vs baseline"
    elif ref is None:
        verdict = "ok (new case, no baseline yet)"
    if verdict.startswith("FAIL"):
        failures += 1
    delta = agg.get("delta")
    print(f"{name:22} {score:6.2f} {('-' if ref is None else f'{ref:.2f}'):>6} {('-' if delta is None else f'{delta:+.2f}'):>18}  {verdict}")
print(f"\ncost ${res.get('costUsd', 0):.2f} · {res.get('durationSeconds', 0)}s · claude {res.get('claudeVersion')}")
if update:
    if res.get("partial"):
        print("refusing --update-baseline: partial run"); sys.exit(1)
    for case in res.get("cases", []):
        base["cases"][case["name"]] = {"score": round(case["aggregates"]["score"], 4)}
    base["floor"], base["tolerance"] = floor, tol
    json.dump(base, open(baseline_path, "w"), indent=2, sort_keys=True)
    open(baseline_path, "a").write("\n")
    print(f"baseline updated: {baseline_path}")
sys.exit(1 if failures else 0)
PY

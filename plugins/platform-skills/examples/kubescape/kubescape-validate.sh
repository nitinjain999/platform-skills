#!/usr/bin/env bash
# Offline validator for examples/kubescape/
# Run from anywhere: bash examples/kubescape/kubescape-validate.sh
# Requires: bash, python3 with PyYAML. When the kubescape CLI is on PATH it also
# proves the gate: the hardened manifests pass and the insecure one fails.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$ROOT_DIR/examples/kubescape"
WORKFLOW="$DIR/workflows/kubescape.yml"

ERRORS=0
ok() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

echo ""
echo "=== Kubescape example structure ==="
for f in README.md exceptions.json workflows/kubescape.yml \
         manifests/insecure/deployment.yaml \
         manifests/hardened/deployment.yaml manifests/hardened/networkpolicy.yaml; do
  if [ -f "$DIR/$f" ]; then ok "$f exists"; else fail "$f missing"; fi
done

if grep -qE '^Status: (Stable|Beta|Draft|Experimental)' "$DIR/README.md" 2>/dev/null; then
  ok "README.md has a Status: line"
else
  fail "README.md needs a 'Status:' line near the top"
fi

echo ""
echo "=== exceptions.json follows the postureExceptionPolicy schema ==="
# Each entry needs a reason-bearing name, the fixed policyType, one action and
# at least one resource and one policy. Kubescape (opa-utils v0.0.315) treats the
# two actions differently: "disable" removes the finding from the score and the
# gates; "alertOnly" keeps it failing. A disable entry is an accepted risk, so
# its name must carry an until-YYYY-MM-DD review date. Expiry itself is enforced
# by the CI workflow, not here, so this repository's CI never expires.
if python3 -I - "$DIR/exceptions.json" <<'PY'
import json, re, sys
entries = json.load(open(sys.argv[1]))
assert isinstance(entries, list) and entries, "exceptions.json must be a non-empty list"
for e in entries:
    name = e.get("name", "<unnamed>")
    assert e.get("name"), "every exception needs a name"
    assert e.get("policyType") == "postureExceptionPolicy", f"{name}: policyType must be postureExceptionPolicy"
    assert e.get("actions") in (["disable"], ["alertOnly"]), f"{name}: actions must be [disable] or [alertOnly]"
    if e["actions"] == ["disable"]:
        assert re.search(r"until-\d{4}-\d{2}-\d{2}$", name), f"{name}: a disable exception needs an until-YYYY-MM-DD suffix"
    res = e.get("resources") or []
    assert res and all(r.get("designatorType") == "Attributes" and r.get("attributes") for r in res), \
        f"{name}: resources need designatorType Attributes and attributes"
    pols = e.get("posturePolicies") or []
    assert pols and all(p.get("controlID") or p.get("frameworkName") for p in pols), \
        f"{name}: posturePolicies need controlID or frameworkName"
    assert not any("controlName" in p for p in pols), f"{name}: controlName is deprecated; use controlID"
PY
then
  ok "exceptions.json entries are well formed"
else
  fail "exceptions.json is malformed (see the assertion above)"
fi

echo ""
echo "=== Manifests and workflow parse ==="
for f in manifests/insecure/deployment.yaml manifests/hardened/deployment.yaml \
         manifests/hardened/networkpolicy.yaml workflows/kubescape.yml; do
  [ -f "$DIR/$f" ] || continue
  if python3 -I -c 'import sys, yaml; list(yaml.safe_load_all(open(sys.argv[1])))' "$DIR/$f" 2>/dev/null; then
    ok "$f is valid YAML"
  else
    fail "$f is invalid YAML"
  fi
done

echo ""
echo "=== CI workflow supply-chain rules ==="
if [ -f "$WORKFLOW" ]; then
  # kubescape/github-action's latest release bundles CLI v3.0.21 and its README
  # recommends @main plus tj-actions/changed-files; the workflow installs a
  # signature-verified CLI instead.
  if grep -qE 'uses:[[:space:]]*kubescape/github-action' "$WORKFLOW"; then
    fail "workflow uses kubescape/github-action (stale CLI); install the pinned CLI instead"
  else
    ok "workflow does not use kubescape/github-action"
  fi
  if grep -qE 'uses:[[:space:]]*tj-actions/' "$WORKFLOW"; then
    fail "workflow uses tj-actions/* (compromised in March 2025)"
  else
    ok "workflow does not use tj-actions/*"
  fi
  unpinned="$(grep -nE '^[[:space:]]*-?[[:space:]]*uses:' "$WORKFLOW" | grep -vE '@[0-9a-f]{40}' || true)"
  if [ -z "$unpinned" ]; then
    ok "every uses: is pinned to a full commit SHA"
  else
    fail "unpinned uses: $unpinned"
  fi
  version="$(sed -nE 's/^[[:space:]]*KUBESCAPE_VERSION:[[:space:]]*"?([0-9]+\.[0-9]+\.[0-9]+)"?.*/\1/p' "$WORKFLOW" | head -1)"
  if [ -n "$version" ]; then
    ok "KUBESCAPE_VERSION pinned to $version"
  else
    fail "KUBESCAPE_VERSION must be pinned to an exact X.Y.Z"
  fi
  if grep -q 'cosign verify-blob' "$WORKFLOW" \
     && grep -q 'certificate-identity "https://github.com/kubescape/kubescape/.github/workflows/02-release.yaml@refs/tags/v${KUBESCAPE_VERSION}"' "$WORKFLOW" \
     && grep -q 'certificate-oidc-issuer "https://token.actions.githubusercontent.com"' "$WORKFLOW"; then
    ok "CLI download is verified with cosign against the release workflow identity"
  else
    fail "workflow must cosign verify-blob checksums.sha256 against the 02-release.yaml identity and GitHub OIDC issuer"
  fi
  if grep -qE 'sha256sum (--check|-c)' "$WORKFLOW"; then
    ok "tarball checked against the verified checksums"
  else
    fail "workflow must sha256sum --check the tarball against checksums.sha256"
  fi
  if grep -q 'persist-credentials: false' "$WORKFLOW"; then
    ok "checkout does not persist credentials"
  else
    fail "actions/checkout must set persist-credentials: false"
  fi

  # A required check must start on every PR: a workflow skipped by a paths
  # filter leaves the required check pending and blocks the merge.
  # (PyYAML reads the bare key `on` as boolean True.)
  if python3 -I - "$WORKFLOW" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
on = doc.get("on", doc.get(True, {})) or {}
pr = on.get("pull_request") if isinstance(on, dict) else None
sys.exit(1 if isinstance(pr, dict) and ("paths" in pr or "paths-ignore" in pr) else 0)
PY
  then
    ok "pull_request trigger has no paths filter (required check always reports)"
  else
    fail "pull_request must not use paths/paths-ignore: a skipped required check blocks merges"
  fi

  # Inline kubescape.io/skip-controls annotations are honoured by default on
  # local files and would let a PR suppress its own finding without review.
  scans="$(grep -cE '^[[:space:]]*kubescape scan ' "$WORKFLOW" || true)"
  hardened="$(grep -A3 -E '^[[:space:]]*kubescape scan ' "$WORKFLOW" | grep -c -- '--honor-inline-exceptions=false' || true)"
  if [ "$scans" -gt 0 ] && [ "$scans" = "$hardened" ]; then
    ok "all $scans kubescape scans pass --honor-inline-exceptions=false"
  else
    fail "every kubescape scan must pass --honor-inline-exceptions=false ($hardened of $scans do)"
  fi

  if grep -q 'helm dependency build' "$WORKFLOW"; then
    ok "Helm chart dependencies are built (and fail loudly) before scanning"
  else
    fail "workflow must run 'helm dependency build' for charts under SCAN_PATH; kubescape only warns when its own build fails"
  fi

  # Behaviour test of chart discovery in the dependency step: it must find chart
  # roots whether SCAN_PATH is k8s/, charts/ or a chart itself, and must not
  # descend into a chart's own charts/ (vendored subcharts). A stub helm records
  # what would be built, so no network is needed. Needs yq (preinstalled on
  # GitHub runners); skipped without it.
  depstep="$(python3 -I -c '
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for s in doc["jobs"]["posture"]["steps"]:
    if s.get("name") == "Build Helm chart dependencies":
        print(s["run"]); break' "$WORKFLOW")"
  if ! command -v yq >/dev/null 2>&1; then
    echo "  SKIP: yq not on PATH; chart discovery not exercised"
  elif [ -n "$depstep" ]; then
    tmpd="$(mktemp -d)"
    mkdir -p "$tmpd/bin"
    printf '#!/usr/bin/env bash\necho "$*" >> "%s/helm.log"\n' "$tmpd" > "$tmpd/bin/helm"; chmod +x "$tmpd/bin/helm"
    chart() { mkdir -p "$1"; printf 'apiVersion: v2\nname: %s\nversion: 0.1.0\n' "$(basename "$1")" > "$1/Chart.yaml"
              [ "${2:-}" = deps ] && printf 'dependencies:\n  - name: redis\n    version: 1.0.0\n    repository: https://charts.example.com\n' >> "$1/Chart.yaml"; return 0; }
    # layout A: SCAN_PATH=charts with charts/api (deps) and a vendored subchart that also lists deps
    chart "$tmpd/a/charts/api" deps; chart "$tmpd/a/charts/api/charts/redis" deps; chart "$tmpd/a/charts/web"
    # layout B: SCAN_PATH=k8s with k8s/payments (deps)
    chart "$tmpd/b/k8s/payments" deps
    # layout C: SCAN_PATH is the chart itself
    chart "$tmpd/c/charts/api" deps
    for c in "a:charts:charts/api" "b:k8s:k8s/payments" "c:charts/api:charts/api"; do
      ws="${c%%:*}"; rest="${c#*:}"; sp="${rest%%:*}"; want="${rest#*:}"
      : > "$tmpd/helm.log"
      (cd "$tmpd/$ws" && PATH="$tmpd/bin:$PATH" GITHUB_WORKSPACE="$tmpd/$ws" RUNNER_TEMP="$tmpd/rt-$ws" SCAN_PATH="$sp" bash -c "$depstep") >/dev/null 2>&1 || true
      builds="$(grep -c '^dependency build ' "$tmpd/helm.log" || true)"
      if grep -q "^dependency build $tmpd/$ws/$want\$" "$tmpd/helm.log" && [ "$builds" = 1 ]; then
        ok "chart discovery: SCAN_PATH=$sp builds $want only (vendored subcharts skipped)"
      else
        fail "chart discovery: SCAN_PATH=$sp should build exactly $want, helm saw: $(tr '\n' ';' < "$tmpd/helm.log")"
      fi
    done
    rm -rf "$tmpd"
  fi

  # Behaviour test of the exception-policy step against crafted files.
  step="$(python3 -I -c '
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for s in doc["jobs"]["posture"]["steps"]:
    if s.get("name") == "Check exception policy":
        print(s["run"]); break' "$WORKFLOW")"
  if [ -z "$step" ]; then
    fail "workflow needs a 'Check exception policy' step"
  elif grep -q "hashFiles('.kubescape" "$WORKFLOW"; then
    fail "exception check must use \$EXCEPTIONS, not a hard-coded hashFiles() path"
  else
    tmpx="$(mktemp -d)"
    mk() { printf '[{"name":"%s","policyType":"postureExceptionPolicy","actions":%s,"resources":[{"designatorType":"Attributes","attributes":{"kind":".*"}}],"posturePolicies":[{"controlID":"C-0030"}]}]' "$1" "$2" > "$tmpx/$3.json"; }
    mk "accepted-until-2999-12-31" '["disable"]' valid
    mk "accepted-until-2000-01-01" '["disable"]' expired
    mk "accepted-without-a-date" '["disable"]' undated
    mk "known-issue-kept-visible" '["alertOnly"]' alertonly
    # opa-utils v0.0.315 suppresses unless every matching exception is explicitly
    # alertOnly: a mixed list, an empty or missing actions field and an unknown
    # value all suppress. Only the singletons are accepted, whatever the date.
    mk "mixed-until-2999-12-31" '["alertOnly","disable"]' mixed
    mk "mixed-without-a-date" '["alertOnly","disable"]' mixed_undated
    mk "empty-until-2999-12-31" '[]' empty
    mk "unknown-until-2999-12-31" '["ignore"]' unknown
    printf '[{"name":"no-actions-until-2999-12-31","policyType":"postureExceptionPolicy","resources":[{"designatorType":"Attributes","attributes":{"kind":".*"}}],"posturePolicies":[{"controlID":"C-0030"}]}]' > "$tmpx/noactions.json"
    for c in valid:0 alertonly:0 expired:1 undated:1 mixed:1 mixed_undated:1 empty:1 unknown:1 noactions:1 missing:0; do
      f="${c%%:*}"; want="${c##*:}"
      if EXCEPTIONS="$tmpx/$f.json" bash -c "$step" >/dev/null 2>&1; then got=0; else got=1; fi
      if [ "$got" = "$want" ]; then ok "exception policy: $f → exit $got"; else fail "exception policy: $f → exit $got, want $want"; fi
    done
    rm -rf "$tmpx"
  fi
fi

echo ""
echo "=== Gate behaviour (kubescape CLI) ==="
if command -v kubescape >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  if kubescape scan framework nsa "$DIR/manifests/hardened" --severity-threshold medium \
       --format json --output "$tmp/hardened.json" >/dev/null 2>&1; then
    ok "hardened manifests pass NSA at --severity-threshold medium"
  else
    fail "hardened manifests should pass NSA at --severity-threshold medium"
  fi
  if kubescape scan framework nsa "$DIR/manifests/insecure" --severity-threshold medium \
       --format json --output "$tmp/insecure.json" >/dev/null 2>&1; then
    fail "insecure manifest should fail NSA at --severity-threshold medium"
  else
    ok "insecure manifest fails NSA at --severity-threshold medium"
  fi
else
  echo "  SKIP: kubescape not on PATH; gate behaviour not exercised"
fi

echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS kubescape example error(s)"
  exit 1
fi
echo "PASS: kubescape example checks passed"

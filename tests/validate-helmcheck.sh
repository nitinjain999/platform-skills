#!/usr/bin/env bash
# Validates the helmcheck skill, command, reference guide, and example chart.
# Run from the repository root: bash tests/validate-helmcheck.sh

set -euo pipefail

ERRORS=0

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

# ---------------------------------------------------------------------------
echo ""
echo "=== Helmcheck command file ==="

CMD="commands/helmcheck.md"

if [ -f "$CMD" ]; then
  pass "$CMD exists"
else
  fail "$CMD missing"
fi

for field in "^name:" "^description:" "^argument-hint:"; do
  if grep -qE "$field" "$CMD"; then
    pass "$CMD has '$field'"
  else
    fail "$CMD missing '$field'"
  fi
done

for mode in "create" "review" "security"; do
  if grep -q "## Mode: $mode" "$CMD"; then
    pass "$CMD defines Mode: $mode"
  else
    fail "$CMD missing Mode: $mode section"
  fi
done

if grep -q "kubeconform" "$CMD" && ! grep -q "kubeval" "$CMD"; then
  pass "$CMD uses kubeconform (not deprecated kubeval)"
else
  fail "$CMD still references deprecated kubeval or missing kubeconform"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Helmcheck slash command registered in plugin.json ==="

if grep -q '"./commands/helmcheck.md"' .claude-plugin/plugin.json; then
  pass "commands/helmcheck.md registered in plugin.json"
else
  fail "commands/helmcheck.md not registered in plugin.json"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== SKILL.md helmcheck integration ==="

SKILL="skills/platform-skills/SKILL.md"

if grep -q "Helm (Helmcheck)" "$SKILL"; then
  pass "SKILL.md lists Helm domain"
else
  fail "SKILL.md missing Helm domain entry"
fi

if grep -q "helmcheck" "$SKILL"; then
  pass "SKILL.md references /platform-skills:helmcheck slash command"
else
  fail "SKILL.md missing /platform-skills:helmcheck slash command"
fi

if grep -q "references/helm.md" "$SKILL"; then
  pass "SKILL.md references references/helm.md"
else
  fail "SKILL.md does not reference references/helm.md"
fi

if grep -q "kubeconform" "$SKILL" && ! grep -q "kubeval" "$SKILL"; then
  pass "SKILL.md uses kubeconform (not deprecated kubeval)"
else
  fail "SKILL.md still references deprecated kubeval or missing kubeconform"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== references/helm.md ==="

REF="references/helm.md"

if [ -f "$REF" ]; then
  pass "$REF exists"
else
  fail "$REF missing"
fi

for section in "_helpers.tpl" "values.yaml" "Lint and Validation Pipeline" "values.schema.json" "Dependency Management" "GitOps Integration"; do
  if grep -q "$section" "$REF"; then
    pass "$REF contains section: $section"
  else
    fail "$REF missing section: $section"
  fi
done

if grep -q "kubeconform" "$REF" && ! grep -q "kubeval" "$REF"; then
  pass "$REF uses kubeconform (not deprecated kubeval)"
else
  fail "$REF still references deprecated kubeval or missing kubeconform"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== examples/helm/web-service chart structure ==="

CHART="examples/helm/web-service"

REQUIRED_FILES=(
  "$CHART/Chart.yaml"
  "$CHART/values.yaml"
  "$CHART/values.schema.json"
  "$CHART/.helmignore"
  "$CHART/templates/_helpers.tpl"
  "$CHART/templates/deployment.yaml"
  "$CHART/templates/service.yaml"
  "$CHART/templates/serviceaccount.yaml"
  "$CHART/templates/ingress.yaml"
  "$CHART/templates/hpa.yaml"
  "$CHART/templates/pdb.yaml"
  "$CHART/templates/networkpolicy.yaml"
  "$CHART/templates/NOTES.txt"
  "$CHART/templates/tests/test-connection.yaml"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [ -f "$f" ]; then
    pass "$f exists"
  else
    fail "$f missing"
  fi
done

# ---------------------------------------------------------------------------
echo ""
echo "=== Chart.yaml correctness ==="

CHART_YAML="$CHART/Chart.yaml"

if grep -q "^apiVersion: v2$" "$CHART_YAML"; then
  pass "Chart.yaml uses apiVersion: v2"
else
  fail "Chart.yaml missing apiVersion: v2"
fi

for field in "^name:" "^description:" "^version:" "^appVersion:"; do
  if grep -qE "$field" "$CHART_YAML"; then
    pass "Chart.yaml has '$field'"
  else
    fail "Chart.yaml missing '$field'"
  fi
done

# ---------------------------------------------------------------------------
echo ""
echo "=== values.schema.json correctness ==="

SCHEMA="$CHART/values.schema.json"

DUPLICATE_PROPS=$(python3 - "$SCHEMA" <<'PYEOF'
import json, sys
# Only check top-level properties keys for duplicates.
# Nested objects legitimately reuse keywords like "type", "minimum", etc.
top_pairs = []
def top_level_hook(lst):
    top_pairs.extend(k for k, _ in lst)
    return dict(lst)
with open(sys.argv[1]) as f:
    raw = f.read()
import re
# Extract only the top-level properties object by loading the doc normally
# then re-parsing just its keys via a targeted hook on the root document.
root_pairs = []
def root_hook(lst):
    root_pairs.extend(k for k, _ in lst)
    return dict(lst)
import io
json.load(io.StringIO(raw), object_pairs_hook=root_hook)
# root_pairs contains ALL keys at every depth; find true top-level property names
# by checking the 'properties' value of the root object directly
doc = json.loads(raw)
prop_names = list(doc.get("properties", {}).keys())
# Count occurrences in root_pairs to detect top-level property duplication
dups = [k for k in set(prop_names) if root_pairs.count(k) > 1]
print(",".join(sorted(set(dups))) if dups else "ok")
PYEOF
)
if [ "$DUPLICATE_PROPS" = "ok" ]; then
  pass "values.schema.json has no duplicate property keys"
else
  fail "values.schema.json has duplicate property keys: $DUPLICATE_PROPS"
fi

if python3 -c "import json; json.load(open('$SCHEMA')); print('ok')" 2>/dev/null | grep -q "ok"; then
  pass "values.schema.json is valid JSON"
else
  fail "values.schema.json is invalid JSON"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Security baselines in values.yaml ==="

VALUES="$CHART/values.yaml"

for check in "runAsNonRoot" "readOnlyRootFilesystem" "allowPrivilegeEscalation" "seccompProfile" "capabilities"; do
  if grep -q "$check" "$VALUES"; then
    pass "values.yaml contains $check"
  else
    fail "values.yaml missing security default: $check"
  fi
done

if grep -q "automount: false" "$VALUES"; then
  pass "values.yaml has automount: false"
else
  fail "values.yaml missing automount: false for ServiceAccount"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Template safety checks ==="

DEPLOYMENT="$CHART/templates/deployment.yaml"
HELPERS="$CHART/templates/_helpers.tpl"
NETPOL="$CHART/templates/networkpolicy.yaml"
TEST_POD="$CHART/templates/tests/test-connection.yaml"

# Image tag must fall back to AppVersion
if grep -q "\.Values\.image\.tag | default \.Chart\.AppVersion" "$DEPLOYMENT"; then
  pass "deployment.yaml uses .Chart.AppVersion fallback for image tag"
else
  fail "deployment.yaml missing AppVersion fallback — image tag may be hardcoded"
fi

# automountServiceAccountToken on pod spec must be wired to values (default false)
if grep -q "automountServiceAccountToken: {{ .Values.serviceAccount.automount }}" "$DEPLOYMENT"; then
  pass "deployment.yaml wires automountServiceAccountToken to .Values.serviceAccount.automount"
else
  fail "deployment.yaml missing automountServiceAccountToken wired to .Values.serviceAccount.automount"
fi

# emptyDir for /tmp (required when readOnlyRootFilesystem: true)
if grep -q "emptyDir" "$DEPLOYMENT"; then
  pass "deployment.yaml mounts emptyDir for writable scratch space"
else
  fail "deployment.yaml missing emptyDir — readOnlyRootFilesystem will break apps writing to /tmp"
fi

# selectorLabels must NOT contain app.kubernetes.io/version
SELECTOR_BLOCK=$(awk '/define.*selectorLabels/,/^{{- end }}/' "$HELPERS")
if echo "$SELECTOR_BLOCK" | grep -q "app.kubernetes.io/version"; then
  fail "_helpers.tpl selectorLabels contains app.kubernetes.io/version — immutable after creation, breaks upgrades"
else
  pass "_helpers.tpl selectorLabels does not contain app.kubernetes.io/version"
fi

# NetworkPolicy must not reference deprecated kubeval
if grep -q "kubeval" "$NETPOL"; then
  fail "networkpolicy.yaml references deprecated kubeval — replace with kubeconform"
else
  pass "networkpolicy.yaml does not reference deprecated kubeval"
fi

# NetworkPolicy — both ingress AND egress policy types declared
if grep -q "Ingress" "$NETPOL" && grep -q "Egress" "$NETPOL"; then
  pass "networkpolicy.yaml declares both Ingress and Egress policyTypes"
else
  fail "networkpolicy.yaml missing Ingress or Egress in policyTypes"
fi

# Test pod must have securityContext
if grep -q "runAsNonRoot" "$TEST_POD"; then
  pass "test-connection.yaml has pod securityContext (runAsNonRoot)"
else
  fail "test-connection.yaml missing securityContext — will fail restricted PodSecurity namespaces"
fi

# Test pod image must be pinned (not bare busybox)
if grep -q "busybox:" "$TEST_POD"; then
  pass "test-connection.yaml uses pinned busybox image tag"
else
  fail "test-connection.yaml uses unpinned 'busybox' image (resolves to latest)"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== examples/helm/README.md ==="

HELM_README="examples/helm/README.md"

if grep -q "^Status:" "$HELM_README"; then
  pass "$HELM_README has Status maturity label"
else
  fail "$HELM_README missing Status maturity label"
fi

if grep -q "kubeconform" "$HELM_README" && ! grep -q "kubeval" "$HELM_README"; then
  pass "$HELM_README uses kubeconform (not deprecated kubeval)"
else
  fail "$HELM_README still references deprecated kubeval or missing kubeconform"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== HOW_IT_WORKS.md completeness ==="

HOW="HOW_IT_WORKS.md"

if [ -f "$HOW" ]; then
  pass "$HOW exists"
else
  fail "$HOW missing"
fi

for cmd in "helmcheck" "review" "terraform" "debug" "gitops" "compliance" "product" "mcp" "observability" "document" "datadog" "dynatrace" "commit"; do
  if grep -q "platform-skills:$cmd" "$HOW"; then
    pass "$HOW references /platform-skills:$cmd"
  else
    fail "$HOW missing /platform-skills:$cmd in slash command table"
  fi
done

# ---------------------------------------------------------------------------
echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS validation error(s)"
  exit 1
fi

echo "PASS: all helmcheck validation checks passed"

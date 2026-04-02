#!/usr/bin/env bash
# Validates that the skill structure is internally consistent.
# Run from the repository root: bash tests/validate-skill.sh

set -euo pipefail

ERRORS=0

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

echo ""
echo "=== SKILL.md ==="

# Must have YAML frontmatter
if head -1 SKILL.md | grep -q "^---"; then
  pass "SKILL.md has frontmatter"
else
  fail "SKILL.md missing frontmatter"
fi

# Must have name and description fields
for field in "^name:" "^description:"; do
  if sed -n '/^---$/,/^---$/p' SKILL.md | grep -qE "$field"; then
    pass "SKILL.md frontmatter has '${field}' field"
  else
    fail "SKILL.md frontmatter missing '${field}' field"
  fi
done

echo ""
echo "=== Reference files ==="

REQUIRED_REFERENCES=(
  references/platform-operating-model.md
  references/terraform.md
  references/kubernetes.md
  references/openshift.md
  references/flux.md
  references/argocd.md
  references/aws.md
  references/azure.md
  references/github-actions.md
  references/secrets.md
)

for ref in "${REQUIRED_REFERENCES[@]}"; do
  if [ -f "$ref" ]; then
    pass "$ref exists"
  else
    fail "$ref missing"
  fi
done

echo ""
echo "=== Example domains have assets beyond README.md ==="

EXAMPLE_DOMAINS=(
  examples/aws
  examples/azure
  examples/kubernetes
  examples/openshift
  examples/argocd
  examples/flux
  examples/terraform
  examples/github-actions
)

for domain in "${EXAMPLE_DOMAINS[@]}"; do
  ASSET_COUNT=$(find "$domain" -type f ! -name "README.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$ASSET_COUNT" -gt 0 ]; then
    pass "$domain has $ASSET_COUNT asset(s)"
  else
    fail "$domain has no example assets (only README.md)"
  fi
done

echo ""
echo "=== SKILL.md references all required reference files ==="

for ref in "${REQUIRED_REFERENCES[@]}"; do
  if grep -q "$ref" SKILL.md; then
    pass "SKILL.md references $ref"
  else
    fail "SKILL.md does not reference $ref"
  fi
done

echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS validation error(s)"
  exit 1
fi

echo "PASS: all skill structure checks passed"

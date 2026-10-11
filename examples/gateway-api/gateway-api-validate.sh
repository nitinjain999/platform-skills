#!/usr/bin/env bash
# Validates the Gateway API examples and the Flux basic-monorepo that uses them.
#
# Structural checks always run. kubeconform schema checks run when kubeconform
# is installed; Gateway API, cert-manager and Flux kinds are resolved through the
# datreeio CRDs catalog, so a misspelled CRD field fails instead of being skipped.
#
# Usage: bash examples/gateway-api/gateway-api-validate.sh
# Requires: kubectl (for `kubectl kustomize`); kubeconform optional

set -euo pipefail

ERRORS=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MONOREPO="$ROOT_DIR/examples/fluxcd/basic-monorepo"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

CRD_CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

OVERLAYS=(
  infrastructure/production
  infrastructure/staging
  infrastructure/configs/production
  infrastructure/configs/staging
  apps/production
  apps/staging
)

echo ""
echo "=== basic-monorepo: every overlay builds ==="

if ! command -v kubectl >/dev/null 2>&1; then
  fail "kubectl not installed — cannot build overlays"
else
  for overlay in "${OVERLAYS[@]}"; do
    if out="$(kubectl kustomize "$MONOREPO/$overlay" 2>&1)"; then
      pass "$overlay builds"
      if command -v kubeconform >/dev/null 2>&1; then
        if printf '%s\n' "$out" | kubeconform -strict -summary -output text \
            -schema-location default -schema-location "$CRD_CATALOG" - >/dev/null 2>&1; then
          pass "$overlay passes kubeconform (strict, CRD catalog)"
        else
          fail "$overlay fails kubeconform — run: kubectl kustomize $overlay | kubeconform -strict -schema-location default -schema-location '$CRD_CATALOG' -"
        fi
      fi
    else
      fail "$overlay does not build: $out"
    fi
  done
fi

# Flux Kustomizations under clusters/ are applied directly, not through an
# overlay, so they need their own schema pass (healthCheckExprs, dependsOn).
if command -v kubeconform >/dev/null 2>&1; then
  if kubeconform -strict -summary -output text \
      -schema-location default -schema-location "$CRD_CATALOG" \
      "$MONOREPO"/clusters/*/*.yaml >/dev/null 2>&1; then
    pass "clusters/*/*.yaml pass kubeconform (strict, CRD catalog)"
  else
    fail "clusters/*/*.yaml fail kubeconform"
  fi
fi

echo ""
echo "=== basic-monorepo: no retired controller, no removed APIs ==="

# Manifests only: the README names ingress-nginx to explain the migration.
if grep -rIl --include='*.yaml' 'ingress-nginx' "$MONOREPO" >/dev/null 2>&1; then
  fail "ingress-nginx still referenced: $(grep -rIl --include='*.yaml' 'ingress-nginx' "$MONOREPO" | sed "s|$ROOT_DIR/||" | tr '\n' ' ')"
else
  pass "no ingress-nginx references in manifests"
fi

if grep -rIlE '^kind: Ingress$' "$MONOREPO" >/dev/null 2>&1; then
  fail "networking.k8s.io Ingress objects remain — use HTTPRoute"
else
  pass "no Ingress objects"
fi

if grep -rIl 'source.toolkit.fluxcd.io/v1beta2' "$MONOREPO" >/dev/null 2>&1; then
  fail "source.toolkit.fluxcd.io/v1beta2 is not served by Flux 2.9 — use v1"
else
  pass "Flux source APIs are v1"
fi

echo ""
echo "=== basic-monorepo: ordering and access contracts ==="

EG_RELEASE="$MONOREPO/infrastructure/base/envoy-gateway/helmrelease.yaml"
EG_SOURCE="$MONOREPO/infrastructure/base/envoy-gateway/ocirepository.yaml"
CM_RELEASE="$MONOREPO/infrastructure/base/cert-manager/helmrelease.yaml"

if [ -f "$EG_SOURCE" ] && [ "$(yq '.spec.ref.tag' "$EG_SOURCE")" = "v1.9.2" ]; then
  pass "Envoy Gateway chart pinned to v1.9.2"
else
  fail "Envoy Gateway OCIRepository missing or not pinned to v1.9.2"
fi

# cert-manager ignores Gateways if the Gateway API CRDs appear after it starts.
if [ -f "$CM_RELEASE" ] && grep -q 'name: envoy-gateway' "$CM_RELEASE" && grep -q 'dependsOn:' "$CM_RELEASE"; then
  pass "cert-manager HelmRelease dependsOn envoy-gateway (CRDs exist first)"
else
  fail "cert-manager HelmRelease must dependsOn envoy-gateway"
fi

if [ -f "$CM_RELEASE" ] && [ "$(yq '.spec.values.config.gatewayAPI.enabled' "$CM_RELEASE" 2>/dev/null)" = "true" ]; then
  pass "cert-manager config.gatewayAPI.enabled is true"
else
  fail "cert-manager must set values.config.gatewayAPI.enabled: true"
fi

if [ -f "$EG_RELEASE" ] && grep -q 'kind: OCIRepository' "$EG_RELEASE"; then
  pass "Envoy Gateway HelmRelease uses chartRef to the OCIRepository"
else
  fail "Envoy Gateway HelmRelease missing chartRef kind: OCIRepository"
fi

if grep -q 'gateway-access: "true"' "$MONOREPO/apps/base/namespace.yaml"; then
  pass "app namespace opts in to the shared Gateway (gateway-access label)"
else
  fail "apps/base/namespace.yaml missing gateway-access: \"true\" — HTTPRoute will be NotAllowedByListeners"
fi

for env in production staging; do
  apps="$MONOREPO/clusters/$env/apps.yaml"
  if [ "$(yq '.spec.dependsOn[].name' "$apps" 2>/dev/null)" = "infrastructure-configs" ]; then
    pass "clusters/$env/apps.yaml depends on infrastructure-configs"
  else
    fail "clusters/$env/apps.yaml must dependsOn infrastructure-configs"
  fi
  configs="$MONOREPO/clusters/$env/infrastructure-configs.yaml"
  if [ -f "$configs" ] && [ "$(yq '.spec.dependsOn[].name' "$configs")" = "infrastructure" ]; then
    pass "clusters/$env/infrastructure-configs.yaml depends on infrastructure"
  else
    fail "clusters/$env/infrastructure-configs.yaml missing or not dependent on infrastructure"
  fi
done

echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS Gateway API validation error(s)"
  exit 1
fi
echo "All Gateway API checks passed"

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
echo "=== Repository: no manifest still depends on ingress-nginx ==="

# Excluded on purpose: the frozen token-optimizer eval fixtures (changing them
# breaks baseline comparability) and the migration example's "before" state.
STALE="$(cd "$ROOT_DIR" && grep -rIl --include='*.yaml' --include='*.yml' 'ingress-nginx' . \
  --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.claude \
  | grep -v -E '^\./(evals/token-optimizer/|examples/gateway-api/before/)' || true)"
if [ -z "$STALE" ]; then
  pass "no manifest outside the allowlist references ingress-nginx"
else
  fail "manifests still reference ingress-nginx: $(printf '%s' "$STALE" | tr '\n' ' ')"
fi

echo ""
echo "=== Migration example: before and after ==="

BEFORE="$SCRIPT_DIR/before/ingress.yaml"
AFTER="$SCRIPT_DIR/after/httproute.yaml"
if [ -f "$BEFORE" ] && [ -f "$AFTER" ]; then
  pass "before/ingress.yaml and after/httproute.yaml exist"
  if command -v kubeconform >/dev/null 2>&1; then
    if kubeconform -strict -summary -output text \
        -schema-location default -schema-location "$CRD_CATALOG" \
        "$BEFORE" "$SCRIPT_DIR"/after/*.yaml >/dev/null 2>&1; then
      pass "before/after pass kubeconform (strict, CRD catalog)"
    else
      fail "before/after fail kubeconform"
    fi
  fi
  # Every host in the Ingress must survive the conversion. An empty host list
  # would make the loop below pass vacuously, so it is a failure on its own.
  if [ -z "$(yq '.spec.rules[].host' "$BEFORE")" ]; then
    fail "before/ingress.yaml has no rules[].host — nothing to compare"
  fi
  for host in $(yq '.spec.rules[].host' "$BEFORE"); do
    if yq '.spec.hostnames[]' "$AFTER" | grep -qx "$host"; then
      pass "host $host carried into HTTPRoute"
    else
      fail "host $host from the Ingress is missing in the HTTPRoute"
    fi
  done
else
  fail "examples/gateway-api/before/ingress.yaml or after/httproute.yaml missing"
fi

echo ""
echo "=== basic-monorepo: ordering and access contracts ==="

EG_RELEASE="$MONOREPO/infrastructure/base/envoy-gateway/helmrelease.yaml"
EG_SOURCE="$MONOREPO/infrastructure/base/envoy-gateway/ocirepository.yaml"
EG_CRDS="$MONOREPO/infrastructure/base/envoy-gateway/helmrelease-crds.yaml"
CM_RELEASE="$MONOREPO/infrastructure/base/cert-manager/helmrelease.yaml"

if [ -f "$EG_SOURCE" ] && [ "$(yq -N '.spec.ref.tag' "$EG_SOURCE" | sort -u)" = "v1.9.2" ]; then
  pass "Envoy Gateway CRD and controller charts both pinned to v1.9.2"
else
  fail "Envoy Gateway OCIRepository missing or not pinned to v1.9.2"
fi

# cert-manager ignores Gateways if the Gateway API CRDs appear after it starts.
if [ -f "$CM_RELEASE" ] && [ "$(yq '.spec.dependsOn[].name' "$CM_RELEASE")" = "gateway-crds" ]; then
  pass "cert-manager HelmRelease dependsOn gateway-crds (CRDs exist first)"
else
  fail "cert-manager HelmRelease must dependsOn gateway-crds"
fi

# The controller chart bundles experimental-channel CRDs; they must stay off.
if [ -f "$EG_CRDS" ] && [ "$(yq '.spec.values.crds.gatewayAPI.channel' "$EG_CRDS")" = "standard" ] \
    && [ "$(yq '.spec.values.crds.enabled' "$EG_RELEASE")" = "false" ]; then
  pass "Gateway API CRDs are standard channel, owned by gateway-crds only"
else
  fail "gateway-crds must set channel: standard and envoy-gateway must set crds.enabled: false"
fi

# Deleting a CRD deletes every Gateway and HTTPRoute; Helm must keep them.
if [ -f "$EG_CRDS" ] && [ "$(yq '.spec.postRenderers[].kustomize.patches[] | select(.target.kind == "CustomResourceDefinition") | .patch' "$EG_CRDS" | grep -c 'resource-policy')" -ge 1 ]; then
  pass "gateway-crds post-renderer marks CRDs helm.sh/resource-policy: keep"
else
  fail "gateway-crds must post-render helm.sh/resource-policy: keep onto CRDs"
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
  # A route hostname the listener does not cover is NoMatchingListenerHostname.
  if command -v kubectl >/dev/null 2>&1; then
    listener_hosts="$(kubectl kustomize "$MONOREPO/infrastructure/configs/$env" | yq -N 'select(.kind == "Gateway") | .spec.listeners[] | select(.protocol == "HTTPS") | .hostname')"
    route_hosts="$(kubectl kustomize "$MONOREPO/apps/$env" | yq -N 'select(.kind == "HTTPRoute") | .spec.hostnames[]')"
    if [ -z "$route_hosts" ]; then
      fail "apps/$env renders no HTTPRoute hostnames"
    fi
    for h in $route_hosts; do
      if printf '%s\n' "$listener_hosts" | grep -qx "$h"; then
        pass "$env: route hostname $h has a matching HTTPS listener"
      else
        fail "$env: route hostname $h has no HTTPS listener on platform-gateway"
      fi
    done
  fi

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

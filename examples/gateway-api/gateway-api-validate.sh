#!/usr/bin/env bash
# Validates the Gateway API examples and the Flux basic-monorepo that uses them.
#
# Structural checks always run. kubeconform schema checks run when kubeconform
# is installed; Gateway API, cert-manager and Flux kinds are resolved through the
# datreeio CRDs catalog, so a misspelled CRD field fails instead of being skipped.
#
# Usage: bash examples/gateway-api/gateway-api-validate.sh
# Requires: kubectl (for `kubectl kustomize`) and mikefarah yq v4
#           (https://github.com/mikefarah/yq; the Python `yq` wrapper uses a
#           different syntax and will not work). kubeconform is optional
#           locally and required in CI (CI=true), where its absence fails.

set -euo pipefail

# Fail fast with one clear message instead of a cascade of command-not-found
# errors further down: every structural check below depends on yq v4.
if ! command -v yq >/dev/null 2>&1; then
  echo "FAIL: yq not found. Install mikefarah yq v4: https://github.com/mikefarah/yq#install"
  exit 1
fi
if ! yq --version 2>&1 | grep -q 'mikefarah/yq.* v4\.'; then
  echo "FAIL: found '$(yq --version 2>&1 | head -1)', need mikefarah yq v4: https://github.com/mikefarah/yq#install"
  exit 1
fi

ERRORS=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MONOREPO="$ROOT_DIR/examples/fluxcd/basic-monorepo"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

# The schema pass is the only check that sees CRD fields in rendered overlays,
# so CI must never skip it silently.
if [ -n "${CI:-}" ] && ! command -v kubeconform >/dev/null 2>&1; then
  echo "FAIL: CI=true but kubeconform is not installed; the rendered-overlay schema checks would be skipped"
  exit 1
fi

# Pinned to the same catalog commit as .github/workflows/validate.yml
CRD_CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/63669a570e231d4f1f8396d229a1de512bcf0a34/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

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
CM_RELEASE="$MONOREPO/infrastructure/base/cert-manager/helmrelease.yaml"
APP_NAMESPACES="$MONOREPO/infrastructure/configs/base/app-namespaces.yaml"

if [ -f "$EG_SOURCE" ] && [ "$(yq -N '.spec.ref.tag' "$EG_SOURCE")" = "v1.9.2" ]; then
  pass "Envoy Gateway controller chart pinned to v1.9.2"
else
  fail "Envoy Gateway OCIRepository missing or not pinned to v1.9.2"
fi

# The CRDs are too large for a Helm release Secret (1 MiB), so they must be
# plain Flux Kustomizations, and the controller chart must not install them.
if grep -rqE '^  name: gateway-crds$' "$MONOREPO/infrastructure" 2>/dev/null; then
  fail "a gateway-crds HelmRelease is back in infrastructure/: CRDs exceed the Helm release size limit"
else
  pass "no Helm release manages the Gateway CRDs"
fi
if [ "$(yq '.spec.values.crds.enabled' "$EG_RELEASE")" = "false" ]; then
  pass "envoy-gateway chart does not install its bundled experimental CRDs"
else
  fail "envoy-gateway must set values.crds.enabled: false"
fi

for env in production staging; do
  crds="$MONOREPO/clusters/$env/gateway-crds.yaml"
  infra="$MONOREPO/clusters/$env/infrastructure.yaml"
  if [ ! -f "$crds" ]; then
    fail "clusters/$env/gateway-crds.yaml missing"
    continue
  fi
  # Standard channel from the pinned Gateway API release, EG CRDs from the same
  # pinned chart artifact as the controller, never the experimental file.
  if [ "$(yq -N 'select(.kind == "GitRepository") | .spec.ref.tag' "$crds")" = "v1.6.1" ] \
      && [ "$(yq -N 'select(.kind == "Kustomization" and .metadata.name == "gateway-api-crds") | .spec.path' "$crds")" = "./config/crd/standard" ]; then
    pass "$env: Gateway API CRDs are the standard channel of v1.6.1"
  else
    fail "$env: gateway-api-crds must apply ./config/crd/standard from tag v1.6.1"
  fi
  if [ "$(yq -N 'select(.kind == "OCIRepository") | .spec.ref.tag' "$crds")" = "v1.9.2" ] \
      && [ "$(yq -N 'select(.kind == "Kustomization" and .metadata.name == "envoy-gateway-crds") | .spec.path' "$crds")" = "./gateway-helm/charts/crds/crds/generated" ]; then
    pass "$env: Envoy Gateway CRDs come from the v1.9.2 chart's generated/ dir only"
  else
    fail "$env: envoy-gateway-crds must apply ./gateway-helm/charts/crds/crds/generated from tag v1.9.2"
  fi
  # Deleting a CRD deletes every Gateway and HTTPRoute in the cluster.
  if [ "$(yq -N 'select(.kind == "Kustomization") | (.spec.prune == false and .spec.deletionPolicy == "Orphan")' "$crds" | sort -u)" = "true" ]; then
    pass "$env: CRD Kustomizations never delete CRDs (prune: false, deletionPolicy: Orphan)"
  else
    fail "$env: every CRD Kustomization needs prune: false and deletionPolicy: Orphan"
  fi
  # cert-manager ignores Gateways if the CRDs appear after it starts.
  if [ "$(yq -N '.spec.dependsOn[].name' "$infra" | sort | tr '\n' ' ')" = "envoy-gateway-crds gateway-api-crds " ]; then
    pass "$env: infrastructure dependsOn both CRD Kustomizations (CRDs before cert-manager starts)"
  else
    fail "$env: clusters/$env/infrastructure.yaml must dependsOn gateway-api-crds and envoy-gateway-crds"
  fi
done

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

# Each HTTPS listener must name the one namespace that owns its hostname, by
# the immutable kubernetes.io/metadata.name label. A shared opt-in label lets
# every onboarded team attach to every listener and claim another's hostname.
for env in production staging; do
  if ! listeners="$(kubectl kustomize "$MONOREPO/infrastructure/configs/$env" \
      | yq -N 'select(.kind == "Gateway") | .spec.listeners[] | select(.protocol == "HTTPS")
               | .name + " " + (.allowedRoutes.namespaces.from // "Same") + " "
                 + (.allowedRoutes.namespaces.selector.matchLabels["kubernetes.io/metadata.name"] // "-")' 2>&1)"; then
    fail "$env: listener check could not run: $listeners"
    continue
  fi
  [ -z "$listeners" ] && fail "$env: no HTTPS listeners rendered"
  while read -r lname lfrom lns; do
    [ -z "$lname" ] && continue
    if [ "$lfrom" = "Selector" ] && [ "$lns" != "-" ] && grep -qE "^  name: ${lns}\$" "$APP_NAMESPACES" 2>/dev/null; then
      pass "$env: listener $lname is bound to namespace $lns, which the platform layer creates"
    else
      fail "$env: listener $lname must select one platform-created namespace by kubernetes.io/metadata.name (got from=$lfrom ns=$lns)"
    fi
  done <<< "$listeners"
done
if grep -rq 'gateway-access' "$MONOREPO" --include='*.yaml' 2>/dev/null; then
  fail "a shared gateway-access label is back: listeners must bind to the owning namespace instead"
else
  pass "no shared gateway opt-in label"
fi

# Namespaces are the unit listeners bind to, so the app layer must not create them.
if grep -rlE '^kind: Namespace$' "$MONOREPO/apps" >/dev/null 2>&1; then
  fail "apps/ defines a Namespace; create app namespaces in infrastructure/configs (platform review)"
else
  pass "app namespaces are owned by the platform layer"
fi

# Two proxy replicas only survive a node failure if they run on different nodes.
if kubectl kustomize "$MONOREPO/infrastructure/configs/production" \
    | yq -e -N 'select(.kind == "EnvoyProxy") | .spec.provider.kubernetes.envoyDeployment.pod.topologySpreadConstraints[] | select(.topologyKey == "kubernetes.io/hostname" and .whenUnsatisfiable == "DoNotSchedule")' >/dev/null 2>&1; then
  pass "production Envoy proxies are spread across nodes (hostname, DoNotSchedule)"
else
  fail "production EnvoyProxy needs a kubernetes.io/hostname topologySpreadConstraint with DoNotSchedule"
fi

# Repository baseline: no CPU limits (CFS throttling); memory limits only.
# A yq error must fail the check, never read as "no CPU limit found".
for overlay in infrastructure/production infrastructure/staging infrastructure/configs/production infrastructure/configs/staging; do
  if ! cpu_limits="$(kubectl kustomize "$MONOREPO/$overlay" \
      | yq -N '.. | select(tag == "!!map" and has("limits")) | .limits | select(tag == "!!map" and has("cpu")) | .cpu' 2>&1)"; then
    fail "$overlay: CPU-limit check could not run: $cpu_limits"
  elif [ -n "$cpu_limits" ]; then
    fail "$overlay sets a CPU limit ($cpu_limits); the baseline is CPU requests plus memory-only limits"
  else
    pass "$overlay sets no CPU limits"
  fi
done

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

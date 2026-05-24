# FluxCD Operator Reference

The Flux Operator manages Flux installations declaratively via two CRDs: `FluxInstance` (desired state) and `FluxReport` (observed state). It replaces the `flux bootstrap` imperative workflow with a fully GitOps-managed lifecycle.

---

## Installation

```bash
# Helm (recommended)
helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system --create-namespace

# Terraform — see references/fluxcd-terraform.md
```

---

## FluxInstance

One instance per cluster. Must be named `flux` in the operator's namespace.

```yaml
apiVersion: fluxcd.controlplane.io/v1
kind: FluxInstance
metadata:
  name: flux          # must be named 'flux' — only one per cluster
  namespace: flux-system
  annotations:
    fluxcd.controlplane.io/reconcileEvery: "1h"   # auto-update check
spec:
  distribution:
    version: "2.x"                         # semver range — tracks latest 2.x
    registry: "ghcr.io/fluxcd"
    imagePullSecret: "ghcr-registry-auth"  # optional, for private registries
  cluster:
    type: kubernetes        # kubernetes | openshift | k3s
    multitenant: false      # enables cross-namespace reference restrictions
    tenantDefaultServiceAccount: flux-reconciler
    networkPolicy: true     # adds NetworkPolicies to flux-system
    clusterDomain: "cluster.local"
  components:
    - source-controller
    - kustomize-controller
    - helm-controller
    - notification-controller
    - image-reflector-controller       # optional: required for image automation
    - image-automation-controller      # optional: required for image automation
    - source-watcher                   # optional: required for ArtifactGenerator
  sync:
    kind: OCIRepository                # OCIRepository (gitless) or GitRepository
    url: "oci://ghcr.io/my-org/fleet-manifests"
    ref: "latest"
    path: "clusters/production"
    pullSecret: "registry-auth"
  storage:
    class: "standard"
    size: "10Gi"
```

### Cluster sizing

| Size | Use case | Concurrency | Memory limit |
|---|---|---|---|
| `small` | dev/test, <10 tenants | 5 | 512Mi |
| `medium` | staging, 10–50 tenants | 10 | 1Gi |
| `large` | production, >50 tenants | 20 | 3Gi |

Set via `kustomize.patches` targeting the controller Deployments, or use `spec.sharding` for horizontal scaling.

### Multi-tenancy

When `multitenant: true`:
- Controllers impersonate the specified service account for reconciliation
- Cross-namespace references are disabled by default
- Each tenant's Kustomization must set `spec.serviceAccountName`

### Sync modes

| Mode | `spec.sync.kind` | When to use |
|---|---|---|
| Gitless (OCI) | `OCIRepository` | Default for Flux Operator — immutable, signable |
| Git | `GitRepository` | Migrating from `flux bootstrap` |

Both create a root Kustomization in `flux-system` that reconciles the configured path.

### Kustomize patches

Apply patches to controller Deployments without forking the distribution:

```yaml
spec:
  kustomize:
    patches:
      - target:
          kind: Deployment
          name: kustomize-controller
        patch: |
          - op: add
            path: /spec/template/spec/tolerations
            value:
              - key: dedicated
                operator: Equal
                value: flux
                effect: NoSchedule
```

### Optional components

| Component | Enables |
|---|---|
| `image-reflector-controller` | ImageRepository, ImagePolicy CRDs |
| `image-automation-controller` | ImageUpdateAutomation CRDs |
| `source-watcher` | ArtifactGenerator CRD (monorepo decomposition) |

---

## FluxReport

Auto-updated every 5 minutes. Reports distribution version, component readiness, reconciler stats, and sync status.

```bash
# Check cluster-wide Flux health
kubectl get fluxreport flux -n flux-system -o yaml

# Key fields to inspect
kubectl get fluxreport flux -n flux-system -o jsonpath='{.status.conditions}'
```

Configure reporting interval:

```yaml
metadata:
  annotations:
    fluxcd.controlplane.io/reconcileEvery: "5m"
```

---

## Runtime ConfigMap

The `flux-runtime-info` ConfigMap holds cluster variables consumed via `postBuild.substituteFrom` across all Kustomizations.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: flux-runtime-info
  namespace: flux-system
  labels:
    reconcile.fluxcd.io/watch: Enabled    # triggers immediate reconciliation on change
  annotations:
    kustomize.toolkit.fluxcd.io/ssa: "Merge"  # preserves fields owned by Terraform
data:
  CLUSTER_NAME: "production-eu"
  CLUSTER_REGION: "eu-west-1"
  ENVIRONMENT: "prod"
  DOMAIN: "example.com"
```

The `reconcile.fluxcd.io/watch: Enabled` label causes any Kustomization with `substituteFrom` referencing this ConfigMap to immediately reconcile when the ConfigMap changes.

---

## Reconciliation triggers

Force immediate reconciliation on any Flux Operator resource:

```bash
kubectl annotate fluxinstance flux -n flux-system \
  fluxcd.controlplane.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite

kubectl annotate fluxreport flux -n flux-system \
  fluxcd.controlplane.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite
```

---

## Tag promotion pattern

Use separate tags per environment — `latest` tracks the main branch (staging), `latest-stable` tracks release tags (production). Each FluxInstance references its environment's tag:

```yaml
# staging FluxInstance
spec:
  sync:
    url: "oci://ghcr.io/my-org/fleet-manifests"
    ref: "latest"            # built from main branch

# production FluxInstance
spec:
  sync:
    url: "oci://ghcr.io/my-org/fleet-manifests"
    ref: "latest-stable"     # built from release tags only
```

CI pushes both tags — `latest` on every merge to main, `latest-stable` only on tagged releases. This gives staging automatic updates and production explicit promotion.

---

## Flux Web UI

The Flux Operator Helm chart bundles a Web UI that shows FluxInstance status, reconciler stats, and cluster sync state. Enable it via Helm values:

```yaml
# values for flux-operator Helm chart
ui:
  enabled: true
  ingress:
    enabled: true
    host: flux.internal.example.com
```

Supports SSO via OIDC providers (Dex, Keycloak, Microsoft Entra ID, OpenShift). No additional installation — it is built into the operator Helm chart.

---

## Migration from `flux bootstrap`

1. Install the Flux Operator (`helm install flux-operator ...`)
2. Create a `FluxInstance` with `sync.kind: GitRepository` pointing to your existing bootstrap repo
3. Verify `FluxReport` shows all components Ready
4. Switch `sync.kind` to `OCIRepository` once you publish OCI artifacts from CI
5. Remove the old `gotk-sync.yaml` and `gotk-components.yaml` from Git

---

## Validation

```bash
# Check FluxInstance status
kubectl get fluxinstance flux -n flux-system
kubectl describe fluxinstance flux -n flux-system

# Check cluster-wide health
kubectl get fluxreport flux -n flux-system -o yaml

# Check controller pod health
kubectl get pods -n flux-system
kubectl logs -n flux-system deploy/source-controller | tail -50
```

# FluxCD Kustomization Reference

The Flux `Kustomization` CRD (`kustomize.toolkit.fluxcd.io/v1`) is managed by kustomize-controller. It is Flux's primary mechanism for deploying manifests to a cluster.

> This is distinct from Kustomize's `kustomization.yaml` config file — they share the name but are different resources.

---

## Minimal example

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m
  prune: true
  sourceRef:
    kind: OCIRepository     # GitRepository | OCIRepository | Bucket | ExternalArtifact
    name: fleet-manifests
  path: ./apps
  wait: true
  timeout: 5m
  serviceAccountName: apps-reconciler    # for multi-tenant RBAC isolation
```

---

## Core fields

| Field | Required | Purpose |
|---|---|---|
| `sourceRef.kind` | Yes | `GitRepository`, `OCIRepository`, `Bucket`, `ExternalArtifact` |
| `sourceRef.name` | Yes | Name of the source object |
| `interval` | Yes | How often to reconcile |
| `prune` | Yes | Delete resources removed from source |
| `path` | No | Subdirectory within the artifact |
| `targetNamespace` | No | Override namespace for all resources |
| `wait` | No | Block until resources are Ready (default: false) |
| `timeout` | No | Fail fast if blocked (default: 5m) |
| `force` | No | Recreate resources that can't be patched |
| `suspend` | No | Pause reconciliation |
| `deletionPolicy` | No | `MirrorPrune` (default), `WaitForTermination` |
| `serviceAccountName` | No | Impersonate this SA for RBAC isolation |

---

## Dependencies

Kustomizations wait until dependencies are Ready before reconciling:

```yaml
spec:
  dependsOn:
    - name: infrastructure
      namespace: flux-system
    - name: cert-manager
      namespace: flux-system
      readyExpr: >
        status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'True')
```

`readyExpr` is a CEL expression with access to `dep` (the dependency object) and `self` (this Kustomization). Use `status.observedGeneration >= 0` as a "reconciled-once" check for CRD-installing Kustomizations.

---

## PostBuild variable substitution

`${VAR}` placeholders are replaced after `kustomize build` but before apply. Variables are sourced from inline `substitute` map or ConfigMaps/Secrets via `substituteFrom`.

```yaml
spec:
  postBuild:
    substitute:
      CLUSTER_NAME: "production-eu"
      REPLICA_COUNT: "3"
    substituteFrom:
      - kind: ConfigMap
        name: flux-runtime-info    # label: reconcile.fluxcd.io/watch: Enabled
        optional: false
      - kind: Secret
        name: cluster-secrets
        optional: true
```

Rules:
- Inline `substitute` values take precedence over `substituteFrom`
- Escape a literal `${VAR}` with `$$` → `$${VAR}`
- Only substitutes within this Kustomization's own `path` — add `substituteFrom` to the Kustomization that owns the manifest, not a sibling

---

## SOPS decryption

```yaml
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age    # key: age.agekey
```

Without `secretRef`, Cloud KMS with workload identity is used (GCP, AWS, Azure).

---

## Health checks

When `wait: true`, standard Kubernetes readiness conditions are evaluated. Custom CEL expressions override the built-in check:

```yaml
spec:
  healthCheckExprs:
    - apiVersion: apps/v1
      kind: Deployment
      current: >
        object.status.conditions.filter(e, e.type == 'Available').all(e, e.status == 'True')
      inProgress: >
        object.status.conditions.filter(e, e.type == 'Progressing').exists(e, e.status == 'True')
      failed: >
        object.status.replicas > 0 && object.status.readyReplicas == 0
```

---

## Remote cluster deployment

**Secret-based (static kubeconfig):**
```yaml
spec:
  kubeConfig:
    secretRef:
      name: remote-cluster-kubeconfig
      key: value
```

**Secretless (workload identity):**
```yaml
spec:
  kubeConfig:
    secretRef:
      name: remote-cluster-config
  # Secret contains provider fields: aws | azure | gcp | generic
```

When both `kubeConfig` and `serviceAccountName` are set, the controller impersonates the service account on the remote cluster.

---

## Apply behaviour annotations

Flux uses server-side apply (SSA). Per-resource annotations tune field ownership:

| Annotation | Value | Behaviour |
|---|---|---|
| `kustomize.toolkit.fluxcd.io/ssa` | `Override` | Flux owns all fields; reverts external edits (default) |
| `kustomize.toolkit.fluxcd.io/ssa` | `Merge` | Preserves non-overlapping fields from other tools (Terraform co-ownership) |
| `kustomize.toolkit.fluxcd.io/ssa` | `IfNotPresent` | Only creates if absent — never updates |
| `kustomize.toolkit.fluxcd.io/ssa` | `Ignore` | Skips this resource entirely |
| `kustomize.toolkit.fluxcd.io/force` | `Enabled` | Recreates on immutable field changes |
| `kustomize.toolkit.fluxcd.io/prune` | `Disabled` | Protects from garbage collection |

---

## Status and inventory

Managed resources are tracked in `status.inventory` using the format:

```
<namespace>_<name>_<group>_<kind>
```

This inventory powers `prune: true` — resources present in the inventory but absent from the current build are deleted.

---

## Reconciliation triggers

```bash
# Force immediate reconciliation (fetches source first)
flux reconcile kustomization apps --with-source -n flux-system

# Annotate directly
kubectl annotate kustomization apps -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite
```

---

## Validation

```bash
# Status overview
flux get kustomizations -A

# Detailed status with events
kubectl describe kustomization apps -n flux-system

# Logs for reconciliation errors
flux logs --kind=Kustomization --name=apps --namespace=flux-system

# List managed inventory
kubectl get kustomization apps -n flux-system -o jsonpath='{.status.inventory.entries[*]}' | tr ' ' '\n'
```

---

## Retry interval

Configure `retryInterval` to recover faster from transient failures without waiting the full `interval`:

```yaml
spec:
  interval: 30m
  retryInterval: 5m    # retry every 5m on failure instead of waiting 30m
```

Without `retryInterval`, a failed Kustomization waits the full `spec.interval` before the next attempt.

---

## Common mistakes

| Mistake | Correct approach |
|---|---|
| `substituteFrom` on a sibling Kustomization | Add `substituteFrom` to the Kustomization that owns the manifest |
| `wait: false` with `dependsOn` | Dependency checks are only meaningful when `wait: true` |
| `prune: true` without testing | Verify `status.inventory` before enabling — garbage collection is immediate |
| Manual edit of a Flux-managed resource | Flux reverts on next reconciliation — add `ssa: Merge` annotation if co-ownership is needed |
| No `retryInterval` set | Flux waits the full `spec.interval` between failure retries — set `retryInterval: 5m` |

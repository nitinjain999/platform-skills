# FluxCD HelmRelease Reference

`HelmRelease` (`helm.toolkit.fluxcd.io/v2`) is managed by helm-controller. It installs, upgrades, tests, and garbage-collects Helm releases with drift detection and structured remediation.

---

## Minimal example

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cert-manager
  namespace: cert-manager
spec:
  interval: 10m
  chartRef:
    kind: OCIRepository
    name: cert-manager
    namespace: flux-system
  values:
    installCRDs: true
  install:
    strategy:
      name: RetryOnFailure    # always use this
```

---

## Chart source — two mutually exclusive approaches

| Approach | When to use | Notes |
|---|---|---|
| `spec.chartRef` | OCI chart sources (recommended) | References an existing `OCIRepository` or `HelmChart`; supports Cosign verification |
| `spec.chart.spec` | HTTPS Helm repos / GitRepository | Auto-creates a `HelmChart` object; cannot be used with `spec.chartRef` |

### Using `spec.chartRef` (OCI — recommended)

```yaml
spec:
  chartRef:
    kind: OCIRepository
    name: cert-manager
    namespace: flux-system
```

### Using `spec.chart.spec` (HTTPS repo)

```yaml
spec:
  chart:
    spec:
      chart: cert-manager
      version: ">=1.13.0"
      sourceRef:
        kind: HelmRepository
        name: jetstack
        namespace: flux-system
```

> Do not set both — they are mutually exclusive.

---

## Values merging

Sources are applied in sequence, each layer overriding the previous:

```yaml
spec:
  valuesFrom:
    - kind: ConfigMap
      name: cert-manager-values       # base values
      valuesKey: values.yaml
    - kind: Secret
      name: cert-manager-secrets      # sensitive overrides
      valuesKey: values.yaml
      optional: true
  values:
    # inline values — applied last, highest precedence
    replicaCount: 2
```

ConfigMaps/Secrets used in `valuesFrom` should carry:

```yaml
labels:
  reconcile.fluxcd.io/watch: Enabled    # triggers immediate HelmRelease reconciliation on change
```

---

## Install / upgrade strategy

Always use `RetryOnFailure` — it retries without uninstalling or rolling back, avoiding downtime and data loss:

```yaml
spec:
  install:
    strategy:
      name: RetryOnFailure
      retryInterval: 3m    # how long to wait between retries (default: interval)
  upgrade:
    strategy:
      name: RetryOnFailure
      retryInterval: 3m
    cleanupOnFail: true
    force: false    # set true only for immutable field changes
```

Set `retryInterval` shorter than `spec.interval` for faster recovery from transient failures. Without it, Flux waits the full reconciliation interval between retries.

> Do not mix modern `install.strategy` with legacy `install.remediation.retries` — they are mutually exclusive.

---

## Drift detection

| Mode | Behaviour |
|---|---|
| `disabled` | No detection (default) |
| `warn` | Detects and reports but does not correct |
| `enabled` | Detects and corrects on every reconciliation |

```yaml
spec:
  driftDetection:
    mode: enabled
    ignore:
      - paths:
          - /spec/replicas    # exclude HPA-managed field
        target:
          kind: Deployment
```

---

## CRD lifecycle

| Value | Install | Upgrade |
|---|---|---|
| `Create` (default) | Installs CRDs | Skips — does not upgrade existing CRDs |
| `Skip` | Skips CRDs | Skips CRDs |
| `CreateReplace` | Installs CRDs | Replaces CRDs — use for breaking CRD upgrades |

```yaml
spec:
  install:
    crds: CreateReplace
  upgrade:
    crds: CreateReplace
```

---

## Dependencies

Wait until listed HelmReleases or Kustomizations are Ready before proceeding:

```yaml
spec:
  dependsOn:
    - name: cert-manager
      namespace: cert-manager
    - name: ingress-nginx
      namespace: ingress-nginx
```

---

## Health check expressions

CEL expressions for custom resource readiness — evaluated when `wait: true` is active:

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

## Post-renderers

Kustomize patches applied after Helm templating, before apply. Useful for injecting annotations, sidecars, or overriding fields the chart doesn't expose as values:

```yaml
spec:
  postRenderers:
    - kustomize:
        patches:
          - target:
              kind: Deployment
              name: ".*"
            patch: |
              - op: add
                path: /spec/template/metadata/annotations/prometheus.io~1scrape
                value: "true"
          - target:
              kind: Ingress
              name: ".*"
            patch: |
              - op: add
                path: /metadata/annotations/nginx.ingress.kubernetes.io~1ssl-redirect
                value: "true"
```

Multiple post-renderers execute sequentially — each renderer's output feeds into the next.

---

## Remote cluster deployment

```yaml
spec:
  kubeConfig:
    secretRef:
      name: remote-cluster-kubeconfig
      key: value
```

---

## Status tracking

```yaml
status:
  conditions:
    - type: Ready
      status: "True"
  history:
    - chartVersion: "1.13.3"
      digest: sha256:abc123...
      firstDeployed: "2024-01-15T10:00:00Z"
      lastDeployed: "2024-01-20T14:30:00Z"
  lastAppliedRevision: "1.13.3+sha256:abc123"
  lastAttemptedRevision: "1.13.3+sha256:abc123"
```

---

## Validation

```bash
# Status overview
flux get helmreleases -A

# Detailed reconciliation trace
kubectl describe helmrelease cert-manager -n cert-manager
flux logs --kind=HelmRelease --name=cert-manager --namespace=cert-manager

# Force immediate reconciliation
flux reconcile helmrelease cert-manager -n cert-manager --with-source

# Check rendered values
kubectl get secret -n cert-manager sh.helm.release.v1.cert-manager.v1 -o jsonpath='{.data.release}' | base64 -d | base64 -d | gunzip | jq '.config'
```

---

## Namespace management

**Never use `targetNamespace` or `createNamespace` on a HelmRelease.** These bypass proper namespace lifecycle management — the namespace is created outside GitOps control and won't be pruned correctly.

Instead, create the target namespace in the parent Kustomization or ResourceSet that deploys the component:

```yaml
# ❌ Wrong — namespace created outside lifecycle control
spec:
  targetNamespace: cert-manager
  install:
    createNamespace: true

# ✅ Correct — namespace owned by the Kustomization
# In the Kustomization that owns this HelmRelease, include a Namespace manifest:
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
```

The namespace must exist before the HelmRelease runs — create it in the parent Kustomization or ResourceSet, never in the HelmRelease itself.

---

## Common mistakes

| Mistake | Correct approach |
|---|---|
| `spec.chart.spec` with `spec.chartRef` set | Mutually exclusive — use one only |
| `install.remediation.retries` (legacy) | Use `install.strategy.name: RetryOnFailure` |
| `valuesFrom` ConfigMap without watch label | Add `reconcile.fluxcd.io/watch: Enabled` or changes won't trigger reconciliation |
| `driftDetection.mode: enabled` without ignore rules | HPA-managed `replicas` will fight with Flux — always ignore `/spec/replicas` |
| `targetNamespace` + `createNamespace: true` on HelmRelease | Create the namespace in the parent Kustomization/ResourceSet instead |
| No `retryInterval` on strategy | Flux waits the full `spec.interval` between retries — set `strategy.retryInterval: 3m` for faster recovery |

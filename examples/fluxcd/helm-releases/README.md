# Helm Release Management with Flux

Status: Beta

Production-ready Helm release management using OCIRepository sources, environment-specific value overlays, and RetryOnFailure remediation.

## Pattern

- Charts sourced from OCI registries (immutable, signed)
- Base HelmRelease with defaults; environment overlays patch values via ConfigMap
- `reconcile.fluxcd.io/watch: Enabled` on all `valuesFrom` ConfigMaps for instant reactivity
- `install.strategy.name: RetryOnFailure` — not the deprecated `install.remediation.retries`

## Directory structure

```text
helm-releases/
├── clusters/
│   ├── staging/
│   │   └── helmreleases.yaml        # Kustomization pointing to releases/
│   └── production/
│       └── helmreleases.yaml
├── releases/
│   ├── base/
│   │   └── cert-manager/
│   │       ├── ocirepository.yaml   # OCI chart source
│   │       ├── helmrelease.yaml     # Base HelmRelease
│   │       └── values-configmap.yaml
│   ├── staging/
│   │   └── kustomization.yaml       # Patches: 1 replica, reduced resources
│   └── production/
│       └── kustomization.yaml       # Patches: 3 replicas, HA, full resources
```

## Key YAML

### OCIRepository chart source

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: cert-manager-chart
  namespace: cert-manager
spec:
  interval: 1h
  url: oci://quay.io/jetstack/charts/cert-manager
  layerSelector:
    mediaType: "application/vnd.cncf.helm.chart.content.v1.tar+gzip"
    operation: copy
  ref:
    semver: "1.x"
```

### HelmRelease with RetryOnFailure

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cert-manager
  namespace: cert-manager
spec:
  interval: 1h
  chartRef:
    kind: OCIRepository
    name: cert-manager-chart
    namespace: cert-manager
  install:
    strategy:
      name: RetryOnFailure
      retryInterval: 5m
  upgrade:
    strategy:
      name: RetryOnFailure
      retryInterval: 5m
  driftDetection:
    mode: enabled
  valuesFrom:
    - kind: ConfigMap
      name: cert-manager-values
```

### valuesFrom ConfigMap with watch label

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cert-manager-values
  namespace: cert-manager
  labels:
    reconcile.fluxcd.io/watch: Enabled   # immediate reconciliation on change
data:
  values.yaml: |
    replicaCount: 1
    resources:
      requests:
        cpu: 10m
        memory: 32Mi
```

### Environment overlay (production)

```yaml
# releases/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base/cert-manager
patches:
  - patch: |
      - op: replace
        path: /data/values.yaml
        value: |
          replicaCount: 3
          podDisruptionBudget:
            enabled: true
            minAvailable: 2
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
    target:
      kind: ConfigMap
      name: cert-manager-values
```

## Common mistakes to avoid

| Mistake | Correct |
|---|---|
| `spec.chart.spec` on HelmRelease | Use `spec.chartRef` for OCI sources |
| `install.remediation.retries: 3` | Use `install.strategy.name: RetryOnFailure` |
| Missing `layerSelector.mediaType` | Required for Helm chart OCI layers |
| `valuesFrom` ConfigMap without watch label | Add `reconcile.fluxcd.io/watch: Enabled` |

## Troubleshooting

```bash
# Check HelmRelease status
flux get helmrelease cert-manager -n cert-manager

# See detailed conditions and events
kubectl describe helmrelease cert-manager -n cert-manager

# Follow helm-controller logs for this release
flux logs --kind=HelmRelease --name=cert-manager --namespace=cert-manager

# Force reconciliation
flux reconcile helmrelease cert-manager -n cert-manager --with-source
```

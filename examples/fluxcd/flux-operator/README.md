# Flux Operator with FluxInstance

Status: Beta

Install and configure Flux CD using the Flux Operator and a `FluxInstance` CRD. The operator manages the full Flux lifecycle — installation, upgrades, and health reporting — without `flux bootstrap`.

## Why Flux Operator

| Concern | `flux bootstrap` | Flux Operator |
|---|---|---|
| Lifecycle management | Manual upgrades via CLI | Operator upgrades Flux automatically |
| Gitless delivery | Extra configuration | Native via `FluxInstance.spec.sync.kind: OCIRepository` |
| Health visibility | `flux check` command | `FluxReport` CRD — queryable as a resource |
| Multi-cluster fleet | Per-cluster bootstrap | Single operator image manages all clusters |

## Files

```text
flux-operator/
├── fluxinstance.yaml        # FluxInstance with gitless OCI sync
├── ocirepository.yaml       # Fleet manifests OCI source
└── verify-policy.yaml       # Cosign signature verification for OCI source
```

## Install the Flux Operator

```bash
helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace \
  --wait
```

## Apply FluxInstance

```bash
kubectl apply -f flux-operator/
```

## Key YAML

### FluxInstance (gitless OCI sync)

```yaml
apiVersion: fluxcd.controlplane.io/v1
kind: FluxInstance
metadata:
  name: flux          # must be named 'flux' — only one per cluster
  namespace: flux-system
  annotations:
    fluxcd.controlplane.io/reconcileEvery: "1h"
    fluxcd.controlplane.io/reconcileTimeout: "5m"
spec:
  distribution:
    version: "2.x"
    registry: "ghcr.io/fluxcd"
    artifact: "oci://ghcr.io/controlplaneio-fluxcd/flux-operator-manifests"
  components:
    - source-controller
    - kustomize-controller
    - helm-controller
    - notification-controller
    - image-reflector-controller
    - image-automation-controller
  cluster:
    type: kubernetes
    multitenant: false
    networkPolicy: true          # restricts controller inter-pod communication
    domain: "cluster.local"
  sync:
    kind: OCIRepository
    url: "oci://ghcr.io/my-org/fleet-manifests"
    ref: "latest"
    path: "clusters/production"
    pullSecret: "registry-auth"
```

### OCIRepository (fleet manifests source)

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: fleet-manifests
  namespace: flux-system
spec:
  interval: 5m
  url: oci://ghcr.io/my-org/fleet-manifests
  ref:
    tag: latest
  secretRef:
    name: registry-auth
  verify:
    provider: cosign              # verify Cosign signature on every pull
```

### Push fleet manifests from CI

```bash
# Build and push manifests OCI artifact (in CI pipeline)
flux push artifact oci://ghcr.io/my-org/fleet-manifests:latest \
  --path=./clusters/production \
  --source="$(git config --get remote.origin.url)" \
  --revision="$(git rev-parse HEAD)" \
  --creds="$GITHUB_ACTOR:$GITHUB_TOKEN"

# Sign with Cosign (keyless, Sigstore)
cosign sign --yes ghcr.io/my-org/fleet-manifests:latest
```

## Check health

```bash
# Check FluxInstance status
kubectl get fluxinstance flux -n flux-system -o yaml

# Check cluster-wide reconciliation health
kubectl get fluxreport flux -n flux-system -o yaml

# Check all controllers are running
kubectl get pods -n flux-system

# Check reconciliation of all resources
flux get all -A
```

## Migrate from flux bootstrap

If you have an existing `flux bootstrap` installation:

1. Install the Flux Operator alongside the existing install
2. Create `FluxInstance` with `spec.sync` pointing to your existing Git/OCI source
3. The operator will take over management of the existing controllers
4. Remove `gotk-sync.yaml` and `gotk-components.yaml` from your Git repo after verifying operator control

Full migration guide: https://fluxoperator.dev/docs/guides/migration/

## Troubleshooting

```bash
# FluxInstance not ready
kubectl describe fluxinstance flux -n flux-system

# Controller not starting
kubectl logs -n flux-system deploy/flux-operator | tail -50

# FluxReport showing degraded state
kubectl get fluxreport flux -n flux-system \
  -o jsonpath='{.status.conditions}' | python3 -m json.tool
```

# Basic Monorepo Structure

A simple GitOps repository structure using Kustomize overlays for environment differences.

Traffic enters through [Gateway API](https://gateway-api.sigs.k8s.io/) on [Envoy Gateway](https://gateway.envoyproxy.io/). This example used ingress-nginx until v1.43.0. That project's best-effort maintenance ended in March 2026, with no further releases or security fixes. To migrate an existing cluster, use `/platform-skills:gateway-api`.

## Prerequisites

- Flux v2.9 or later (`OCIRepository` v1, `HelmRelease` `chartRef`, `healthCheckExprs`)
- A LoadBalancer implementation (EKS, AKS and GKE have one; on kind or bare metal install MetalLB). Without it the Gateway never becomes `Programmed` and `infrastructure-configs` times out

## Structure

```
basic-monorepo/
├── clusters/
│   ├── production/
│   │   ├── flux-system/                 # Flux bootstrap
│   │   ├── gateway-crds.yaml            # Gateway API + Envoy Gateway CRDs (never pruned)
│   │   ├── infrastructure.yaml          # Controllers: Envoy Gateway, cert-manager
│   │   ├── infrastructure-configs.yaml  # Gateway, GatewayClass, ClusterIssuer
│   │   └── apps.yaml                    # Apps Kustomization
│   └── staging/
│       ├── flux-system/
│       ├── gateway-crds.yaml
│       ├── infrastructure.yaml
│       ├── infrastructure-configs.yaml
│       └── apps.yaml
├── infrastructure/
│   ├── base/                      # Shared controllers (install CRDs)
│   │   ├── kustomization.yaml
│   │   ├── envoy-gateway/
│   │   └── cert-manager/
│   ├── configs/                   # Objects that need those CRDs
│   │   ├── base/                  # App namespaces, GatewayClass, EnvoyProxy, Gateway, redirect, ClusterIssuer
│   │   ├── production/            # Production hostnames
│   │   └── staging/               # Staging hostnames, single proxy
│   ├── production/                # Production overrides
│   │   └── kustomization.yaml
│   └── staging/                   # Staging overrides
│       └── kustomization.yaml
└── apps/
    ├── base/                      # Base app definitions
    │   ├── kustomization.yaml
    │   └── my-app/
    ├── production/                # Production config
    │   └── kustomization.yaml
    └── staging/                   # Staging config
        └── kustomization.yaml
```

## Bootstrap

### 1. Fork and Clone

```bash
git clone https://github.com/YOUR_ORG/YOUR_REPO.git
cd YOUR_REPO
```

### 2. Bootstrap Production

```bash
flux bootstrap github \
  --owner=YOUR_ORG \
  --repository=YOUR_REPO \
  --branch=main \
  --path=clusters/production \
  --personal=false
```

### 3. Bootstrap Staging

```bash
flux bootstrap github \
  --owner=YOUR_ORG \
  --repository=YOUR_REPO \
  --branch=main \
  --path=clusters/staging \
  --personal=false
```

## How It Works

### Cluster Configuration

Each cluster defines what to reconcile:

```yaml
# clusters/production/infrastructure.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  interval: 10m
  path: ./infrastructure/production
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  wait: true
  timeout: 5m
```

### Layer Dependencies

The layers reconcile in order: `gateway-api-crds` and `envoy-gateway-crds` apply the CRDs. `infrastructure` installs the controllers (Envoy Gateway, cert-manager; cert-manager must start after the Gateway API CRDs exist). `infrastructure-configs` creates the app namespaces and the Gateway API and cert-manager objects that need those CRDs. `apps` attaches routes to the Gateway.

Splitting controllers from configs is required, not cosmetic. Flux dry-runs a Kustomization before applying it, and a `Gateway` cannot be dry-run until the Gateway API CRDs exist.

Apps depend on the configs layer:

```yaml
# clusters/production/apps.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  dependsOn:
    - name: infrastructure-configs
  interval: 5m
  path: ./apps/production
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
```

### Environment Overlays

Staging references base with patches:

```yaml
# infrastructure/staging/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
patches:
  - target:
      kind: HelmRelease
      name: envoy-gateway
    patch: |-
      - op: replace
        path: /spec/values/deployment/replicas
        value: 1  # Staging uses fewer replicas
```

Production references base without changes or with production-specific patches:

```yaml
# infrastructure/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
patches:
  - target:
      kind: HelmRelease
      name: cert-manager
    patch: |-
      - op: replace
        path: /spec/values/replicaCount
        value: 3  # Production uses more replicas
```

### Ingress with Gateway API

Ownership is split the way Gateway API intends:

| Object | Owner | Namespace |
|---|---|---|
| `GatewayClass` `envoy-gateway`, `EnvoyProxy` `platform-proxy` | Platform team | cluster / `envoy-gateway-system` |
| `Gateway` `platform-gateway`, listeners, TLS certificates | Platform team | `envoy-gateway-system` |
| `HTTPRoute` per app | App team | the app's namespace |

- **TLS:** the Gateway carries `cert-manager.io/cluster-issuer: letsencrypt-prod`. cert-manager creates one Certificate per HTTPS listener and solves HTTP-01 through the same Gateway.
- **Access:** the HTTPS listener only accepts routes from namespaces labelled `gateway-access: "true"`. A route from any other namespace is rejected with `NotAllowedByListeners`. App namespaces are created in `infrastructure/configs/base/app-namespaces.yaml`, not under `apps/`, so an app team cannot grant itself the label. Protect that path with CODEOWNERS.
- **Redirect:** a platform-owned `HTTPRoute` on port 80 sends everything to HTTPS with a 308, the same code ingress-nginx used. ACME challenge routes use an `Exact` path match, which takes precedence over it.
- **CRDs:** `clusters/<env>/gateway-crds.yaml` applies the Gateway API **standard**-channel CRDs and the Envoy Gateway CRDs as plain manifests through two Flux Kustomizations. Not a HelmRelease: the CRDs are multi-megabyte and a Helm release Secret is capped at 1 MiB. Both use `prune: false` and `deletionPolicy: Orphan`, because deleting a CRD deletes every Gateway and HTTPRoute in the cluster.
- **Availability:** `EnvoyProxy` runs two proxy replicas with a PodDisruptionBudget in production. Staging runs one and removes the PDB, because `minAvailable: 1` on a single replica blocks every node drain.


## Key Patterns

### 1. Separate Concerns

- **clusters/**: What each cluster reconciles
- **infrastructure/**: Shared platform components
- **apps/**: Application workloads

### 2. Use Dependencies

Infrastructure must be ready before apps:

```yaml
spec:
  dependsOn:
    - name: infrastructure
```

### 3. Wait for Readiness

Block until resources are healthy:

```yaml
spec:
  wait: true
  timeout: 5m
```

### 4. Minimal Overlays

Keep environment differences small. Most configuration should be in base.

## Adding New Applications

A new app needs a platform-team change first: add its Namespace to `infrastructure/configs/base/app-namespaces.yaml`, with `gateway-access: "true"` if it serves public traffic. A new **public hostname** also needs an HTTPS listener in `infrastructure/configs/base/gateway.yaml`, patched per environment; cert-manager requires one listener per hostname.

1. **Create base definition:**

```bash
mkdir -p apps/base/new-app
cat <<EOF > apps/base/new-app/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: new-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: new-app
  template:
    metadata:
      labels:
        app: new-app
    spec:
      containers:
      - name: app
        image: nginx:1.25.0
        ports:
        - containerPort: 80
EOF
```

2. **Add to base kustomization:**

```bash
cat <<EOF >> apps/base/kustomization.yaml
resources:
  - new-app/
EOF
```

3. **Add environment-specific values if needed:**

```yaml
# apps/production/kustomization.yaml
resources:
  - ../base
patches:
  - target:
      kind: Deployment
      name: new-app
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 5  # More replicas in production
```

4. **Commit and push:**

```bash
git add apps/
git commit -m "Add new-app deployment"
git push
```

5. **Wait for reconciliation:**

```bash
flux reconcile kustomization apps --with-source
kubectl get deployment new-app -w
```

## Troubleshooting

### Check Reconciliation Status

```bash
flux get kustomizations -A
```

### View Logs

```bash
flux logs --kind=kustomize-controller --since=10m
```

### Force Sync

```bash
flux reconcile kustomization apps --with-source
```

### Route Not Serving Traffic

```bash
# Is the Gateway Programmed (has an address)?
kubectl get gateway platform-gateway -n envoy-gateway-system
# Did the route attach? Look for Accepted=True and ResolvedRefs=True per parent
kubectl get httproute my-app -n my-app -o jsonpath='{range .status.parents[*]}{.parentRef.sectionName}{": "}{range .conditions[*]}{.type}={.status} ({.reason}) {end}{"\n"}{end}'
# Was the certificate issued?
kubectl get certificate -n envoy-gateway-system
```

| Condition | Meaning | Fix |
|---|---|---|
| `Accepted=False`, `NotAllowedByListeners` | Namespace lacks `gateway-access: "true"` or the `sectionName` is wrong | Label the namespace or fix `sectionName` |
| `ResolvedRefs=False`, `BackendNotFound` | Service name or port in `backendRefs` is wrong | Match the Service name and port number |
| Gateway `Programmed=False`, `AddressNotAssigned` | No LoadBalancer implementation | Install one, or use a NodePort `EnvoyProxy` for local clusters |
| No Certificate | cert-manager started before the Gateway API CRDs existed | `kubectl rollout restart deployment cert-manager -n cert-manager` |

### Validate Locally

```bash
kubectl kustomize apps/production
# Full check: every overlay builds and passes kubeconform against CRD schemas
bash examples/gateway-api/gateway-api-validate.sh
```

## Advantages

- ✅ Simple structure, easy to understand
- ✅ All environments in one repository
- ✅ Clear environment boundaries
- ✅ Minimal overlay complexity

## Limitations

- ❌ All teams share one repository (RBAC harder)
- ❌ Single team's changes can affect others
- ❌ Harder to scale to many independent teams

## When to Use

- Single platform team managing all environments
- Consistent app portfolio across environments
- Simple RBAC requirements
- Small to medium scale deployments

## Next Steps

- Add Helm release patterns for third-party apps
- Add image automation patterns for updates
- Consider a multi-tenant split when teams need stronger repo boundaries

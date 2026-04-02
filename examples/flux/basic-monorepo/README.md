# Basic Monorepo Structure

A simple GitOps repository structure using Kustomize overlays for environment differences.

## Structure

```
basic-monorepo/
├── clusters/
│   ├── production/
│   │   ├── flux-system/           # Flux bootstrap
│   │   ├── infrastructure.yaml    # Infrastructure Kustomization
│   │   └── apps.yaml              # Apps Kustomization
│   └── staging/
│       ├── flux-system/
│       ├── infrastructure.yaml
│       └── apps.yaml
├── infrastructure/
│   ├── base/                      # Shared infrastructure
│   │   ├── kustomization.yaml
│   │   ├── ingress-nginx/
│   │   └── cert-manager/
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

Apps depend on infrastructure:

```yaml
# clusters/production/apps.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  dependsOn:
    - name: infrastructure
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
      kind: Deployment
      name: ingress-nginx-controller
    patch: |-
      - op: replace
        path: /spec/replicas
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
      kind: Deployment
      name: ingress-nginx-controller
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 3  # Production uses more replicas
```

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

### Validate Locally

```bash
kustomize build apps/production
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

- Add [Helm releases](../helm-releases/) for third-party apps
- Implement [image automation](../image-automation/) for updates
- Consider [multi-tenant](../multi-tenant/) for team separation

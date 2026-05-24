# Multi-Tenant Flux Repository

Status: Beta

A GitOps repository pattern for multiple teams sharing a single cluster, with RBAC and network isolation per tenant.

## Pattern

Each tenant gets:
- A dedicated namespace
- A ServiceAccount scoped to that namespace
- A Kustomization running as that ServiceAccount (limits blast radius)
- NetworkPolicy default-deny + allow-same-namespace

The platform team owns the cluster bootstrap and tenant onboarding. Tenant teams push to their own source repositories.

## Directory structure

```text
multi-tenant/
├── clusters/
│   └── production/
│       ├── platform.yaml        # Kustomization for ClusterRole + NetworkPolicy
│       └── tenants.yaml         # Kustomization pointing to tenants/ (dependsOn: platform)
├── tenants/
│   └── team-a/
│       ├── namespace.yaml
│       ├── serviceaccount.yaml  # Created in flux-system namespace
│       ├── rolebinding.yaml
│       ├── gitrepository.yaml
│       └── kustomization.yaml
└── platform/
    ├── kustomization.yaml       # Kustomize config listing rbac + network-policy
    ├── rbac/
    │   └── tenant-role.yaml     # ClusterRole with namespace-scoped permissions
    └── network-policy/
        └── default-deny.yaml    # Default-deny + allow-same-namespace per tenant
```

## Key patterns

### Tenant isolation via serviceAccountName

```yaml
# tenants/team-a/kustomization.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: team-a
  namespace: flux-system
spec:
  interval: 10m
  prune: true
  wait: true
  timeout: 5m
  serviceAccountName: team-a          # runs as team-a SA — limits to team-a namespace
  sourceRef:
    kind: GitRepository
    name: team-a-app
  path: ./deploy
```

### No cross-namespace references

Tenant Kustomizations must not reference resources in other tenant namespaces. Use `spec.targetNamespace` to enforce.

### Tenant onboarding

To add a new tenant, copy `tenants/team-a/` to `tenants/<new-team>/`, update namespace and names, and commit. Flux will create the namespace, RBAC, and source reconciliation automatically.

## Prerequisites

- Flux CD 2.x or Flux Operator with FluxInstance
- `flux` CLI installed
- `kubectl` with cluster-admin access for initial setup

## Bootstrap

```bash
# Bootstrap Flux (or apply FluxInstance if using Flux Operator)
flux bootstrap github \
  --owner=my-org \
  --repository=platform-gitops \
  --branch=main \
  --path=./clusters/production

# Verify tenants are reconciling
flux get kustomizations -n flux-system | grep team-
```

## Troubleshooting

```bash
# Check a tenant's Kustomization status
flux get kustomization team-a -n flux-system

# Check RBAC — is the ServiceAccount missing permissions?
# SA is in flux-system namespace, not the tenant namespace
kubectl auth can-i create deployments \
  --as=system:serviceaccount:flux-system:team-a -n team-a

# Check NetworkPolicy is not blocking cross-namespace traffic unexpectedly
kubectl describe networkpolicy -n team-a
```

# Flux CD Examples

This directory contains reference implementations for Flux CD GitOps patterns.

Status: Stable

## Examples

| Example | Pattern | Status |
|---|---|---|
| [basic-monorepo/](basic-monorepo/) | Single team, Kustomize overlays per environment | Stable |
| [multi-tenant/](multi-tenant/) | Multiple teams sharing a cluster, RBAC isolation per tenant | Beta |
| [helm-releases/](helm-releases/) | Helm chart management via OCIRepository, environment value overlays | Beta |
| [image-automation/](image-automation/) | Automated image tag updates — Git-based and gitless (OCIArtifactTag) side-by-side | Beta |
| [flux-operator/](flux-operator/) | Flux Operator + FluxInstance + gitless OCI sync + Cosign verification | Beta |

## Choosing the right pattern

| Need | Example |
|---|---|
| Single team, simple environment promotion | `basic-monorepo/` |
| Multiple teams on one cluster, isolated blast radius | `multi-tenant/` |
| Third-party Helm charts with environment value overrides | `helm-releases/` |
| Automate image tag updates from CI to cluster | `image-automation/` |
| Manage Flux itself via Kubernetes CRD, no bootstrap script | `flux-operator/` |
| Gitless delivery — no Git credentials on clusters | `flux-operator/` + `image-automation/gitless/` |

## Prerequisites

- Kubernetes 1.28+
- Flux CLI 2.2+ (`brew install fluxcd/tap/flux`)
- `kubectl` with cluster access
- Flux Operator examples additionally require: `helm` CLI

## Common commands

```bash
# Check all Flux resources across namespaces
flux get all -A

# Force immediate reconciliation of a Kustomization
flux reconcile kustomization <name> --with-source

# Suspend and resume reconciliation
flux suspend kustomization <name>
flux resume kustomization <name>

# Stream controller logs for a specific resource
flux logs --kind=HelmRelease --name=<name> --namespace=<namespace>

# Check cluster-wide health (Flux Operator only)
kubectl get fluxreport flux -n flux-system -o yaml
```

## Shared best practices

All examples follow these conventions:

| Practice | Why |
|---|---|
| `spec.prune: true` on all Kustomizations | Removes orphaned resources when files are deleted from Git |
| `spec.wait: true` with `timeout` | Blocks dependent resources until health checks pass |
| `dependsOn` for ordered apply | infrastructure must be ready before apps |
| `spec.chartRef` (OCI) over `spec.chart.spec` (HTTPS) | OCI charts are immutable and signable |
| `install.strategy.name: RetryOnFailure` | Modern remediation API |
| `reconcile.fluxcd.io/watch: Enabled` on `valuesFrom` ConfigMaps | Immediate HelmRelease reconciliation when values change |
| Workload Identity over static credentials | No long-lived tokens on clusters |
| SOPS or External Secrets for secrets | No plain secrets in Git |

## Troubleshooting

See [references/fluxcd.md](../../references/fluxcd.md) for the full CRD reference table, source selection decision matrix, Flux Operator patterns, ResourceSet patterns, common mistakes, and image automation models.

For live cluster debugging use `/platform-skills:gitops`. For repo auditing use `/platform-skills:gitops-audit`.

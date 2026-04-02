# Flux CD Examples

This directory contains reference implementations for Flux CD GitOps patterns.

Status: `basic-monorepo/` is runnable today. The other patterns below are handbook roadmap items, not committed example directories yet.

## Examples

### 1. Basic Monorepo Structure

[basic-monorepo/](basic-monorepo/) - Simple monorepo with environment overlays

**Use case:** Single team, multiple environments  
**Pattern:** Kustomize overlays for environment differences  
**Components:**
- Cluster bootstrap configuration
- Infrastructure layer (ingress, cert-manager)
- Application layer with environment overlays

### 2. Multi-Tenant Repository

Planned handbook pattern: separate tenant repositories with central platform

**Use case:** Multiple teams with independent release cycles  
**Pattern:** Platform repo references tenant repos  
**Components:**
- Platform repository with tenant configurations
- Example tenant repository structure
- RBAC boundaries per tenant

### 3. Helm Release Management

Planned handbook pattern: HelmRelease value hierarchy and chart management

**Use case:** Managing third-party Helm charts  
**Pattern:** Base values with environment-specific overrides  
**Components:**
- HelmRepository definitions
- HelmRelease with value composition
- Secret management integration

### 4. Image Automation

Planned handbook pattern: automated image updates with policies

**Use case:** Auto-update container images on new versions  
**Pattern:** ImageRepository + ImagePolicy + ImageUpdateAutomation  
**Components:**
- Image repository scanning
- Semver policy configuration
- Git commit automation setup

## Quick Start

The runnable example currently included is:
- `basic-monorepo/` - setup instructions plus Flux and Kustomize manifests

## Prerequisites

- Kubernetes cluster (1.28+)
- Flux CLI (2.2+)
- kubectl configured for cluster access
- Git repository for GitOps

## Common Commands

```bash
# Check all sources
flux get sources all -A

# Check reconciliation status
flux get kustomizations -A
flux get helmreleases -A

# Force reconciliation
flux reconcile kustomization apps --with-source

# Suspend during maintenance
flux suspend kustomization apps
flux resume kustomization apps

# View logs
flux logs --kind=kustomize-controller --since=10m
flux logs --kind=helm-controller --since=10m
```

## Troubleshooting

See [references/flux.md](../../references/flux.md) for detailed troubleshooting patterns.

Common issues:
- **Source not updating**: Check GitRepository credentials and network access
- **Reconciliation failing**: Check RBAC permissions and resource conflicts
- **Helm chart errors**: Validate values against chart schema
- **Runtime issues**: Not a Flux problem - check pod logs and events

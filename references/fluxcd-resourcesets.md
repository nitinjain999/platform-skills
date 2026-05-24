# FluxCD ResourceSet Reference

`ResourceSet` (`fluxcd.controlplane.io/v1`) generates Kubernetes resources from input value matrices using templates. It powers multi-tenant orchestration, fleet management, and self-service platform patterns that would otherwise require N copies of the same manifest.

---

## Core concept

A ResourceSet takes one or more sets of inputs and renders a template block once per input entry. The result is a set of Kubernetes resources owned and reconciled by the Flux Operator.

```yaml
apiVersion: fluxcd.controlplane.io/v1
kind: ResourceSet
metadata:
  name: tenant-apps
  namespace: flux-system
spec:
  inputsFrom:
    - kind: ResourceSetInputProvider
      name: tenant-list
  resources:
    - apiVersion: kustomize.toolkit.fluxcd.io/v1
      kind: Kustomization
      metadata:
        name: << inputs.tenant >>-apps
        namespace: flux-system
      spec:
        interval: 10m
        prune: true
        sourceRef:
          kind: OCIRepository
          name: << inputs.tenant >>-manifests
        path: ./apps
        serviceAccountName: << inputs.tenant >>
```

**Template delimiters are `<< >>` — not `{{ }}`.**

---

## Template functions

Templates use slim-sprig (Go sprig subset):

```
<< inputs.tenant >>                          # simple substitution
<< inputs.tag | default "latest" >>          # default value
<< inputs.config | toYaml | nindent 4 >>     # serialize nested object
<< if eq inputs.env "prod" >>3<< else >>1<< end >>  # conditional
```

---

## Input strategies

| Strategy | Behaviour |
|---|---|
| `Flatten` (default) | Concatenates all inputs into a flat list |
| `Permute` | Cartesian product of all provider outputs |

Under `Permute`, field names are namespaced under the normalized provider name. A provider named `image-tag` is accessed as `inputs.image_tag.tag`. Inline inputs on a ResourceSet named `my-apps` require `inputs.my_apps.region`, not `inputs.region`.

> Always set `filter.limit: 1` on OCIArtifactTag providers used with `Permute` — multiple exports per provider create a cross-product explosion (operator stalls at 10,000 permutations).

---

## ResourceSetInputProvider types

```yaml
apiVersion: fluxcd.controlplane.io/v1
kind: ResourceSetInputProvider
metadata:
  name: tenant-list
  namespace: flux-system
spec:
  type: Static           # Static | OCIArtifactTag | ECRArtifactTag | GitHubTag | GitHubPullRequest | GitLabTag | AzureContainerTag | ExternalService
  defaultValues:
    region: eu-west-1
```

| Type | Exported fields | Use case |
|---|---|---|
| `Static` | From `defaultValues` | Fixed config, shared cluster variables |
| `OCIArtifactTag` | `id`, `tag`, `digest` | Gitless image automation |
| `ECRArtifactTag` | `id`, `tag`, `digest` | ECR-native gitless automation |
| `GitHubTag` | `id`, `tag`, `sha` | Fleet release tracking |
| `GitHubPullRequest` | `id`, `sha`, `branch`, `author`, `title` | Preview environments per PR |
| `GitLabTag` | `id`, `tag`, `sha` | GitLab fleet release tracking |
| `AzureContainerTag` | `id`, `tag`, `digest` | ACR gitless automation |
| `ExternalService` | From HTTP JSON response | Custom registry / inventory API |

**Key spec fields:**

| Field | Purpose |
|---|---|
| `type` | Provider type (required) |
| `url` | Registry or repo URL |
| `secretRef.name` | Credentials secret |
| `filter.limit` | Max inputs returned (default: 100) |
| `filter.semver` | Semver range to filter/sort tags |
| `defaultValues` | Merged defaults added to every exported entry |
| `schedule` | Cron expression for reconciliation windows |

Reconciliation interval is controlled via annotation, not spec:

```yaml
annotations:
  fluxcd.controlplane.io/reconcileEvery: "5m"
```

---

## Dependencies

ResourceSets support CEL-based readiness expressions:

```yaml
spec:
  dependsOn:
    - kind: Kustomization
      name: platform-rbac
      namespace: flux-system
      readyExpr: >
        status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'True')
    - kind: Kustomization
      name: cert-manager
      namespace: flux-system
      readyExpr: "status.observedGeneration >= 0"   # reconciled-once check
```

---

## Advanced patterns

### Conditional resource inclusion

```yaml
resources:
  - apiVersion: v1
    kind: Namespace
    metadata:
      name: << inputs.tenant >>
      annotations:
        fluxcd.controlplane.io/reconcile: << if eq inputs.active "true" >>enabled<< else >>disabled<< end >>
```

When the annotation value is `disabled`, that resource is excluded for that input entry.

### copyFrom

Copies ConfigMaps or Secrets from another namespace and keeps them in sync. Required for distributing shared config across tenant namespaces:

```yaml
spec:
  resources:
    - apiVersion: v1
      kind: ConfigMap
      metadata:
        name: cluster-config
        namespace: << inputs.tenant >>
        annotations:
          fluxcd.controlplane.io/copyFrom: flux-system/cluster-config
```

For Secrets, the `type` field must also be set in the template.

### Built-in input fields

| Field | Description |
|---|---|
| `inputs._index` | Zero-based index of current input |
| `inputs._id` | Adler-32 checksum of input values — stable unique ID |
| `inputs.provider.kind` | `ResourceSet` or `ResourceSetInputProvider` |
| `inputs.provider.name` | Name of the providing object |

### Deduplication

When multiple inputs produce resources with identical GVK + namespace + name, the last input wins.

---

## Common patterns

### Gitless multi-tenant fleet

Chain of ResourceSets with `dependsOn`: **policies → infra → apps**. Each tenant gets a Namespace, OCIRepository, Kustomization, RBAC, and registry credentials — all from a single ResourceSet template.

### Preview environments

A `GitHubPullRequest` provider with label filter feeds a ResourceSet that spins up per-PR namespaces and deployments. Cleaned up automatically when the PR closes.

### Gitless image automation

`OCIArtifactTag` provider + `Permute` strategy pins HelmRelease resources to `tag@digest` without Git commits. Set `limit: 1` per provider.

```yaml
apiVersion: fluxcd.controlplane.io/v1
kind: ResourceSetInputProvider
metadata:
  name: app-image
  namespace: flux-system
  annotations:
    fluxcd.controlplane.io/reconcileEvery: "2m"
spec:
  type: OCIArtifactTag
  url: ghcr.io/my-org/my-app
  secretRef:
    name: registry-auth
  filter:
    limit: 1
    semver: ">=1.0.0"
---
apiVersion: fluxcd.controlplane.io/v1
kind: ResourceSet
metadata:
  name: app-release
  namespace: flux-system
spec:
  inputsFrom:
    - kind: ResourceSetInputProvider
      name: app-image
  resources:
    - apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      metadata:
        name: my-app
        namespace: apps
      spec:
        interval: 10m
        chartRef:
          kind: OCIRepository
          name: my-app-chart
        values:
          image:
            tag: "<< inputs.tag >>@<< inputs.digest >>"
```

---

## Validation

```bash
# List all ResourceSets
kubectl get resourceset -A

# Inspect inputs and generated resources
kubectl describe resourceset <name> -n flux-system

# List resources generated by a specific ResourceSet
kubectl get kustomization,helmrelease -l resourceset.fluxcd.io/name=<name> -A

# Force immediate reconciliation
kubectl annotate resourceset <name> -n flux-system \
  fluxcd.controlplane.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite
```

# Argo CD Examples

This directory contains reference patterns for Argo CD application delivery and GitOps repository design.

Status: runnable app-of-apps example plus additional handbook-style reference patterns.

## Prerequisites

Before deploying the app-of-apps example, create the required AppProject:

```bash
kubectl apply -f projects/platform-project.yaml
```

This creates the `platform` AppProject that constrains source repositories, destination namespaces, and permissions for all applications in this example.

See [projects/platform-project.yaml](projects/platform-project.yaml) for the complete project definition.

## Example Areas

### 1. App of Apps

See [app-of-apps/application.yaml](app-of-apps/application.yaml) for a root application that manages child Argo CD `Application` resources declaratively.
The child applications live under `app-of-apps/applications/` and separate production infrastructure from production workloads.

**Usage:**
```bash
# Apply the root application (after creating the platform AppProject above)
kubectl apply -f app-of-apps/application.yaml
```

### 2. Project Boundary

Use `AppProject` to constrain source repositories, namespaces, and clusters:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: payments
  namespace: argocd
spec:
  sourceRepos:
    - https://github.com/nitinjain999/platform-skills
  destinations:
    - namespace: payments
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
```

### 3. ApplicationSet Fleet Pattern

Use `ApplicationSet` for repeated cluster onboarding:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: platform-addons
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: staging
            namespace: platform-system
          - cluster: production
            namespace: platform-system
  template:
    metadata:
      name: '{{cluster}}-platform-addons'
    spec:
      project: platform
      source:
        repoURL: https://github.com/nitinjain999/platform-skills
        targetRevision: main
        path: examples/flux/basic-monorepo/infrastructure/production
      destination:
        name: '{{cluster}}'
        namespace: '{{namespace}}'
```

## Operational Checklist

- AppProject boundaries defined before tenant onboarding
- Sync and prune settings reviewed for blast radius
- ApplicationSet used for repeated cluster patterns
- Manual cluster drift corrected through Git, not ad hoc kubectl changes

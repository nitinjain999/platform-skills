# Argo CD Examples

This directory contains reference patterns for Argo CD application delivery and GitOps repository design.

## Example Areas

### 1. App of Apps

See [app-of-apps/application.yaml](app-of-apps/application.yaml) for a root application that manages other Argo CD applications declaratively.

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

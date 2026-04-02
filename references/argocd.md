# Argo CD Reference

## Contents

- Scope
- Repository patterns
- Reconciliation model
- Promotion model
- Safety rules

## Scope

Use Argo CD for:

- Declarative application deployment to Kubernetes clusters
- Multi-cluster fleet management with projects and app boundaries
- App-of-apps or application set patterns
- Helm, Kustomize, and directory-based Git reconciliation

Argo CD fills the same last-mile delivery role as Flux in many platforms. Choose one reconciler per boundary unless there is a deliberate transition plan.

## Repository patterns

Common layout:

```text
argocd/
  projects/
  applications/
clusters/
  prod/
  staging/
apps/
  base/
  overlays/
```

- `projects/` defines policy boundaries and allowed source/destination combinations.
- `applications/` defines app-of-apps roots or cluster application entrypoints.
- `apps/` contains reusable manifests or Helm/Kustomize content.

## Reconciliation model

- Keep Argo CD applications small, named clearly, and scoped intentionally.
- Use `Project` boundaries to control sources, destinations, and cluster access.
- Prefer `ApplicationSet` for repeated cluster or tenant patterns instead of manual duplication.
- Use sync waves, health checks, and sync options deliberately.

## Promotion model

- Promote by version pins, overlay changes, or application set inputs in Git.
- Keep environment-specific divergence minimal.
- Separate platform app promotion from workload version promotion when teams differ.

## Safety rules

- Do not let teams bypass Git with manual cluster edits and still call the result managed.
- Keep automated prune and self-heal settings aligned to the platform’s risk tolerance.
- Avoid running Argo CD and Flux over the same resources without strict ownership boundaries.
- Treat bootstrap, secrets, and cloud identity as upstream dependencies owned outside the app reconciler unless explicitly designed otherwise.

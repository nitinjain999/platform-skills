# Flux Reference

## Contents

- Scope
- Repository patterns
- Reconciliation model
- Promotion model
- Safety rules

## Scope

Use Flux for:

- Cluster add-ons
- Application delivery
- Helm release management
- Kustomize overlays per cluster or environment

Flux should consume a prepared cluster. Bootstrap the cluster and its cloud prerequisites with Terraform unless there is a strong reason to use another control plane.

## Repository patterns

Common layout:

```text
clusters/
  prod/
  staging/
apps/
  base/
  overlays/
infrastructure/
  controllers/
  add-ons/
```

- `clusters/` defines what each cluster reconciles.
- `apps/` defines application or service workloads.
- `infrastructure/` contains in-cluster platform components such as ingress, cert-manager, external-dns, or observability stacks.

## Reconciliation model

- Keep reconciliation pull-based from Git.
- Pin chart and image versions intentionally.
- Prefer small, well-named `Kustomization` boundaries with clear dependencies.
- Use `dependsOn`, health checks, and intervals deliberately rather than a single large root object.

## Promotion model

- Promote by changing image tags, chart versions, or overlay refs in Git.
- Keep environment overlays minimal; shared defaults belong in base definitions.
- For multi-cluster fleets, separate cluster-specific settings from app version promotion.

## Safety rules

- Do not patch resources manually in-cluster and call that the deployed state.
- Keep secrets out of plain Git unless encrypted and operationally justified.
- Ensure controllers that need cloud access use workload identity rather than static keys where possible.
- Treat Flux as the last-mile reconciler, not as the place to invent environment-specific business logic.

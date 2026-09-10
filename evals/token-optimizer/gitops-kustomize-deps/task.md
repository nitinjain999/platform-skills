# Task: Map Flux Kustomization dependency order

The `basic-monorepo/` directory contains Flux CD Kustomization manifests for infrastructure and apps across staging and production.

Map the dependency order:
- Which Kustomizations depend on which others (via `dependsOn`)
- The reconciliation order for staging
- The reconciliation order for production
- Any circular dependencies or missing dependencies

Report complete, partial, or blocked.

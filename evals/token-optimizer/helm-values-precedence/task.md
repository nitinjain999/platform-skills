# Task: Trace Helm values through environment overlays

The `helm/` directory contains a Helm chart, and `helm-releases/` contains FluxCD HelmRelease manifests for staging and production environments.

Trace how values are merged across:
- Chart default values
- Base HelmRelease values
- Environment-specific overlays

For the `replicaCount` and `image.tag` settings, report:
- The default value from the chart
- The value in staging
- The value in production
- How environment overlays merge or override

Report complete, partial, or blocked.

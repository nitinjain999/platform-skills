# Helm Examples

Production-ready Helm chart patterns. Copy, adapt, and lint before deploying.

Status: Stable

Committed chart templates for the handbook. Adapt them into your own repo — do not copy blindly into production without reviewing values, image references, and namespace strategy.

## Charts

| Directory | Workload | What it demonstrates |
|-----------|----------|----------------------|
| [web-service/](web-service/) | Deployment + Service + optional Ingress | Full production chart: hardened security context, HPA, PDB, NetworkPolicy, schema validation, helm tests |

## Validation

Run this pipeline against any chart before deploying:

```bash
# 1. Strict lint — fail on warnings
helm lint web-service/ --strict

# 2. Render and inspect
helm template my-release web-service/ --debug

# 3. Validate rendered manifests against K8s schemas
helm template my-release web-service/ | kubeconform -strict -summary

# 4. Security scan on rendered output
helm template my-release web-service/ | checkov -d - --framework kubernetes

# 5. Install and run in-cluster tests
helm install my-release web-service/ -n payments --create-namespace
helm test my-release -n payments
```

## Checklist

- `apiVersion: v2` in Chart.yaml (Helm 3 only)
- `_helpers.tpl` defines `labels`, `selectorLabels`, `fullname`, `serviceAccountName`
- `selectorLabels` does **not** include `app.kubernetes.io/version` (immutable after creation)
- Image tag defaults to `.Chart.AppVersion` — no hardcoded tags in templates
- `automountServiceAccountToken: false` on ServiceAccount and pod spec
- `readOnlyRootFilesystem: true` with `emptyDir` mounted at `/tmp`
- `capabilities.drop: [ALL]` on every container
- `seccompProfile.type: RuntimeDefault` on pod security context
- Resource requests and limits set on every container
- Liveness and readiness probes defined
- PDB enabled for `replicaCount >= 2`
- NetworkPolicy: default-deny + explicit allow from ingress controller
- `values.schema.json` enforces types on critical values
- `helm lint --strict` passes with zero warnings

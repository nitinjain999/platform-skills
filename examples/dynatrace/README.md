Status: Stable

# Dynatrace Examples

Production-ready Dynatrace OneAgent deployment on Kubernetes via the Dynatrace Operator.

## Examples

| Example | Type | Description |
|---------|------|-------------|
| [operator/dynakube.yaml](operator/) | Kubernetes | DynaKube CR — cloudNativeFullStack injection with ActiveGate |

## Quick Start

```bash
# 1. Install the Dynatrace Operator
kubectl create namespace dynatrace
kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/latest/download/kubernetes.yaml

# 2. Create the API token secret (never use plain values)
kubectl -n dynatrace create secret generic dynakube \
  --from-literal=apiToken="${DT_API_TOKEN}" \
  --from-literal=dataIngestToken="${DT_DATA_INGEST_TOKEN}"

# 3. Edit operator/dynakube.yaml — replace ENVIRONMENT_ID with your Dynatrace environment ID
#    apiUrl: "https://ENVIRONMENT_ID.live.dynatrace.com/api"

# 4. Apply the DynaKube CR
kubectl apply -f operator/dynakube.yaml

# 5. Verify deployment
kubectl -n dynatrace get dynakube dynakube
kubectl -n dynatrace get pods
```

## What dynakube.yaml Provides

| Feature | Setting | Effect |
|---------|---------|--------|
| `cloudNativeFullStack` | Enabled | Automatic OneAgent injection — no pod restarts required |
| Control-plane tolerations | `node-role.kubernetes.io/control-plane` | OneAgent runs on control-plane nodes |
| ActiveGate | 2 replicas | High-availability routing, Kubernetes monitoring, API gateway |
| `metadataEnrichment` | Enabled | All telemetry enriched with k8s namespace, pod, node labels |

## URL Conventions

| Use case | URL format | Example |
|----------|-----------|---------|
| `DynaKube.spec.apiUrl` (Operator) | `live.dynatrace.com` | `https://abc12345.live.dynatrace.com/api` |
| `DT_ENVIRONMENT` (MCP server) | `apps.dynatrace.com` | `https://abc12345.apps.dynatrace.com` |

These are different URLs — the Operator uses the classic API URL; the MCP server requires the Platform URL.

## Required Token Scopes

| Token | Required scopes |
|-------|----------------|
| `apiToken` | `ReadConfig`, `WriteConfig`, `DataExport`, `LogExport`, `ReadSyntheticData`, `WriteAnomalyDetection` |
| `dataIngestToken` | `metrics.ingest`, `logs.ingest` |

Store both tokens in a Kubernetes Secret — never in plain Helm values or committed files.

## Verify Injection

```bash
# OneAgent should appear as an init container in application pods
kubectl describe pod <app-pod> -n <app-namespace> | grep -A5 "Init Containers"

# Check OneAgent status
kubectl -n dynatrace get oneagent
```

## Checklist

- [ ] `ENVIRONMENT_ID` replaced with real environment ID in `apiUrl`
- [ ] API token secret created before applying DynaKube CR
- [ ] Both token scopes verified in Dynatrace UI before deployment
- [ ] `cloudNativeFullStack` chosen over `fullStack` for zero-restart injection
- [ ] `metadataEnrichment: true` — enriches all signals with k8s metadata
- [ ] ActiveGate replicas ≥ 2 for high availability

## See Also

- [references/dynatrace.md](../../references/dynatrace.md) — Operator setup, code-level instrumentation, custom metrics, SLOs, Terraform provider, Davis AI
- `/platform-skills:dynatrace` — setup, instrument, monitor, SLO, dashboard, investigate incidents

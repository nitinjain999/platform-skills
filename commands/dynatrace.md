---
name: dynatrace
description: Deploy and configure Dynatrace — OneAgent Kubernetes Operator, code-level instrumentation, Log Monitoring, custom metrics, SLOs, Dashboards, anomaly detection, and Davis AI problem feeds. Covers Terraform-managed Dynatrace resources.
argument-hint: "[setup|instrument|monitor|slo|dashboard|debug] [service or description]"
---

Configure or troubleshoot Dynatrace observability for a service or platform.

## Mode: setup

Deploy the Dynatrace Operator and OneAgent on Kubernetes.

Steps:
1. Ask for: environment ID, Kubernetes distribution (EKS/AKS/GKE), monitoring mode (fullStack / cloudNativeFullStack)
2. Install Operator: `kubectl apply -f .../dynatrace-operator/releases/latest/download/kubernetes.yaml`
3. Create Secret with `apiToken` and `dataIngestToken` (store in Kubernetes Secret or secrets manager — never plain values)
4. Generate `DynaKube` CR with `cloudNativeFullStack` for automatic injection — no pod restarts required
5. Enable `metadataEnrichment: true` for Kubernetes metadata on all telemetry
6. Verify injection: `kubectl describe pod <app-pod> | grep dynatrace`

Required token scopes:
- `apiToken`: `ReadConfig WriteConfig DataExport LogExport`
- `dataIngestToken`: `metrics.ingest logs.ingest`

Reference: `references/dynatrace.md` → Deployment, Token Scopes

## Mode: instrument

Add custom spans or business transaction tracing to a service.

Steps:
1. OneAgent auto-instruments HTTP, database, cache, and messaging — code changes only needed for custom business spans
2. Ask for: language (Node.js / Python / Java), business operations to trace (payment, checkout, data pipeline)
3. Generate SDK code for custom spans using `@dynatrace/oneagent-sdk` (Node.js), `oneagent-sdk` (Python), or OneAgent Java SDK
4. For cross-service propagation: forward and extract the `x-dynatrace` header between services
5. Verify in Distributed Traces UI: service appears in Service Map with custom spans

Reference: `references/dynatrace.md` → Code-Level Instrumentation

## Mode: monitor

Configure anomaly detection and alerting for a service.

Steps:
1. Ask for: service entity ID (from Smartscape or Settings API), alerting thresholds (auto-detection or fixed), notification target
2. Generate Terraform `dynatrace_service_anomalies_v2` resource for failure rate and response time
3. Generate Terraform `dynatrace_alerting` profile linking anomalies to the team
4. Davis AI will auto-detect baseline anomalies — custom thresholds override only when auto-detection is too noisy
5. Wire alerting profile to notification integration (PagerDuty, Slack, Opsgenie)

Reference: `references/dynatrace.md` → Terraform Provider, Davis AI Problem Feeds

## Mode: slo

Define a Dynatrace SLO.

Steps:
1. Ask for: SLI expression (availability / latency / custom), target %, timeframe
2. Generate Terraform `dynatrace_slo_v2` resource
3. Use built-in metrics for availability: `builtin:service.errors.server.successCount` / `builtin:service.requestCount.server`
4. Validate the metric expression returns data in the Metrics Explorer before applying
5. Set both `target_success` and `target_warning` thresholds

Reference: `references/dynatrace.md` → SLOs

## Mode: dashboard

Create a Dynatrace dashboard.

Steps:
1. Ask for: service entity ID, key metrics to show (availability, latency, throughput, error rate)
2. Generate Terraform `dynatrace_json_dashboard` resource pointing to a JSON dashboard file
3. Use built-in service metrics: `builtin:service.requestCount.server`, `builtin:service.response.time`, `builtin:service.errors.server.rate`
4. Provide dashboard JSON with tiles for each metric using `DATA_EXPLORER` tile type

Reference: `references/dynatrace.md` → Terraform Provider

## Mode: debug

Diagnose Dynatrace data gaps or injection failures.

Classify the failure:
- **Injection** — OneAgent not injecting into pods
- **Traces** — service not in Service Map or distributed traces broken
- **Metrics** — custom metrics not appearing
- **SLO** — SLO shows 0% or "No data"
- **Davis AI** — Problems not being created for known issues

Evidence to collect:
```bash
# Operator and DynaKube status
kubectl -n dynatrace get dynakube
kubectl -n dynatrace get pods

# Check injection on app pod
kubectl describe pod <app-pod> | grep -i dynatrace

# Verify MINT ingestion (custom metrics)
curl "https://{env}.live.dynatrace.com/api/v2/metrics/query?metricSelector=<your.metric>" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}"

# List open Davis AI problems
curl "https://{env}.live.dynatrace.com/api/v2/problems?problemSelector=status(OPEN)" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}"
```

Provide: symptom → root cause hypothesis → evidence command → fix → validation step

---
name: datadog
description: Set up and troubleshoot Datadog — Agent deployment on Kubernetes, APM instrumentation, Log Management, Monitors, Dashboards, SLOs, and Synthetic tests. Covers Terraform-managed Datadog resources.
argument-hint: "[setup|instrument|monitor|dashboard|slo|debug] [service or description]"
---

Configure or troubleshoot Datadog observability for a service or platform.

## Mode: setup

Deploy and configure the Datadog Agent on Kubernetes.

Steps:
1. Ask for: Kubernetes distribution (EKS/AKS/GKE), Datadog site (EU: `datadoghq.eu` / US: `datadoghq.com`), features needed (APM, logs, process monitoring)
2. Generate Helm values with: API key from Secret (never hardcoded), APM enabled, log collection enabled, cluster name set, Cluster Agent enabled with 2 replicas
3. Provide install command: `helm upgrade --install datadog datadog/datadog -f values.yaml -n datadog`
4. Provide verification commands: `kubectl exec -n datadog ds/datadog -- agent status`
5. Add Unified Service Tagging labels (`DD_ENV`, `DD_SERVICE`, `DD_VERSION`) to app Deployment

Reference: `references/datadog.md` → Agent Setup

## Mode: instrument

Add APM tracing to a service.

Steps:
1. Ask for: language (Node.js / Python / Java / Go), framework (Express / Django / Spring / etc.), whether log-trace correlation is needed
2. Generate tracer initialisation code — `dd-trace` init must be the first import in Node.js; use `ddtrace-run` or `patch_all()` in Python
3. Add Unified Service Tagging env vars to the Deployment manifest
4. Add custom spans for business-critical paths (payment processing, order creation, etc.)
5. Show expected APM UI outcome: service map entry, latency/error rate populated

Reference: `references/datadog.md` → APM Instrumentation, Unified Service Tagging

## Mode: monitor

Create a Datadog monitor for a service.

Steps:
1. Ask for: metric to alert on (error rate / latency / availability), thresholds, notification targets (PagerDuty / Slack)
2. Generate Terraform `datadog_monitor` resource (preferred over UI / API for IaC)
3. Set `notify_no_data: true` and `no_data_timeframe` so silent services alert
4. Include warning and critical thresholds
5. Tag with `service:`, `env:`, `team:` for routing

Output monitor query, thresholds, notification message with `@pagerduty-*` and `@slack-*` handles.

Reference: `references/datadog.md` → Monitors, Terraform Monitor

## Mode: dashboard

Create a Datadog dashboard for a service.

Steps:
1. Default to RED method: request rate, error rate %, p50/p95/p99 latency
2. Generate Terraform `datadog_dashboard` resource with `timeseries_definition` widgets
3. Use APM metrics: `trace.web.request.hits`, `trace.web.request.errors`, `trace.web.request` percentiles
4. Add template variables for `env` and `service` for reuse across environments

Reference: `references/datadog.md` → Dashboards

## Mode: slo

Define a Datadog SLO.

Steps:
1. Ask for: SLI metric (availability / latency), target (e.g. 99.9%), timeframe (7d / 30d / 90d)
2. Generate Terraform `datadog_service_level_objective` resource
3. Set both target and warning thresholds
4. Link SLO to relevant monitors for error budget burn alerts

Reference: `references/datadog.md` → SLOs

## Mode: debug

Diagnose Datadog data gaps or agent issues.

Classify the failure:
- **Agent** — no data flowing, agent status unhealthy
- **APM** — traces missing, service not appearing in service map
- **Logs** — logs not ingested, missing trace correlation
- **Monitor** — "No Data" state, incorrect thresholds
- **Metrics** — custom metric not visible in Metrics Explorer

Evidence to collect:
```bash
# Agent health
kubectl exec -n datadog ds/datadog -- agent status

# Check APM port
kubectl exec -n datadog ds/datadog -- agent check apm

# Verify pod env vars
kubectl describe pod <app-pod> | grep -E "DD_ENV|DD_SERVICE|DD_VERSION|DD_TRACE"

# Test metric query in Metrics Explorer before using in monitor
```

Provide: symptom → root cause hypothesis → evidence command → fix → validation

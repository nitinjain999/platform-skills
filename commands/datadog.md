---
name: datadog
description: Set up and troubleshoot Datadog — Agent deployment on Kubernetes, APM instrumentation, Log Management, Monitors, Dashboards, SLOs, Synthetic tests, and live incident investigation using the Datadog MCP server. Covers Terraform-managed Datadog resources.
argument-hint: "[setup|instrument|monitor|dashboard|slo|investigate|debug] [service or description]"
title: "Datadog Command"
sidebar_label: "datadog"
custom_edit_url: null
---

Configure, troubleshoot, or investigate incidents in Datadog.

## Mode: setup

Deploy and configure the Datadog Agent on Kubernetes.

Steps:
1. Ask for: Kubernetes distribution (EKS/AKS/GKE), Datadog site (EU: `datadoghq.eu` / US: `datadoghq.com`), features needed (APM, logs, process monitoring)
2. Generate Helm values with: API key from Secret (never hardcoded), APM enabled, log collection enabled, cluster name set, Cluster Agent enabled with 2 replicas
3. Provide install command: `helm upgrade --install datadog datadog/datadog -f values.yaml -n datadog`
4. Provide verification commands: `kubectl exec -n datadog ds/datadog -- agent status`
5. Add Unified Service Tagging labels (`DD_ENV`, `DD_SERVICE`, `DD_VERSION`) to app Deployment

## Mode: instrument

Add APM tracing to a service.

Steps:
1. Ask for: language (Node.js / Python / Java / Go), framework (Express / Django / Spring / etc.), whether log-trace correlation is needed
2. Generate tracer initialisation code — `dd-trace` init must be the first import in Node.js; use `ddtrace-run` or `patch_all()` in Python
3. Add Unified Service Tagging env vars to the Deployment manifest
4. Add custom spans for business-critical paths (payment processing, order creation, etc.)
5. Show expected APM UI outcome: service map entry, latency/error rate populated

## Mode: monitor

Create a Datadog monitor for a service.

Steps:
1. Ask for: metric to alert on (error rate / latency / availability), thresholds, notification targets (PagerDuty / Slack)
2. Generate Terraform `datadog_monitor` resource (preferred over UI / API for IaC)
3. Set `notify_no_data: true` and `no_data_timeframe` so silent services alert
4. Include warning and critical thresholds
5. Tag with `service:`, `env:`, `team:` for routing

Output monitor query, thresholds, notification message with `@pagerduty-*` and `@slack-*` handles.

## Mode: dashboard

Create a Datadog dashboard for a service.

Steps:
1. Default to RED method: request rate, error rate %, p50/p95/p99 latency
2. Generate Terraform `datadog_dashboard` resource with `timeseries_definition` widgets
3. Use APM metrics: `trace.web.request.hits`, `trace.web.request.errors`, `trace.web.request` percentiles
4. Add template variables for `env` and `service` for reuse across environments

## Mode: slo

Define a Datadog SLO.

Steps:
1. Ask for: SLI metric (availability / latency), target (e.g. 99.9%), timeframe (7d / 30d / 90d)
2. Generate Terraform `datadog_service_level_objective` resource
3. Set both target and warning thresholds
4. Link SLO to relevant monitors for error budget burn alerts

## Mode: investigate

**Live incident investigation using the Datadog MCP server.**

Requires the Datadog MCP server connected to Claude Code. See setup in `references/datadog.md` → MCP Server Setup.

### Phase 1 — Triage (what is broken right now?)

Ask Claude to run these via the MCP server:
- List all active monitors in ALERT or WARN state for the affected service and environment
- Fetch the triggering monitor's event stream for the last 30 minutes
- Check recent deployments — list events tagged `service:<name>` over the last 2 hours

```
What monitors are currently firing for service:orders-service env:production?
Show me the event stream for the orders-service in the last 30 minutes.
Were there any deployments to orders-service in the last 2 hours?
```

### Phase 2 — Signals (logs, metrics, traces)

Correlate the three pillars through the MCP:
- Pull error logs for the affected service filtered to the incident window
- Query APM error rate and p99 latency time series
- Fetch a sample of failing traces to identify the error message and stack trace

```
Show me error logs for service:orders-service between <start> and <end>.
What is the error rate and p99 latency for orders-service over the last hour?
Find traces with errors for orders-service — show me the top error messages.
```

### Phase 3 — Root cause

Narrow down with MCP queries:
- Compare metrics before and after the incident start time
- Check downstream dependencies — are errors concentrated on one endpoint or database host?
- Query infrastructure metrics (CPU, memory, disk) for the affected hosts

```
Compare the error rate for orders-service before and after <incident-start-time>.
Which endpoints have the highest error rate on orders-service right now?
Show me CPU and memory metrics for the hosts running orders-service.
```

### Phase 4 — Resolution and follow-up

- Acknowledge or resolve the triggering monitor via MCP
- Post an incident update to Slack via the MCP integration
- Create a notebook capturing the timeline, evidence, and resolution for the post-mortem

```
Resolve the monitor "orders-service high error rate" — the fix has been deployed.
Post to #incidents: "orders-service error rate returning to baseline, fix deployed at <time>."
Create a Datadog notebook summarising the orders-service incident timeline.
```

## Mode: debug

If you need deeper context on any Datadog component, load `references/datadog.md`.

Diagnose Datadog data gaps or agent issues without the MCP server.

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

## Mode: pup

Perform Datadog operations via the `pup` CLI — log search, metric queries, monitor management, and post-deploy gates.

Requires `pup` installed and `DD_API_KEY`, `DD_APP_KEY`, `DD_SITE` set in shell. See `references/datadog.md` → pup CLI for install and config.

Steps:
1. Classify the request:
   - **search** — search logs for a service/time range
   - **query** — fetch a metric time series
   - **monitors** — list, mute, unmute, or resolve a monitor
   - **gate** — generate a post-deploy quality gate script
2. Generate the exact `pup` command with flags
3. For scripting/gate use cases, generate a bash script using the scripting pattern from `references/datadog.md` → pup CLI
4. Include jq expression to extract the value of interest from `--format json` output

## Mode: llmo

Instrument an AI application with Datadog LLM Observability, bootstrap evaluators, analyze experiments, or root-cause LLM failures.

Steps:
1. Classify the request:
   - **instrument** — add LLMObs spans to a Python or Node.js LLM application
   - **evaluate** — attach evaluation scores to spans and set up a CI quality gate
   - **rca** — root-cause a failing LLM trace using `dd-llmo-eval-trace-rca`
   - **experiment** — compare model/prompt variants using `dd-llmo-experiment-analyzer`
2. For **instrument**: ask for language (Python/Node.js) and LLM provider (OpenAI/Anthropic/Bedrock); generate `LLMObs.enable()` init and `@llm` / `llmobs.trace()` call for the main LLM call; add `DD_LLMOBS_ML_APP` and `DD_LLMOBS_AGENTLESS_ENABLED` to the Deployment env vars
3. For **evaluate**: generate `LLMObs.submit_evaluation()` calls (kwarg `span=LLMObs.export_span()`) after each LLM span; generate a pup-based CI gate querying `ml_obs.evaluations.<label>` metric
4. For **rca**: instruct user to invoke `/dd-llmo-eval-trace-rca` with the failing trace ID; provide the manual `pup apm traces get` fallback
5. For **experiment**: generate `experiment.name`, `experiment.variant`, `experiment.cohort` tag annotations; instruct user to invoke `/dd-llmo-experiment-analyzer`; provide manual pup comparison fallback
6. Always set `DD_LLMOBS_ML_APP` — spans without this tag are silently discarded

Reference: `references/llm-observability.md`

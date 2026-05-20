# DORA Metrics Examples
Status: Stable

Working examples for tracking the four DORA metrics — Deployment Frequency, Lead Time for Changes, Change Failure Rate, and MTTR — using GitHub Actions, Prometheus Pushgateway, Prometheus recording rules, and Grafana.

## How it fits together

1. **GitHub Actions** pushes raw metric events (deploy timestamps, lead time, incident lifecycle) to a Prometheus Pushgateway.
2. **Prometheus recording rules** aggregate those raw events into the four DORA KPIs over a 30-day window.
3. **Grafana** visualises the KPIs with DORA performance-band thresholds (Elite / High / Medium / Low).

## Files

| File | Description |
|---|---|
| `deployment-event-step.yaml` | GitHub Actions step: push deploy event to Prometheus Pushgateway |
| `incident-webhook-handler.yaml` | GitHub Actions workflow triggered by PagerDuty/OpsGenie webhook |
| `prometheus-recording-rules.yaml` | All four DORA Prometheus recording rules |
| `grafana-dashboard.json` | Grafana dashboard JSON with four DORA panels and threshold bands |
| `dora-validate.sh` | Domain validator |
| `amp-variant/` | AMP-specific replacements — see below |

## Amazon Managed Prometheus (AMP)

AMP has no public Pushgateway endpoint. Use the files in [`amp-variant/`](amp-variant/) alongside the standard files:

| amp-variant file | What it does |
|---|---|
| `pushgateway-helm-values.yaml` | Deploys in-cluster Pushgateway (GitHub Actions still pushes here) |
| `prometheus-agent-values.yaml` | Prometheus Agent: scrapes Pushgateway, remote_writes to AMP via SigV4/IRSA |
| `amp-recording-rules-deploy.sh` | AWS CLI script to create/update DORA rules in AMP (replaces `kubectl apply`) |
| `grafana-amp-datasource.yaml` | Grafana datasource ConfigMap for self-hosted Grafana → AMP (SigV4) |
| `grafana-amg-datasource.json` | Datasource config for Amazon Managed Grafana |

The `deployment-event-step.yaml`, `incident-webhook-handler.yaml`, `prometheus-recording-rules.yaml`, and `grafana-dashboard.json` files are **unchanged** — only the infrastructure wiring differs.

## Usage

### 1. Push deployment events

Append `deployment-event-step.yaml` to your existing production deploy workflow. Set `PUSHGATEWAY_URL` as a repository secret pointing to your Pushgateway instance.

### 2. Handle incident events

Deploy `incident-webhook-handler.yaml` as a GitHub Actions workflow. Configure your PagerDuty or OpsGenie account to send `repository_dispatch` webhook events to the GitHub API.

### 3. Apply Prometheus recording rules

```bash
kubectl apply -f examples/dora/prometheus-recording-rules.yaml
```

Or add the file to your Prometheus Operator `PrometheusRule` CRD if using the kube-prometheus-stack Helm chart.

### 4. Import Grafana dashboard

Import `grafana-dashboard.json` via Grafana UI: **Dashboards → Import → Upload JSON file**, or provision it via your GitOps pipeline into the Grafana provisioning directory.

## Validation

Run the domain validator from the repository root:

```bash
bash examples/dora/dora-validate.sh
```

The validator checks all YAML files with `yq` and the JSON dashboard with `python3`. It exits non-zero if any file fails.

## Prerequisites

| Tool | Minimum version | Purpose |
|---|---|---|
| `yq` | v4+ | YAML validation |
| `python3` | 3.6+ | JSON validation |
| Prometheus Pushgateway | any | Receives metric pushes from CI |
| Prometheus | 2.x | Evaluates recording rules |
| Grafana | 9+ | Dashboard rendering (schemaVersion 36) |

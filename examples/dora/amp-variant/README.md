# DORA Metrics — Amazon Managed Prometheus (AMP) Variant

This directory contains AMP-specific replacements for files in `examples/dora/`.
Use these instead of the parent directory files when your Prometheus backend is AMP.

## Architecture

```
GitHub Actions  ──push──►  Pushgateway (in-cluster)  ──scrape──►  Prometheus Agent
                                                                         │
                                                              remote_write (SigV4)
                                                                         │
                                                                         ▼
                                                              Amazon Managed Prometheus
                                                                         │
                                                                    Grafana / AMG
```

AMP has no public Pushgateway endpoint. The supported pattern is:

1. GitHub Actions pushes deploy/incident metrics to an **in-cluster Pushgateway** (same as the default variant — no change to workflow steps)
2. A **Prometheus Agent** (or any Prometheus with `remote_write`) scrapes the Pushgateway and forwards to AMP using SigV4 authentication
3. Recording rules are managed via the **AWS CLI** (`aws amp create-rule-groups-namespace`)
4. Grafana connects to AMP via SigV4 (self-hosted Grafana with plugin, or Amazon Managed Grafana)

## Files

| File | Replaces | What it adds |
|---|---|---|
| `pushgateway-helm-values.yaml` | — | Prometheus Pushgateway Helm values with remote_write to AMP |
| `prometheus-agent-values.yaml` | — | Prometheus Agent Helm values: scrapes Pushgateway, remote_writes to AMP via SigV4 |
| `amp-recording-rules-deploy.sh` | — | AWS CLI script to create/update DORA recording rules in AMP |
| `grafana-amp-datasource.yaml` | — | Grafana datasource ConfigMap for self-hosted Grafana connecting to AMP |
| `grafana-amg-datasource.json` | — | AMG datasource config (Amazon Managed Grafana, SigV4 auto-handled) |

Files from `examples/dora/` that are **unchanged** for AMP:
- `deployment-event-step.yaml` — still pushes to in-cluster Pushgateway, no changes needed
- `incident-webhook-handler.yaml` — still pushes to in-cluster Pushgateway, no changes needed
- `prometheus-recording-rules.yaml` — same rule content; only the delivery mechanism differs (use `amp-recording-rules-deploy.sh`)
- `grafana-dashboard.json` — same dashboard JSON; import into AMG or self-hosted Grafana with SigV4 datasource

## Prerequisites

- AMP workspace created: `aws amp create-workspace --alias dora --region eu-central-1`
- IRSA or Pod Identity for the Prometheus Agent pod with policy `AmazonPrometheusRemoteWriteAccess`
- Pushgateway deployed in-cluster (see `pushgateway-helm-values.yaml`)
- AWS CLI v2 with `aps:CreateRuleGroupsNamespace` / `aps:PutRuleGroupsNamespace` permissions

## Quick start

```bash
# 1. Deploy Pushgateway
helm upgrade --install pushgateway prometheus-community/prometheus-pushgateway \
  --namespace monitoring --create-namespace \
  -f examples/dora/amp-variant/pushgateway-helm-values.yaml

# 2. Deploy Prometheus Agent (scrapes Pushgateway, remote_writes to AMP)
helm upgrade --install prometheus-agent prometheus-community/prometheus \
  --namespace monitoring \
  -f examples/dora/amp-variant/prometheus-agent-values.yaml

# 3. Deploy DORA recording rules to AMP
AMP_WORKSPACE_ID=$(aws amp list-workspaces --alias dora --query 'workspaces[0].workspaceId' --output text)
bash examples/dora/amp-variant/amp-recording-rules-deploy.sh "$AMP_WORKSPACE_ID"

# 4. Connect Grafana to AMP
kubectl apply -f examples/dora/amp-variant/grafana-amp-datasource.yaml
# Then import examples/dora/grafana-dashboard.json into Grafana
```

# DORA Metrics — Amazon Managed Prometheus (AMP) Variant

This directory contains AMP-specific replacements for files in `examples/dora/`.
Use these instead of the parent directory files when your Prometheus backend is AMP.

## Architecture

```
GitHub Actions  ──push──►  Pushgateway (in-cluster)  ──scrape──►  Prometheus Agent
                                                                         │
                                                              remote_write (SigV4/IRSA)
                                                                         │
                                                                         ▼
                                                              Amazon Managed Prometheus
                                                                         │
                                                                    Grafana / AMG
```

AMP has no public Pushgateway endpoint. The supported pattern is:

1. GitHub Actions pushes deploy/incident metrics to an **in-cluster Pushgateway** (same as the default variant — no change to workflow steps)
2. A **Prometheus Agent** scrapes the Pushgateway and remote_writes to AMP using SigV4 (via IRSA)
3. Recording rules are managed via **Terraform** (preferred) or the AWS CLI fallback script
4. Grafana connects to AMP via SigV4 (self-hosted with plugin, or Amazon Managed Grafana)

## Files

| File | What it does |
|---|---|
| `amp-workspace.tf` | Terraform: provision AMP workspace + deploy DORA recording rules in one apply |
| `pushgateway-helm-values.yaml` | Prometheus Pushgateway Helm values (in-cluster) |
| `prometheus-agent-values.yaml` | Prometheus Agent Helm values: scrapes Pushgateway, remote_writes to AMP via SigV4 |
| `amp-recording-rules-deploy.sh` | AWS CLI fallback: create/update DORA rules in AMP without Terraform |
| `grafana-amp-datasource.yaml` | Grafana datasource ConfigMap — self-hosted Grafana → AMP (SigV4, IRSA) |
| `grafana-amg-datasource.json` | Datasource config for Amazon Managed Grafana (SigV4 auto-handled) |

Files from `examples/dora/` that are **unchanged** for AMP:
- `deployment-event-step.yaml` — still pushes to in-cluster Pushgateway, no changes
- `incident-webhook-handler.yaml` — still pushes to in-cluster Pushgateway, no changes
- `prometheus-recording-rules.yaml` — same rule YAML; `amp-workspace.tf` and `amp-recording-rules-deploy.sh` both consume it
- `grafana-dashboard.json` — same dashboard JSON; import into AMG or self-hosted Grafana pointing at AMP

## Quick start — Terraform path (recommended)

```bash
# 1. Provision AMP workspace + deploy DORA recording rules
cd examples/dora/amp-variant
terraform init
terraform apply -var="workspace_alias=dora-platform"

# Capture the outputs for steps 2 and 4:
terraform output workspace_prometheus_endpoint
terraform output workspace_id

# 2. Deploy in-cluster Pushgateway
helm upgrade --install pushgateway prometheus-community/prometheus-pushgateway \
  --namespace monitoring --create-namespace \
  -f pushgateway-helm-values.yaml

# 3. Deploy Prometheus Agent
# Replace <endpoint> with the remote_write_url Terraform output.
# Replace <account-id> with your AWS account ID in prometheus-agent-values.yaml first.
helm upgrade --install prometheus-agent prometheus-community/prometheus \
  --namespace monitoring \
  -f prometheus-agent-values.yaml

# 4. Connect Grafana to AMP
kubectl apply -f grafana-amp-datasource.yaml
# Then import examples/dora/grafana-dashboard.json into Grafana
```

## Quick start — AWS CLI fallback (no Terraform)

```bash
# 1. Create AMP workspace
aws amp create-workspace --alias dora-platform --region eu-central-1

# 2. Deploy DORA recording rules
AMP_WORKSPACE_ID=$(aws amp list-workspaces \
  --query 'workspaces[?alias==`dora-platform`].workspaceId' \
  --output text --region eu-central-1)
bash examples/dora/amp-variant/amp-recording-rules-deploy.sh "$AMP_WORKSPACE_ID"

# 3-4. Same as Terraform path above (Helm + Grafana)
```

## Prerequisites

| Component | Requirement |
|---|---|
| Terraform | >= 1.5.7 (for `amp-workspace.tf`) |
| AWS provider | >= 6.28 |
| IRSA / Pod Identity | Prometheus Agent pod needs `AmazonPrometheusRemoteWriteAccess` |
| IRSA / Pod Identity | Grafana pod needs `AmazonPrometheusQueryAccess` |
| Helm | >= 3.x |
| yq | v4+ (for dora-validate.sh) |

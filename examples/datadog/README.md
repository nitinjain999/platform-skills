Status: Stable

# Datadog Examples

Production-ready Datadog configurations for Kubernetes, APM, monitors, dashboards, and SLOs.

## Examples

| Example | Type | Description |
|---------|------|-------------|
| [helm-values/](helm-values/) | Helm | Agent values — APM, logs, Cluster Agent |
| [terraform/](terraform/) | Terraform | Monitors, dashboards, and SLOs as code |

## Usage

```bash
# Deploy agent
helm repo add datadog https://helm.datadoghq.com
helm upgrade --install datadog datadog/datadog \
  -f helm-values/datadog-values.yaml \
  --set datadog.apiKey="${DD_API_KEY}" \
  -n datadog --create-namespace

# Apply Terraform resources
cd terraform
terraform init && terraform plan
```

## See Also

- [references/datadog.md](../../references/datadog.md) — agent setup, APM, logs, monitors, dashboards, SLOs
- `/platform-skills:datadog` — setup, instrument, monitor, dashboard, SLO, debug

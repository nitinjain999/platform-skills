Status: Stable

# Datadog Examples

Production-ready Datadog configurations for Kubernetes, APM, monitors, dashboards, and SLOs.

## Examples

| Example | Type | Description |
|---------|------|-------------|
| [terraform/](terraform/) | Terraform | Monitors, dashboards, and SLOs as code |

## Usage

```bash
# Deploy agent — create API key secret first, never pass on command line
kubectl create secret generic datadog-secret \
  --from-literal=api-key="${DD_API_KEY}" \
  -n datadog --dry-run=client -o yaml | kubectl apply -f -

helm repo add datadog https://helm.datadoghq.com
helm upgrade --install datadog datadog/datadog \
  --set datadog.apiKeyExistingSecret=datadog-secret \
  -n datadog --create-namespace

# Apply Terraform resources
cd terraform
terraform init && terraform plan
```

## See Also

- [references/datadog.md](../../references/datadog.md) — agent setup, APM, logs, monitors, dashboards, SLOs
- `/platform-skills:datadog` — setup, instrument, monitor, dashboard, SLO, debug

Status: Stable

# Dynatrace Examples

Production-ready Dynatrace configurations for OneAgent Kubernetes deployment, anomaly detection, SLOs, and dashboards.

## Examples

| Example | Type | Description |
|---------|------|-------------|
| [operator/](operator/) | Kubernetes | DynaKube CR for cloudNativeFullStack injection |
| [terraform/](terraform/) | Terraform | Anomaly detection, SLOs, and alerting as code |

## Usage

```bash
# Deploy OneAgent Operator
kubectl create namespace dynatrace
kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/latest/download/kubernetes.yaml
kubectl -n dynatrace create secret generic dynakube \
  --from-literal=apiToken="${DT_API_TOKEN}" \
  --from-literal=dataIngestToken="${DT_DATA_INGEST_TOKEN}"
kubectl apply -f operator/dynakube.yaml

# Apply Terraform resources
cd terraform
terraform init && terraform plan
```

## See Also

- [references/dynatrace.md](../../references/dynatrace.md) — Operator setup, instrumentation, metrics, SLOs, Terraform provider
- `/platform-skills:dynatrace` — setup, instrument, monitor, SLO, dashboard, debug

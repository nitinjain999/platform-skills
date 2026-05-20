Status: Stable

# Datadog Examples

Production-ready Datadog monitors, dashboards, and SLOs managed as Terraform code.

## Examples

| Example | Type | Description |
|---------|------|-------------|
| [terraform/monitors.tf](terraform/) | Terraform | Error rate monitor, p99 latency monitor, and 30-day availability SLO |
| [llm-observability/llmobs-python.py](llm-observability/llmobs-python.py) | Python | LLMObs instrumentation with `@llm`, `@workflow`, `@retrieval` decorators and faithfulness evaluation |
| [llm-observability/llmobs-nodejs.js](llm-observability/llmobs-nodejs.js) | Node.js | LLMObs instrumentation with `llmobs.trace()` and evaluation submission |
| [llm-observability/evaluator-bootstrap.py](llm-observability/evaluator-bootstrap.py) | Python | Faithfulness and quality evaluator stubs generated from production trace patterns |

## Quick Start

```bash
# Export credentials (never hardcode)
export DD_API_KEY="your-api-key"
export DD_APP_KEY="your-app-key"

cd terraform
terraform init
terraform plan
terraform apply
```

## What terraform/monitors.tf Creates

| Resource | Type | Threshold |
|----------|------|-----------|
| `orders-service high error rate` | Metric alert | Critical: > 5%, Warning: > 2% |
| `orders-service p99 latency high` | Metric alert | Critical: > 1s, Warning: > 0.5s |
| `Orders Service Availability` | SLO (metric) | Target: 99.9%, Warning: 99.95% over 30d |

## Key Patterns

### Unified Service Tagging (required on all Datadog resources)

Always set these three tags consistently across pods, traces, logs, and monitors:

```yaml
# Pod environment variables
env:
  - name: DD_ENV
    value: "production"
  - name: DD_SERVICE
    value: "orders-service"
  - name: DD_VERSION
    valueFrom:
      fieldRef:
        fieldPath: metadata.annotations['app.kubernetes.io/version']
```

### Secure Agent installation (no `--set apiKey`)

```bash
# ✅ Create namespace + secret (idempotent)
kubectl create namespace datadog --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic datadog-secret \
  --from-literal=api-key="${DD_API_KEY}" \
  -n datadog \
  --dry-run=client -o yaml | kubectl apply -f -

# ✅ Reference secret in Helm values
helm upgrade --install datadog datadog/datadog \
  --set datadog.apiKeyExistingSecret=datadog-secret \
  --create-namespace \
  -n datadog

# ❌ Never pass key on command line — stored in Helm release history
# helm upgrade --install datadog datadog/datadog --set datadog.apiKey="${DD_API_KEY}"
```

### Log + trace correlation

```javascript
// dd-trace init — must be first import
import tracer from "dd-trace";
tracer.init({
  service: "orders-service",
  env: process.env.DD_ENV,
  logInjection: true,  // injects trace_id and span_id into log lines
});
```

## Adapt to Your Service

Replace `orders-service` in `monitors.tf` with your service name:

```bash
sed -i 's/orders-service/my-service/g' terraform/monitors.tf
```

## Checklist

- [ ] Unified Service Tagging applied: `DD_ENV`, `DD_SERVICE`, `DD_VERSION` on every pod
- [ ] API key stored in Kubernetes Secret — not in Helm values or environment
- [ ] `logInjection: true` in tracer init — enables log/trace correlation
- [ ] Monitors notify correct PagerDuty/Slack channels (`@pagerduty-*`, `@slack-*`)
- [ ] SLO target and timeframe match your error budget

## See Also

- [references/datadog.md](../../references/datadog.md) — Agent setup, APM, log management, monitors, dashboards, SLOs, synthetic tests, MCP server, pup CLI, Datadog Labs skills
- [references/llm-observability.md](../../references/llm-observability.md) — LLMObs instrumentation, eval bootstrap, trace RCA, experiment analysis
- `/platform-skills:datadog` — setup, instrument, monitor, dashboard, SLO, investigate incidents

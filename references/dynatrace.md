# Dynatrace Reference

Covers OneAgent deployment, Kubernetes Operator, Davis AI, Distributed Tracing, Log Monitoring, SLOs, and Dashboards.

---

## MCP Server Setup

The official Dynatrace MCP server lets Claude Code query Problems, logs, traces, DQL, and Davis AI directly — enabling AI-driven incident investigation without leaving your editor.

### Connect to Claude Code

```bash
# stdio transport (local, Node.js 22+ required)
claude mcp add dynatrace -- npx -y @dynatrace-oss/dynatrace-mcp-server

# Set your environment URL
export DT_ENVIRONMENT="https://abc12345.apps.dynatrace.com"   # Platform URL (not classic)
```

Or add to `.mcp.json`:

```json
{
  "mcpServers": {
    "dynatrace": {
      "command": "npx",
      "args": ["-y", "@dynatrace-oss/dynatrace-mcp-server@latest"],
      "env": {
        "DT_ENVIRONMENT": "https://abc12345.apps.dynatrace.com"
      }
    }
  }
}
```

**Remote MCP** (no local Node.js needed): available at the [Dynatrace Hub](https://www.dynatrace.com/hub/detail/dynatrace-mcp-server/). Authentication handled via browser OAuth — no token needed.

**Cost note**: `execute_dql` scans Grail data and may incur costs. Set `DT_GRAIL_QUERY_BUDGET_GB` (default 1000 GB) to cap session spend. Use short timeframes (1h–24h) during investigation.

### Available Capabilities

| Category | Key Tools |
|----------|-----------|
| Problems | `list_problems`, full problem details with root cause entity and impact |
| Logs / Metrics / Traces | `execute_dql` — query any Grail data with DQL |
| Natural language | `generate_dql_from_natural_language`, `explain_dql_in_natural_language` |
| Entity discovery | `find_entity_by_name` — look up services, hosts, process groups |
| Davis AI | `chat_with_davis_copilot`, `list_davis_analyzers`, `execute_davis_analyzer` |
| Kubernetes | `get_kubernetes_events` |
| Exceptions | `list_exceptions` with stack traces |
| Notifications | `send_slack_message`, `send_email`, `send_event` |
| Documentation | `create_dynatrace_notebook` for post-mortem capture |

### Incident Investigation Workflow

Use `/platform-skills:dynatrace investigate` for a guided 4-phase workflow:
1. **Triage** — list open Problems, get Davis AI root cause entity and impact scope
2. **Signals** — DQL queries for error logs, exceptions, and failing traces
3. **Root cause** — Davis Copilot analysis, Davis Analyzer execution, entity health check
4. **Resolution** — close Problem with note, send Slack update, create Notebook

---

## Deployment

### Kubernetes Operator (recommended)

```bash
# Install the Dynatrace Operator
kubectl create namespace dynatrace
kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/latest/download/kubernetes.yaml

# Create API and data-ingest tokens as a Secret
kubectl -n dynatrace create secret generic dynakube \
  --from-literal=apiToken="${DT_API_TOKEN}" \
  --from-literal=dataIngestToken="${DT_DATA_INGEST_TOKEN}"
```

```yaml
# dynakube.yaml — full-stack monitoring with automatic injection
apiVersion: dynatrace.com/v1beta1
kind: DynaKube
metadata:
  name: dynakube
  namespace: dynatrace
spec:
  apiUrl: "https://{your-environment-id}.live.dynatrace.com/api"
  tokens: dynakube

  oneAgent:
    cloudNativeFullStack:
      # Automatic injection into all pods — no restart required
      image: ""       # use default

  activeGate:
    capabilities:
      - routing
      - kubernetes-monitoring
      - dynatrace-api
    replicas: 2

  metadataEnrichment:
    enabled: true     # enriches logs/metrics with k8s metadata
```

```bash
kubectl apply -f dynakube.yaml
kubectl -n dynatrace get dynakube dynakube
```

### Verify Injection

```bash
# OneAgent should be injected into app pods as an init container
kubectl describe pod <app-pod> | grep dynatrace
```

---

## Code-Level Instrumentation

### Node.js (OneAgent auto-instruments automatically)

```js
// For custom business transactions — no SDK needed for http/db/cache
// Use the SDK only for custom spans
import Dynatrace from "@dynatrace/oneagent-sdk";

const sdk = Dynatrace.createInstance();
const tracer = sdk.traceIncomingRemoteCall({
  serviceMethod: "processPayment",
  serviceName: "orders-service",
  serviceEndpoint: "/payments",
  dynatraceStringTag: req.headers["x-dynatrace"],
  protocol: Dynatrace.ChannelType.OTHER,
});

tracer.start(async () => {
  await processPayment(order);
});
```

### Java / Spring Boot (auto-instrumented)

OneAgent auto-instruments JVM services — no code changes needed. For custom spans:

```java
import com.dynatrace.oneagent.sdk.api.OneAgentSDK;
import com.dynatrace.oneagent.sdk.api.OneAgentSDKFactory;

OneAgentSDK sdk = OneAgentSDKFactory.createInstance();
OutgoingRemoteCallTracer tracer = sdk.traceOutgoingRemoteCall(
    "processPayment", "PaymentService", "grpc://payments:50051",
    ChannelType.OTHER, null);

tracer.start();
try {
    stub.processPayment(request);
    tracer.end();
} catch (Exception e) {
    tracer.error(e);
    tracer.end();
}
```

### Python (OneAgent auto-instruments Django, Flask, FastAPI, SQLAlchemy)

```bash
pip install oneagent-sdk
```

```python
import oneagent

with oneagent.sdk.get_sdk().trace_custom_service(
    "processPayment", "orders-service"
) as tracer:
    process_payment(order)
```

---

## Log Monitoring

### Kubernetes Log Ingestion

OneAgent collects container stdout/stderr automatically when `cloudNativeFullStack` is enabled.

Enrich logs with custom attributes:

```yaml
# Add log enrichment annotations to pod spec
metadata:
  annotations:
    logs.dynatrace.com/ingest: "true"
```

### Log Processing Rules (via UI or API)

```bash
# Create a log processing rule via Settings API
curl -X POST "https://{env}.live.dynatrace.com/api/v2/settings/objects" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "schemaId": "builtin:logmonitoring.log-storage-settings",
    "value": {
      "enabled": true,
      "matchers": [{"attribute": "k8s.namespace.name", "values": ["production"]}],
      "send_to_storage": true
    }
  }'
```

---

## Metrics Ingestion (Custom Metrics)

```bash
# Ingest custom metrics via the Metrics Ingestion API (MINT)
curl -X POST "https://{env}.live.dynatrace.com/api/v2/metrics/ingest" \
  -H "Authorization: Api-Token ${DT_DATA_INGEST_TOKEN}" \
  -H "Content-Type: text/plain" \
  --data-binary "orders.created,env=production,service=orders-service count,delta=42"
```

```python
# Python helper
import requests

def push_metric(env: str, token: str, metric: str, value: float, tags: dict):
    tag_str = ",".join(f"{k}={v}" for k, v in tags.items())
    payload = f"{metric},{tag_str} gauge,{value}"
    requests.post(
        f"https://{env}.live.dynatrace.com/api/v2/metrics/ingest",
        headers={"Authorization": f"Api-Token {token}", "Content-Type": "text/plain"},
        data=payload,
    )
```

---

## SLOs

```bash
# Create SLO via API
curl -X POST "https://{env}.live.dynatrace.com/api/v2/slo" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Orders Service Availability",
    "description": "99.9% of requests succeed over 30 days",
    "metricExpression": "100*(builtin:service.errors.server.successCount:splitBy():sum)/(builtin:service.requestCount.server:splitBy():sum)",
    "evaluationType": "AGGREGATE",
    "filter": "type(SERVICE),entityName(orders-service),tag(env:production)",
    "target": 99.9,
    "warning": 99.95,
    "timeframe": "-30d",
    "enabled": true
  }'
```

---

## Terraform Provider (preferred for IaC)

```hcl
terraform {
  required_providers {
    dynatrace = {
      source  = "dynatrace-oss/dynatrace"
      version = "~> 1.0"
    }
  }
}

provider "dynatrace" {
  dt_env_url   = "https://{env}.live.dynatrace.com"
  dt_api_token = var.dt_api_token
}

# Service anomaly detection
resource "dynatrace_service_anomalies_v2" "orders" {
  scope = "SERVICE-XXXXXXXXXXXXXXXX"   # service entity ID

  failure_rate {
    detection_mode = "auto"
    enabled        = true
  }

  response_time {
    detection_mode = "auto"
    enabled        = true
  }
}

# Dashboard
resource "dynatrace_json_dashboard" "orders_red" {
  contents = file("${path.module}/dashboards/orders-red.json")
}

# SLO
resource "dynatrace_slo_v2" "orders_availability" {
  name        = "Orders Service Availability"
  enabled     = true
  description = "99.9% of requests succeed"

  metric_expression = "100*(builtin:service.errors.server.successCount:splitBy():sum)/(builtin:service.requestCount.server:splitBy():sum)"
  evaluation_type   = "AGGREGATE"
  filter            = "type(SERVICE),entityName(orders-service)"
  target_success    = 99.9
  target_warning    = 99.95
  timeframe         = "-30d"
}

# Alerting profile
resource "dynatrace_alerting" "platform" {
  name = "Platform Team"

  rules {
    delay_in_minutes = 0
    include_mode     = "INCLUDE_ALL"
    severity_level   = "AVAILABILITY"
  }
}
```

---

## Davis AI Problem Feeds

Davis AI automatically detects anomalies and creates Problems. Query the Problems API to integrate with incident workflows:

```bash
# Get open problems
curl "https://{env}.live.dynatrace.com/api/v2/problems?problemSelector=status(OPEN)" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}"

# Acknowledge a problem
curl -X POST "https://{env}.live.dynatrace.com/api/v2/problems/{problemId}/close" \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"message": "Resolved by platform team — see INC-1234"}'
```

---

## Troubleshooting

| Symptom | Evidence | Fix |
|---------|----------|-----|
| OneAgent not injecting | `kubectl describe pod` — no init containers | Check DynaKube `cloudNativeFullStack` is set; verify namespace not excluded |
| No traces in distributed tracing | Service Map shows service as standalone | Confirm `x-dynatrace` header is forwarded between services |
| Custom metrics not appearing | Check MINT API response code | Verify metric key format: `<prefix>.<name>` with no spaces; confirm `dataIngestToken` has correct scope |
| SLO shows 0% | SLO metric expression returns no data | Validate filter matches entity name exactly; check entity ID in Smartscape |
| Davis AI not alerting | No Problems created | Verify anomaly detection is enabled on service settings; check alerting profile is assigned |

---

## Token Scopes

| Token Type | Required Scopes |
|-----------|----------------|
| `apiToken` | `ReadConfig`, `WriteConfig`, `DataExport`, `LogExport`, `ReadSyntheticData`, `WriteAnomalyDetection` |
| `dataIngestToken` | `metrics.ingest`, `logs.ingest` |

Store both tokens in Kubernetes Secrets or a secrets manager — never in plain Helm values or Terraform state.

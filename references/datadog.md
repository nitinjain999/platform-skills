# Datadog Reference

Covers APM, Infrastructure Monitoring, Log Management, Synthetic Monitoring, Dashboards, Monitors, and SLOs.

---

## MCP Server Setup

The official Datadog MCP server lets Claude Code query logs, metrics, traces, monitors, and incidents directly — no manual API calls needed during incident investigation.

### Connect to Claude Code

```bash
# EU site
claude mcp add --transport http datadog https://mcp.datadoghq.eu/api/unstable/mcp-server/mcp

# US1 site
claude mcp add --transport http datadog https://mcp.datadoghq.com/api/unstable/mcp-server/mcp
```

Or add to `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "datadog": {
      "type": "http",
      "url": "https://mcp.datadoghq.eu/api/unstable/mcp-server/mcp"
    }
  }
}
```

Authentication uses your Datadog session — log in via the browser prompt on first use.

### Available Capabilities

| Category | What you can do |
|----------|----------------|
| Monitors | List firing monitors, get monitor details, resolve monitors |
| Logs | Search logs by service/env/time, filter by status |
| Metrics | Query time series, compare before/after incident |
| APM Traces | Fetch traces with errors, inspect spans and stack traces |
| Events | List deployment events, audit events by tag |
| Incidents | List active incidents, post updates |
| Notebooks | Create notebooks for post-mortem documentation |

### Incident Investigation Workflow

Use `/platform-skills:datadog investigate` for a guided 4-phase workflow:
1. **Triage** — list firing monitors and recent deployments
2. **Signals** — pull error logs, error rate, and failing traces
3. **Root cause** — compare before/after metrics, isolate failing endpoint or host
4. **Resolution** — acknowledge monitor, post Slack update, create post-mortem notebook

---

## Agent Setup

### Kubernetes (Helm)

```yaml
# datadog-values.yaml
datadog:
  apiKey: "$(DD_API_KEY)"       # inject from secret, never hardcode
  site: "datadoghq.eu"          # or datadoghq.com
  apm:
    portEnabled: true
  logs:
    enabled: true
    containerCollectAll: true
  processAgent:
    enabled: true
  clusterName: "prod-eks"

agents:
  tolerations:
    - operator: Exists

clusterAgent:
  enabled: true
  replicas: 2
```

```bash
helm repo add datadog https://helm.datadoghq.com
helm upgrade --install datadog datadog/datadog \
  -f datadog-values.yaml \
  --set datadog.apiKey="${DD_API_KEY}" \
  -n datadog --create-namespace
```

### Verify Agent

```bash
kubectl exec -n datadog ds/datadog -- agent status
kubectl exec -n datadog ds/datadog -- agent check disk
```

---

## APM Instrumentation

### Node.js (dd-trace)

```js
// Must be the very first import
import tracer from "dd-trace";
tracer.init({
  service: "orders-service",
  env: process.env.DD_ENV ?? "production",
  version: process.env.DD_VERSION,   // inject from CI: git sha or semver
  logInjection: true,                // correlate logs and traces
});

// Custom span
const span = tracer.startSpan("payment.process");
span.setTag("payment.method", "card");
try {
  await processPayment(order);
  span.finish();
} catch (err) {
  span.setTag("error", err);
  span.finish();
  throw err;
}
```

### Python (ddtrace)

```python
# run with: ddtrace-run python app.py
# or instrument programmatically:
from ddtrace import tracer, patch_all
patch_all()   # auto-instrument Django, Flask, SQLAlchemy, Redis, etc.

with tracer.trace("payment.process", service="orders-service") as span:
    span.set_tag("payment.method", "card")
    result = process_payment(order)
```

### Unified Service Tagging

Set these three tags consistently across all telemetry:

```yaml
# Pod labels / env vars
DD_ENV: production
DD_SERVICE: orders-service
DD_VERSION: "1.2.3"          # matches git tag or image tag
```

---

## Log Management

### Structured Logging (Pino → Datadog)

```js
import pino from "pino";

const logger = pino({
  level: "info",
  // dd-trace injects trace_id and span_id when logInjection: true
  formatters: {
    level: (label) => ({ level: label }),
  },
  redact: ["req.headers.authorization", "*.password"],
});

logger.info({ orderId, userId }, "order.created");
```

### Log Pipeline (Kubernetes)

Agent `containerCollectAll: true` tails stdout/stderr from all containers. Add processing rules to:

```yaml
# agent config
logs_config:
  processing_rules:
    - type: exclude_at_match
      name: exclude_healthcheck
      pattern: "GET /healthz"
    - type: mask_sequences
      name: mask_tokens
      replace_placeholder: "[REDACTED]"
      pattern: "(Authorization: Bearer )[^\s]+"
```

### Log-Based Metrics

Convert high-cardinality logs into cost-effective metrics in Datadog UI:
- **Logs → Generate Metrics** → filter by `service:orders-service status:error` → metric `custom.orders.errors`

---

## Monitors

### Anomaly Monitor (APM error rate)

```bash
# Create via API
curl -X POST "https://api.datadoghq.eu/api/v1/monitor" \
  -H "DD-API-KEY: ${DD_API_KEY}" \
  -H "DD-APPLICATION-KEY: ${DD_APP_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "orders-service high error rate",
    "type": "metric alert",
    "query": "sum(last_5m):sum:trace.web.request.errors{service:orders-service,env:production}.as_count() / sum:trace.web.request.hits{service:orders-service,env:production}.as_count() > 0.05",
    "message": "Error rate above 5% on orders-service @pagerduty-platform @slack-platform-alerts",
    "tags": ["service:orders-service", "env:production", "team:platform"],
    "options": {
      "thresholds": {"critical": 0.05, "warning": 0.02},
      "notify_no_data": true,
      "no_data_timeframe": 10,
      "renotify_interval": 30
    }
  }'
```

### Terraform Monitor (preferred)

```hcl
resource "datadog_monitor" "orders_error_rate" {
  name    = "orders-service high error rate"
  type    = "metric alert"
  message = "Error rate above 5% on orders-service @pagerduty-platform"

  query = <<-EOQ
    sum(last_5m):
      sum:trace.web.request.errors{service:orders-service,env:production}.as_count()
      / sum:trace.web.request.hits{service:orders-service,env:production}.as_count()
    > 0.05
  EOQ

  monitor_thresholds {
    critical = 0.05
    warning  = 0.02
  }

  tags = ["service:orders-service", "env:production", "team:platform"]

  notify_no_data    = true
  no_data_timeframe = 10
  renotify_interval = 30
}
```

---

## Dashboards

### Dashboard as Code (Terraform)

```hcl
resource "datadog_dashboard" "orders_service" {
  title       = "Orders Service — RED"
  description = "Request rate, error rate, and latency for the orders service"
  layout_type = "ordered"

  widget {
    timeseries_definition {
      title = "Request Rate"
      request {
        q            = "sum:trace.web.request.hits{service:orders-service,env:production}.as_rate()"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Error Rate %"
      request {
        q            = "100 * sum:trace.web.request.errors{service:orders-service,env:production}.as_count() / sum:trace.web.request.hits{service:orders-service,env:production}.as_count()"
        display_type = "line"
      }
      yaxis { min = "0" max = "100" }
    }
  }

  widget {
    timeseries_definition {
      title = "p50/p95/p99 Latency"
      request {
        q            = "p50:trace.web.request{service:orders-service,env:production}"
        display_type = "line"
        style { palette = "cool" }
      }
      request {
        q            = "p95:trace.web.request{service:orders-service,env:production}"
        display_type = "line"
      }
      request {
        q            = "p99:trace.web.request{service:orders-service,env:production}"
        display_type = "line"
      }
    }
  }
}
```

---

## SLOs

```hcl
resource "datadog_service_level_objective" "orders_availability" {
  name        = "Orders Service Availability"
  type        = "metric"
  description = "99.9% of requests succeed over a rolling 30-day window"

  query {
    numerator   = "sum:trace.web.request.hits{service:orders-service,env:production,!status:error}.as_count()"
    denominator = "sum:trace.web.request.hits{service:orders-service,env:production}.as_count()"
  }

  thresholds {
    timeframe = "30d"
    target    = 99.9
    warning   = 99.95
  }

  tags = ["service:orders-service", "env:production"]
}
```

---

## Synthetic Monitoring

```hcl
resource "datadog_synthetics_test" "orders_api" {
  name      = "Orders API — create order"
  type      = "api"
  subtype   = "http"
  status    = "live"
  locations = ["aws:eu-west-1", "aws:eu-central-1"]
  message   = "Orders API endpoint is failing @slack-platform-alerts"

  request_definition {
    method = "POST"
    url    = "https://api.example.com/orders"
    body   = jsonencode({ productId = "prod-smoke-test", quantity = 1 })
  }

  request_headers = {
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer {{orders-api-smoke-token}}"
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "201"
  }

  assertion {
    type     = "responseTime"
    operator = "lessThan"
    target   = "1000"
  }

  options_list {
    tick_every = 300   # every 5 minutes
  }
}
```

---

## Troubleshooting

| Symptom | Evidence | Fix |
|---------|----------|-----|
| Traces not appearing | `agent status` → APM section | Enable `apm.portEnabled: true`; check `DD_TRACE_AGENT_HOSTNAME` |
| Logs missing trace_id | Log entries lack `dd.trace_id` | Set `logInjection: true` in tracer init |
| No data in monitor | Monitor shows "No Data" | Check metric query resolves in Metrics Explorer first |
| High DDtrace overhead | Latency increase > 5ms | Reduce sampling rate: `DD_TRACE_SAMPLE_RATE=0.1` |
| Pod not sending metrics | Agent shows `0 checks` | Verify pod labels match `datadog.checks` annotations |

---

## Security Baseline

- Store API key and APP key in a Kubernetes Secret or AWS Secrets Manager — never in values files
- Use `DD_API_KEY_SECRET_NAME` to reference secret by name in the Helm chart
- Enable `datadog.logs.containerCollectAll: true` only if log volume is manageable — filter noisy sources
- Redact PII in log pipeline processing rules before ingestion
- Scope APP keys to the minimum permissions needed (Monitors Write, Dashboards Write)

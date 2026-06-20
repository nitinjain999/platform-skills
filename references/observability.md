---
title: Observability
custom_edit_url: null
---

# Observability Reference

Covers the three pillars — logs, metrics, traces — plus alerting, dashboards, load testing, and capacity planning.

---

## Structured Logging

### Principle

Every log line must be parseable by a log aggregator (Loki, CloudWatch Logs Insights, Datadog). Use JSON. Never interpolate variables into the message string.

```js
// ✅ Structured — fully queryable
logger.info({ requestId: req.id, userId: req.user.id, durationMs: elapsed }, "order.created");

// ❌ Unstructured — opaque to queries
logger.info(`Order created for user ${req.user.id} in ${elapsed}ms`);
```

### Node.js — Pino

```js
import pino from "pino";

const logger = pino({
  level: process.env.LOG_LEVEL ?? "info",
  redact: ["req.headers.authorization", "*.password", "*.token"],
});

// Child logger with bound context
const reqLogger = logger.child({ requestId: req.id, service: "orders" });
reqLogger.info({ orderId }, "order.created");
reqLogger.error({ err, orderId }, "order.payment_failed");
```

### Python — structlog

```python
import structlog

log = structlog.get_logger()
log = log.bind(request_id=request_id, service="orders")

log.info("order.created", order_id=order_id, amount_cents=amount)
log.error("order.payment_failed", order_id=order_id, error=str(e))
```

### What NOT to Log

- Passwords, API keys, tokens (`redact` them)
- Full request/response bodies containing PII
- Health check noise at INFO level (use DEBUG)

---

## Prometheus Metrics

### Metric Types

| Type | Use For | Example |
|------|---------|---------|
| `Counter` | Monotonically increasing counts | `http_requests_total` |
| `Gauge` | Values that go up and down | `queue_depth`, `memory_bytes` |
| `Histogram` | Latency distributions (buckets) | `http_request_duration_seconds` |
| `Summary` | Pre-computed percentiles | Avoid — use Histogram instead |

### Node.js — prom-client

```js
import { Counter, Histogram, Gauge, register } from "prom-client";

const httpRequests = new Counter({
  name: "http_requests_total",
  help: "Total HTTP requests by method, route, and status",
  labelNames: ["method", "route", "status"],
});

const httpDuration = new Histogram({
  name: "http_request_duration_seconds",
  help: "HTTP request latency",
  labelNames: ["method", "route"],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5],
});

const queueDepth = new Gauge({
  name: "job_queue_depth",
  help: "Number of jobs waiting in the queue",
  labelNames: ["queue"],
});

// Middleware
app.use((req, res, next) => {
  const route = req.route?.path ?? req.path;
  const end = httpDuration.startTimer({ method: req.method, route });
  res.on("finish", () => {
    httpRequests.inc({ method: req.method, route, status: res.statusCode });
    end();
  });
  next();
});

// Scrape endpoint
app.get("/metrics", async (req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});
```

### Python — prometheus-client

```python
from prometheus_client import Counter, Histogram, start_http_server

http_requests = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "route", "status"],
)

http_duration = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "route"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5],
)

start_http_server(9090)  # expose /metrics
```

### Prometheus Scrape Config

```yaml
scrape_configs:
  - job_name: orders-service
    static_configs:
      - targets: ["orders-service:9090"]
    scrape_interval: 15s
    metrics_path: /metrics
```

---

## OpenTelemetry Tracing

### Node.js

```typescript
import { NodeSDK } from "@opentelemetry/sdk-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { trace, SpanStatusCode } from "@opentelemetry/api";

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({ url: "http://otel-collector:4318/v1/traces" }),
  serviceName: "orders-service",
});
sdk.start();

const tracer = trace.getTracer("orders-service");

async function processOrder(orderId: string) {
  const span = tracer.startSpan("order.process");
  span.setAttribute("order.id", orderId);
  try {
    const result = await db.saveOrder(orderId);
    span.setStatus({ code: SpanStatusCode.OK });
    return result;
  } catch (err) {
    span.recordException(err);
    span.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
    throw err;
  } finally {
    span.end();
  }
}
```

### Python

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace.export import BatchSpanProcessor

provider = TracerProvider()
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(
    endpoint="http://otel-collector:4318/v1/traces"
)))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer("orders-service")

async def process_order(order_id: str):
    with tracer.start_as_current_span("order.process") as span:
        span.set_attribute("order.id", order_id)
        result = await db.save_order(order_id)
        return result
```

---

## Alerting Rules

### RED Method (Request-based services)

- **R**ate — requests per second
- **E**rrors — error rate percentage
- **D**uration — latency percentiles

```yaml
groups:
  - name: orders-service
    rules:
      # Error rate > 5% for 2 minutes
      - alert: HighErrorRate
        expr: |
          rate(http_requests_total{status=~"5..",job="orders-service"}[5m])
          / rate(http_requests_total{job="orders-service"}[5m]) > 0.05
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Error rate {{ $value | humanizePercentage }} on {{ $labels.route }}"
          runbook: "https://wiki.internal/runbooks/orders-high-error-rate"

      # p99 latency > 1s for 5 minutes
      - alert: HighLatency
        expr: |
          histogram_quantile(0.99,
            rate(http_request_duration_seconds_bucket{job="orders-service"}[5m])
          ) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "p99 latency {{ $value | humanizeDuration }} on {{ $labels.route }}"

      # Service down
      - alert: ServiceDown
        expr: up{job="orders-service"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "orders-service is down"
```

### USE Method (Resource-based systems)

- **U**tilization — % time resource is busy
- **S**aturation — queue depth, wait time
- **E**rrors — device-level errors

```yaml
      # CPU saturation
      - alert: HighCPUSaturation
        expr: rate(container_cpu_cfs_throttled_seconds_total[5m]) > 0.25
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "CPU throttling above 25% — consider raising CPU limits or removing them"
```

### Alert Design Rules

- Set `for:` ≥ 1m to avoid flapping on transient spikes
- Every alert needs a `runbook` annotation
- Page on symptoms (error rate, latency), not causes (CPU %)
- Derive SLO burn-rate alerts from error budget, not raw thresholds

---

## Grafana Dashboards

### RED Dashboard Template

```json
{
  "title": "Service RED — orders-service",
  "panels": [
    {
      "title": "Request Rate",
      "type": "timeseries",
      "targets": [{"expr": "rate(http_requests_total{job=\"orders-service\"}[5m])"}]
    },
    {
      "title": "Error Rate %",
      "type": "timeseries",
      "targets": [{"expr": "rate(http_requests_total{job=\"orders-service\",status=~\"5..\"}[5m]) / rate(http_requests_total{job=\"orders-service\"}[5m]) * 100"}]
    },
    {
      "title": "p50 / p95 / p99 Latency",
      "type": "timeseries",
      "targets": [
        {"expr": "histogram_quantile(0.50, rate(http_request_duration_seconds_bucket{job=\"orders-service\"}[5m]))", "legendFormat": "p50"},
        {"expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job=\"orders-service\"}[5m]))", "legendFormat": "p95"},
        {"expr": "histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{job=\"orders-service\"}[5m]))", "legendFormat": "p99"}
      ]
    }
  ]
}
```

---

## Load Testing — k6

### Basic Ramp Test

```js
import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "1m", target: 50 },   // ramp up
    { duration: "5m", target: 50 },   // steady state
    { duration: "1m", target: 0 },    // ramp down
  ],
  thresholds: {
    http_req_duration: ["p(95)<500"],  // 95% of requests < 500ms
    http_req_failed:   ["rate<0.01"],  // < 1% error rate
  },
};

export default function () {
  const res = http.post(
    "https://api.example.com/orders",
    JSON.stringify({ productId: "prod-123", quantity: 1 }),
    { headers: { "Content-Type": "application/json" } }
  );
  check(res, {
    "status is 201": (r) => r.status === 201,
    "response time < 500ms": (r) => r.timings.duration < 500,
  });
  sleep(1);
}
```

### Run

```bash
k6 run --out json=results.json load-test.js
```

---

## Capacity Planning

### Back-of-Envelope Formula

```
Required replicas = ceil(
  (peak_rps × avg_latency_s) / target_concurrency_per_pod
)
```

Example: 1000 rps × 0.1s latency / 20 concurrent connections = 5 replicas minimum. Add 50% headroom → 8 replicas.

### HPA Target Utilisation

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: orders-service
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: orders-service
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60   # scale before saturation
    - type: Resource
      resource:
        name: memory
        target:
          type: AverageValue
          averageValue: 400Mi
```

### Resource Budgeting

| Metric | Target | Alert Threshold |
|--------|--------|----------------|
| CPU utilisation | < 60% | > 80% |
| Memory utilisation | < 70% | > 85% |
| Error rate | < 0.1% | > 1% |
| p99 latency | < 500ms | > 1s |
| Disk utilisation | < 70% | > 85% |

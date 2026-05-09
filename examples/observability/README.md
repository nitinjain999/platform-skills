Status: Stable

# Observability Examples

Production-ready alerting rules using the RED method (Request rate, Error rate, Duration).

## Examples

| Example | Tool | Description |
|---------|------|-------------|
| [prometheus-alerts/orders-service.yaml](prometheus-alerts/) | Prometheus | RED method alerting rules for a production service |

## Quick Start

```bash
# Install promtool (included with Prometheus binary)
# https://prometheus.io/download/

# Validate alerting rules syntax and expressions
cd prometheus-alerts
promtool check rules orders-service.yaml

# Test alert firing logic
promtool test rules orders-service.yaml
```

## What the Alerts Cover

| Alert | Threshold | Severity | When it fires |
|-------|-----------|----------|--------------|
| `HighErrorRate` | > 5% errors over 5m | critical | Error rate exceeds SLO budget |
| `HighLatencyP99` | > 1s p99 over 5m | warning | Tail latency degraded |
| `LowRequestRate` | < 0.1 req/s over 10m | warning | Service may be down or receiving no traffic |

## RED Method Applied

```yaml
# Request rate — is traffic flowing?
expr: rate(http_requests_total{job="orders-service"}[5m])

# Error rate — are requests succeeding?
expr: |
  rate(http_requests_total{job="orders-service",status=~"5.."}[5m])
  / rate(http_requests_total{job="orders-service"}[5m])

# Duration (p99) — how slow are requests?
expr: histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{job="orders-service"}[5m]))
```

## Instrument Your Service

To use these alerts, expose the following Prometheus metrics from your service:

```javascript
// Node.js — prom-client
import { Counter, Histogram } from "prom-client";

const httpRequests = new Counter({
  name: "http_requests_total",
  help: "Total HTTP requests",
  labelNames: ["method", "path", "status"],
});

const httpDuration = new Histogram({
  name: "http_request_duration_seconds",
  help: "HTTP request duration",
  labelNames: ["method", "path"],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
});
```

```python
# Python — prometheus-client
from prometheus_client import Counter, Histogram

http_requests = Counter("http_requests_total", "Total HTTP requests", ["method", "path", "status"])
http_duration = Histogram("http_request_duration_seconds", "HTTP request duration", ["method", "path"])
```

## Integrate with Grafana

```yaml
# Prometheus scrape config
scrape_configs:
  - job_name: orders-service
    static_configs:
      - targets: ["orders-service:9090"]
```

Load `prometheus-alerts/orders-service.yaml` into Alertmanager and point your Grafana datasource at Prometheus to visualise these metrics.

## Checklist

- [ ] Service exposes `/metrics` on a dedicated port (not the main API port)
- [ ] Metrics follow naming convention: `<namespace>_<metric>_<unit>_total` / `_seconds` / `_bytes`
- [ ] All metrics have `job` and `env` labels for alert routing
- [ ] Alert `for` duration is long enough to avoid flapping (5m for critical, 10m for warning)
- [ ] Alertmanager routes critical alerts to PagerDuty, warnings to Slack

## See Also

- [references/observability.md](../../references/observability.md) — structured logging, Prometheus metrics, OpenTelemetry tracing, Grafana dashboards, k6 load testing, capacity planning
- `/platform-skills:observability` — instrument services, build dashboards, write alerts, run load tests, plan capacity

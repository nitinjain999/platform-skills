Status: Stable

# Observability Examples

Production-ready instrumentation, dashboards, alerting, and load test configurations.

## Examples

| Example | Tool | Description |
|---------|------|-------------|
| [node-service/](node-service/) | Pino + prom-client + OpenTelemetry | Fully instrumented Node.js service |
| [prometheus-alerts/](prometheus-alerts/) | Prometheus | RED method alerting rules |
| [grafana-dashboard/](grafana-dashboard/) | Grafana | RED dashboard JSON |
| [k6-load-test/](k6-load-test/) | k6 | Ramp load test with SLO thresholds |

## Quick Start

```bash
# Run instrumented Node.js service locally
cd node-service
npm install && npm start
# Metrics: http://localhost:9090/metrics
# Traces: sent to OTEL_EXPORTER_OTLP_ENDPOINT (default: http://localhost:4318)

# Run load test
cd k6-load-test
k6 run load-test.js
```

## See Also

- [references/observability.md](../../references/observability.md) — logging, metrics, tracing, alerting, capacity planning
- `/platform-skills:observability` — instrument, dashboard, alert, load test, or plan capacity

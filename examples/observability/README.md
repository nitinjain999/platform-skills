Status: Stable

# Observability Examples

Production-ready instrumentation, dashboards, alerting, and load test configurations.

## Examples

| Example | Tool | Description |
|---------|------|-------------|
| [prometheus-alerts/](prometheus-alerts/) | Prometheus | RED method alerting rules |

## Quick Start

```bash
# Validate Prometheus alerting rules
cd prometheus-alerts
promtool check rules *.yaml
```

## See Also

- [references/observability.md](../../references/observability.md) — logging, metrics, tracing, alerting, capacity planning
- `/platform-skills:observability` — instrument, dashboard, alert, load test, or plan capacity

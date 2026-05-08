---
name: observability
description: Instrument services with structured logging, Prometheus metrics, and OpenTelemetry tracing. Build Grafana dashboards, write Prometheus alerting rules, run k6 load tests, and plan infrastructure capacity.
argument-hint: "[instrument|dashboard|alert|loadtest|capacity] [service description]"
---

Set up or improve observability for a service or platform component.

## Mode: instrument

Add the three pillars — logs, metrics, traces — to a service.

Steps:
1. Ask for: language/framework, existing logging library (if any), metrics backend (Prometheus / Datadog / CloudWatch), tracing backend (Jaeger / Tempo / OTLP)
2. Add structured JSON logging with correlation IDs (Pino for Node.js, structlog for Python)
3. Instrument RED metrics: `http_requests_total` counter, `http_request_duration_seconds` histogram, per route and status
4. Add OpenTelemetry tracing with span attributes on critical paths
5. Expose `/metrics` scrape endpoint (Prometheus) or configure push exporter
6. Add `/healthz` and `/readyz` health check endpoints
7. Document what NOT to log (passwords, tokens, PII)

Reference: `references/observability.md` → Structured Logging, Prometheus Metrics, OpenTelemetry Tracing

## Mode: dashboard

Create a Grafana dashboard for a service.

Steps:
1. Choose method: RED (request-based services) or USE (resource-based infrastructure)
2. Define panels: request rate, error rate %, p50/p95/p99 latency, active connections, queue depth
3. Set meaningful Y-axis units (req/s, ms, %)
4. Add threshold lines at SLO boundaries
5. Configure template variables for environment and service filtering

Reference: `references/observability.md` → Grafana Dashboards

## Mode: alert

Write Prometheus alerting rules for a service.

Steps:
1. Identify SLIs: error rate, latency percentiles, availability
2. Write alert expressions using `rate()` over 5m windows
3. Set `for:` duration ≥ 1m to suppress transient noise
4. Add `severity` label (critical / warning) and `runbook` annotation to every alert
5. Validate: no alert fires on healthy baseline, alert fires on injected fault

Alert design rules:
- Page on symptoms (error rate, latency), not causes (CPU %)
- Every alert needs a runbook URL
- Derive SLO burn-rate alerts from error budget, not raw thresholds

Reference: `references/observability.md` → Alerting Rules

## Mode: loadtest

Write and run a k6 load test.

Steps:
1. Ask for: target endpoint, expected peak RPS, SLO thresholds (p95 latency, error rate)
2. Write ramp-up → steady-state → ramp-down stages
3. Set `thresholds` matching the SLO
4. Add `check()` assertions on status code and response time
5. Run: `k6 run --out json=results.json load-test.js`
6. Interpret results: p95/p99 latency, error rate, throughput achieved vs. thresholds

Reference: `references/observability.md` → Load Testing

## Mode: capacity

Estimate resource requirements and HPA configuration for a service.

Steps:
1. Gather: expected peak RPS, measured p99 latency, memory per pod at current load
2. Apply formula: `replicas = ceil((peak_rps × avg_latency_s) / target_concurrency_per_pod)`
3. Add 50% headroom for spikes
4. Generate HPA manifest with CPU utilisation target ≤ 60%
5. Set resource requests to measured baseline + 20%; set memory limit; omit CPU limit unless throttling is acceptable
6. Define min/max replica bounds

Reference: `references/observability.md` → Capacity Planning

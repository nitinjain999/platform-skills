---
name: observability
description: Instrument services with structured logging, Prometheus metrics, and OpenTelemetry tracing. Build Grafana dashboards, write Prometheus alerting rules, run k6 load tests, and plan infrastructure capacity.
argument-hint: "[instrument|dashboard|alert|loadtest|capacity] [service description]"
---

Set up or improve observability for a service or platform component.

---

## Interactive Wizard (fires when no arguments are provided)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. instrument — add structured logs, Prometheus metrics, and OTel tracing to a service
  2. dashboard  — create a Grafana RED/USE dashboard for a service
  3. alert      — write Prometheus alerting rules for a service
  4. slo        — define SLIs, error budgets, and SLO burn-rate alerts
  5. loadtest   — write and run a k6 load test
  6. capacity   — estimate resource requirements and HPA configuration

Enter 1–6 or mode name:
```

**Q2 — Context** (after mode selected):
- **instrument**: `What language/framework and which metrics/tracing backend (Prometheus, Datadog, Jaeger, Tempo)?`
- **dashboard**: `Service name and which signal to lead with — request-based (RED) or resource-based (USE)?`
- **alert**: `Service name and what SLIs matter most — error rate, latency, availability?`
- **slo**: `Service name, expected availability target (e.g. 99.9%), and current p95 latency baseline:`
- **loadtest**: `Target endpoint, expected peak RPS, and SLO thresholds (p95 latency, max error rate):`
- **capacity**: `Expected peak RPS, measured p99 latency at current load, and memory per pod:`

---

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

→ **Next:** Run `/platform-skills:observability alert` to write alerting rules for the metrics just added, then `/platform-skills:observability slo` to wrap them in an error budget.

## Mode: dashboard

Create a Grafana dashboard for a service.

Steps:
1. Choose method: RED (request-based services) or USE (resource-based infrastructure)
2. Define panels: request rate, error rate %, p50/p95/p99 latency, active connections, queue depth
3. Set meaningful Y-axis units (req/s, ms, %)
4. Add threshold lines at SLO boundaries
5. Configure template variables for environment and service filtering

Reference: `references/observability.md` → Grafana Dashboards

→ **Next:** Run `/platform-skills:observability slo` to add SLO burn-rate alerts and an error budget panel to this dashboard.

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

→ **Next:** Run `/platform-skills:observability slo` to promote these symptom alerts to proper SLO burn-rate alerts backed by an error budget.

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

→ **Next:** After sizing, run `/platform-skills:observability loadtest` to validate the HPA triggers correctly under synthetic load.

---

## Mode: slo

Define SLIs, set error budgets, and generate SLO burn-rate alerts from first principles.

Steps:
1. **Define SLIs** — identify what "good" looks like for this service:
   - Availability: `sum(rate(http_requests_total{status!~"5.."}[5m])) / sum(rate(http_requests_total[5m]))`
   - Latency: `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) < 0.3`
   - Choose one primary SLI per service; add a secondary only if the first doesn't capture the user journey

2. **Set the SLO target** — start conservative, tighten over time:
   ```
   SLO:           99.9% availability over a 30-day rolling window
   Error budget:  0.1% = 43.2 minutes per 30 days
   ```

3. **Generate burn-rate alerts** — multiwindow, multi-burn-rate (Google SRE Book approach):
   ```yaml
   # Fast burn — consumes 5% of monthly budget in 1h → page immediately
   - alert: SLOFastBurn
     expr: |
       (
         rate(http_requests_total{status=~"5.."}[1h])
         / rate(http_requests_total[1h])
       ) > (14.4 * 0.001)   # 14.4× burn rate exhausts budget in ~2 days
     for: 2m
     labels:
       severity: critical
     annotations:
       summary: "Fast error budget burn on {{ $labels.service }}"
       runbook: "https://runbooks.internal/slo-fast-burn"

   # Slow burn — consumes 10% of monthly budget in 6h → ticket
   - alert: SLOSlowBurn
     expr: |
       (
         rate(http_requests_total{status=~"5.."}[6h])
         / rate(http_requests_total[6h])
       ) > (6 * 0.001)      # 6× burn rate exhausts budget in ~5 days
     for: 15m
     labels:
       severity: warning
     annotations:
       summary: "Slow error budget burn on {{ $labels.service }}"
       runbook: "https://runbooks.internal/slo-slow-burn"
   ```

4. **Track remaining error budget** — add to the Grafana dashboard:
   ```promql
   # Error budget remaining (%) over 30d
   1 - (
     sum(increase(http_requests_total{status=~"5.."}[30d]))
     / sum(increase(http_requests_total[30d]))
   ) / 0.001   # divide by error budget fraction (1 - SLO target)
   ```

5. **Error budget policy** — state in writing what happens when the budget is depleted:
   - >50% remaining → normal feature velocity
   - 10–50% remaining → reliability improvements prioritised alongside features
   - <10% remaining → feature freeze; only reliability work until budget recovers

Key rules:
- Alert on burn rate, not on raw error count — burn rate is predictive
- The `for:` on fast burn should be short (1–2m); slow burn needs longer (10–15m)
- Latency SLOs need histogram buckets aligned to the SLO threshold at chart creation time — you cannot retroactively add buckets

→ **Next:** Run `/platform-skills:observability alert` to add symptom-based alerts alongside SLO burn-rate alerts.

---

## Common mistakes

- **Alerting on CPU% or memory%** — these are causes, not symptoms. Alert on error rate and latency; let CPU/memory be dashboard panels only
- **Missing `for:` duration** — without it, a single bad scrape triggers a page. Minimum 1m for slow alerts, 2m for fast SLO burn
- **Not defining SLOs before writing alerts** — without an SLO, you don't know what threshold to alert at. Define the SLO first (`slo` mode), then write alerts
- **Histogram bucket boundaries misaligned with SLO** — if your SLO is p95 < 300ms and you have no bucket at 0.3s, `histogram_quantile` interpolates inaccurately. Set `le` values at 0.1, 0.25, 0.3, 0.5, 1.0, 2.5
- **Labelling with high-cardinality dimensions** — never use `user_id`, `session_id`, or `request_id` as Prometheus label values. Cardinality explodes memory usage
- **Alert fatigue from symptom + cause alerts** — if you alert on both "error rate high" and "database connection pool exhausted", both fire simultaneously for the same incident. Alert on the symptom; include cause investigation in the runbook

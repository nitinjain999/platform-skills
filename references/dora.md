---
title: DORA Metrics
custom_edit_url: null
---

# DORA Metrics

DORA (DevOps Research and Assessment) metrics are the four evidence-based indicators of software delivery performance: Deployment Frequency, Lead Time for Changes, Change Failure Rate, and Mean Time to Restore (MTTR). Developed through multi-year research by the DORA team at Google, they are the industry standard for measuring the speed and stability of a delivery pipeline — teams that score high across all four consistently outperform peers on reliability, availability, and business outcomes. Tracking them in production (never staging) with real incident data is the only way to get a signal that is actionable rather than cosmetic.

---

## The Four Metrics

| Metric | Definition | What counts | What does NOT count |
|---|---|---|---|
| Deployment Frequency | How often code is deployed to production | Every successful deploy to production environment | Deploys to staging/dev, failed deploys |
| Lead Time for Changes | Time from first commit to production deploy | First commit timestamp → deploy timestamp | PR review time alone, deploy to non-prod |
| Change Failure Rate | % of deploys causing a production incident | Incidents opened within 1h of deploy | Incidents from infra failures unrelated to deploy |
| MTTR | Time from incident detected to service restored | Incident open → incident resolved | Time to deploy the fix (already in Lead Time) |

---

## DORA Performance Bands

2023 State of DevOps research classification:

| Metric | Elite | High | Medium | Low |
|---|---|---|---|---|
| Deployment Frequency | Multiple/day | Weekly–monthly | Monthly–6mo | <6mo |
| Lead Time | <1 hour | 1 day–1 week | 1 week–1 month | >1 month |
| Change Failure Rate | <5% | 5–10% | 10–15% | >15% |
| MTTR | <1 hour | <1 day | 1 day–1 week | >1 week |

Teams that achieve Elite or High across all four metrics are significantly more likely to meet reliability and business targets. Optimizing one metric at the expense of another — for example, deploying more frequently while ignoring change failure rate — does not improve overall delivery performance.

---

## Open-Source Instrumentation Pattern

The recommended open-source approach uses GitHub Actions to emit raw deployment events to a Prometheus Pushgateway. Recording rules then derive the four DORA metrics from the raw event streams.

### Deploy event emission

Add this step to your production deploy workflow, after the deploy succeeds:

```yaml
- name: Record deployment metric
  run: |
    REPO="${{ github.repository }}"
    cat <<EOF | curl --data-binary @- http://pushgateway:9091/metrics/job/dora/instance/${REPO//\//_}
    # TYPE dora_deployment_timestamp gauge
    dora_deployment_timestamp{repo="${REPO}",env="production"} $(date +%s)
    EOF
```

### Lead time emission

Lead time requires knowing the first commit timestamp for the batch being deployed. Emit this from your CI pipeline at deploy time:

```yaml
- name: Record lead time metric
  run: |
    REPO="${{ github.repository }}"
    FIRST_COMMIT_TS=$(git log --reverse --format="%ct" origin/main..HEAD | head -1)
    DEPLOY_TS=$(date +%s)
    LEAD_TIME=$((DEPLOY_TS - FIRST_COMMIT_TS))
    cat <<EOF | curl --data-binary @- http://pushgateway:9091/metrics/job/dora/instance/${REPO//\//_}
    # TYPE dora_lead_time_seconds gauge
    dora_lead_time_seconds{repo="${REPO}",env="production"} ${LEAD_TIME}
    EOF
```

Recording rules derive Deployment Frequency and Lead Time from these raw deployment events. MTTR derives from incident webhook events — see Section 5.

---

## Prometheus Recording Rules

All four DORA metrics expressed as Prometheus recording rules over the raw event gauges:

```yaml
groups:
  - name: dora
    rules:
      # Deployment frequency (deploys per day, 30d rolling)
      # changes() counts how many times the timestamp gauge changed value — one change per deploy push.
      - record: dora:deployment_frequency:rate30d
        expr: changes(dora_deployment_timestamp{env="production"}[30d]) / 30

      # Lead time (p50 seconds from first commit to deploy, 30d rolling)
      - record: dora:lead_time_seconds:p50
        expr: quantile_over_time(0.5, dora_lead_time_seconds{env="production"}[30d])

      # Change failure rate (%)
      # changes() on each gauge counts distinct incident/deploy events, not scrape samples.
      - record: dora:change_failure_rate:ratio30d
        expr: |
          changes(dora_incident_caused_by_deploy{env="production"}[30d])
          / changes(dora_deployment_timestamp{env="production"}[30d]) * 100

      # MTTR (p50 seconds from incident open to close, 30d rolling)
      - record: dora:mttr_seconds:p50
        expr: quantile_over_time(0.5, dora_incident_duration_seconds{env="production"}[30d])
```

**Notes:**
- `dora_deployment_timestamp` is the gauge pushed per successful production deploy.
- `dora_lead_time_seconds` is the gauge pushed per deploy containing the elapsed time since first commit.
- `dora_incident_caused_by_deploy` is a gauge set to 1 for incidents attributed to a deploy (see Section 5).
- `dora_incident_duration_seconds` is a gauge set to the resolved − triggered delta for each incident.

For alerting, create Prometheus alerting rules that fire when `dora:change_failure_rate:ratio30d` exceeds your band threshold or when `dora:mttr_seconds:p50` crosses the Elite/High boundary for your SLO.

---

## Incident Source Integration (MTTR)

MTTR requires a live incident feed. Two supported sources: **PagerDuty** and **OpsGenie**. Both use the same webhook → GitHub Actions → Pushgateway pattern.

### PagerDuty

Configure a PagerDuty webhook (v3) to deliver `incident.triggered` and `incident.resolved` events to a GitHub Actions workflow dispatch endpoint or an intermediate relay.

Relevant fields from the PagerDuty webhook payload:

```yaml
# incident.triggered
event:
  event_type: incident.triggered
  data:
    id: "Q1W2E3R4T5Y6U7"
    created_at: "2024-03-15T14:23:00Z"
    service:
      name: "payments-api"

# incident.resolved
event:
  event_type: incident.resolved
  data:
    id: "Q1W2E3R4T5Y6U7"
    resolved_at: "2024-03-15T14:51:00Z"
```

### OpsGenie

Configure an OpsGenie webhook integration to deliver `alert.created` and `alert.closed` events. The payload structure differs slightly but contains equivalent `createdAt` and `closedAt` timestamps.

### GitHub Actions step — pushing incident metrics to Pushgateway

```yaml
- name: Push MTTR incident metric
  if: ${{ github.event.action == 'resolved' }}
  env:
    INCIDENT_ID: ${{ github.event.client_payload.incident_id }}
    TRIGGERED_AT: ${{ github.event.client_payload.triggered_at_unix }}
    RESOLVED_AT: ${{ github.event.client_payload.resolved_at_unix }}
    CAUSED_BY_DEPLOY: ${{ github.event.client_payload.caused_by_deploy }}
  run: |
    DURATION=$((RESOLVED_AT - TRIGGERED_AT))
    cat <<EOF | curl --data-binary @- http://pushgateway:9091/metrics/job/dora/instance/incident-${INCIDENT_ID}
    # TYPE dora_incident_duration_seconds gauge
    dora_incident_duration_seconds{id="${INCIDENT_ID}"} ${DURATION}
    # TYPE dora_incident_caused_by_deploy gauge
    dora_incident_caused_by_deploy{id="${INCIDENT_ID}"} ${CAUSED_BY_DEPLOY}
    EOF
```

**Critical rule**: Without incident data from an alerting platform (PagerDuty, OpsGenie, or equivalent), MTTR cannot be calculated. Do not estimate MTTR from deployment timestamps alone — that measures deploy cadence, not recovery time.

---

## SaaS Decision Matrix

| Tool | Best for | Limitation |
|---|---|---|
| Sleuth | GitHub-native, easy setup | No custom metric sources |
| LinearB | Engineering manager reporting | Less Kubernetes-aware |
| Cortex | Combines DORA + resource metrics | More setup cost |
| Open-source | Full control, Prometheus ecosystem | More instrumentation work |

**Recommendation:** choose open-source instrumentation if Prometheus already exists in the stack — the recording rules in Section 4 give you full control and integrate with existing dashboards and alerting. Choose a SaaS tool if the team has no observability platform and needs DORA visibility in days rather than weeks.

---

## Anti-Pattern Detection

### 1. Counting commits instead of deploys

**Pattern:** Deployment Frequency is measured by commit count or merge count rather than by actual production deploys.

**Why it distorts the metric:** A commit that never reaches production is invisible to users. Counting commits inflates frequency and masks long batching delays.

**What to do instead:** Emit `dora_deployment_timestamp` only on a confirmed successful deploy to the production environment (e.g., after `kubectl rollout status` or a health-check passes).

---

### 2. Counting all alerts as failures

**Pattern:** Every PagerDuty alert or monitoring alert is attributed to a deploy, regardless of whether it was caused by the deploy.

**Why it distorts the metric:** Change Failure Rate becomes meaningless noise. Infrastructure failures, third-party outages, and mis-configured thresholds inflate the ratio.

**What to do instead:** Only count customer-impacting incidents that are explicitly linked to a deploy — use a `caused_by_deploy` flag set by the on-call engineer during triage, not automatic attribution.

---

### 3. Not tracking partial outages

**Pattern:** MTTR only counts full outages where the service was completely unavailable.

**Why it distorts the metric:** Degraded service (high error rate, elevated latency, partial region failure) is underreported. MTTR appears better than it is.

**What to do instead:** Include degraded-service incidents in the incident feed. Define "incident" as any event that breaches an SLO or causes customer-visible impact, not only full downtime.

---

### 4. Measuring staging instead of production

**Pattern:** All four metrics are calculated against the staging or pre-production environment because it is easier to instrument.

**Why it distorts the metric:** Staging deploy cadence and staging incident rates have no bearing on production reliability. Every metric is wrong.

**What to do instead:** Label all metrics with `env="production"` and filter recording rules to that label. Staging instrumentation is acceptable for pipeline testing but must never feed the DORA dashboard.

---

### 5. Lead time from PR open not first commit

**Pattern:** Lead Time for Changes is measured from the time a pull request was opened rather than from the first commit in the branch.

**Why it distorts the metric:** Work done in the branch before the PR is opened is invisible. Long-lived feature branches with pre-PR commit work will show artificially short lead times.

**What to do instead:** Use the timestamp of the first commit in the branch (relative to the base branch) as the lead time start. In GitHub Actions: `git log --reverse --format="%ct" origin/main..HEAD | head -1`.

---

## Relationship to Chaos Engineering

A sustained high Change Failure Rate (above 10%) is a signal to run targeted chaos experiments. The fault class in the incidents should guide experiment design:

- Repeated database connection failures → inject latency or partition between app and database
- Memory pressure causing OOM kills → inject memory stress at peak load
- Dependency timeouts → inject slow responses from upstream services

The goal is to reproduce the fault class in a controlled experiment, confirm the blast radius, and validate the fix before the next deploy.

Reference `references/chaos.md` → GameDay workflow for the full experiment design and execution process.

---

## Platform Rules

Rules for agents and engineers instrumenting or reporting DORA metrics in this platform:

- **Always use production deploys only** — never include staging, dev, or canary-only deploys in any DORA metric calculation; label all Pushgateway pushes with `env="production"` and filter recording rules to that label.
- **Always require an incident source for MTTR** — connect PagerDuty or OpsGenie before publishing an MTTR number; never estimate MTTR from deploy timestamps or synthetic signals.
- **Flag 0% change failure rate as likely misconfiguration** — a zero CFR over any meaningful window almost always means incident attribution is broken, not that every deploy succeeded; verify the incident webhook pipeline end-to-end before trusting the number.
- **Use first commit timestamp for lead time** — not PR open timestamp, not merge timestamp; emit `dora_lead_time_seconds` from the deploy workflow using `git log --reverse` against the base branch.
- **Treat DORA bands as a diagnostic tool, not a target** — optimizing the number by narrowing measurement scope (e.g., counting only hotfixes as "deploys") defeats the purpose; the metrics are useful only when they reflect the full production delivery process.

---
name: dora
description: Measure, benchmark, instrument, and debug DORA metrics (Deployment Frequency, Lead Time for Changes, Change Failure Rate, MTTR) for production engineering teams. Covers GitHub Actions instrumentation, Prometheus recording rules, Grafana dashboards, incident source integration, SaaS tool selection, and anti-pattern detection. Use when asked to "instrument DORA metrics", "benchmark our deployment frequency", "why is my MTTR data missing", or "generate a DORA dashboard".
argument-hint: "[instrument|dashboard|benchmark|debug] [description or file path]"
---

Measure, benchmark, and instrument DORA metrics for production engineering teams.

## Mode: instrument

Add DORA event emission to a GitHub Actions workflow.

Steps:
1. Identify which events to capture:
   - **Deploy event**: triggered on successful deployment to a target environment
   - **Incident open event**: triggered by PagerDuty/OpsGenie webhook when an incident is created
   - **Incident close event**: triggered when the incident is resolved

2. Detect: does a Prometheus Pushgateway exist in the stack? If not, it must be deployed before instrumentation can work:
   ```bash
   kubectl get svc -A | grep pushgateway
   ```
   If absent, deploy via Helm before proceeding:
   ```bash
   helm upgrade --install prometheus-pushgateway prometheus-community/prometheus-pushgateway \
     --namespace monitoring \
     --create-namespace
   ```

3. Generate GitHub Actions steps for each event type:
   - **Deploy event**: push `dora_deployment_timestamp` and `dora_lead_time_seconds` to Pushgateway
   - **Incident triggered** (PagerDuty/OpsGenie webhook): push `dora_incident_start_timestamp`
   - **Incident resolved**: push `dora_incident_duration_seconds` and `dora_incident_caused_by_deploy`

4. Output: exact YAML to append to the existing workflow, using the Pushgateway job name convention `job/dora/instance/<repo-owner_repo-name>`. Sanitize `owner/repo` → `owner_repo` to avoid breaking Pushgateway path segments.

   Example deploy event step:
   ```yaml
   - name: Push DORA deploy metrics
     if: success()
     env:
       PUSHGATEWAY_URL: ${{ secrets.PUSHGATEWAY_URL }}
       REPO: ${{ github.repository }}
     run: |
       DEPLOY_TS=$(date +%s)
       # Lead time from first commit in this batch — requires fetch-depth: 0 in checkout.
       FIRST_COMMIT_TS=$(git log --reverse --format="%ct" origin/main..HEAD | head -1)
       FIRST_COMMIT_TS=${FIRST_COMMIT_TS:-$DEPLOY_TS}
       LEAD_TIME=$((DEPLOY_TS - FIRST_COMMIT_TS))
       INSTANCE="${REPO//\//_}"
       cat <<EOF | curl --data-binary @- "${PUSHGATEWAY_URL}/metrics/job/dora/instance/${INSTANCE}"
       # TYPE dora_deployment_timestamp gauge
       dora_deployment_timestamp{repo="${REPO}",env="production"} ${DEPLOY_TS}
       # TYPE dora_lead_time_seconds gauge
       dora_lead_time_seconds{repo="${REPO}",env="production"} ${LEAD_TIME}
       EOF
   ```

5. Warn: Change Failure Rate requires incident source integration — a rate of 0% without incident data is a configuration gap, not a real metric. Never report 0% CFR without confirmed incident source connectivity.

**Validation:**
```bash
# Confirm Pushgateway received the metric
curl -s http://pushgateway:9091/metrics | grep dora_deployment_timestamp

# Confirm Prometheus scraped it (allow up to 1 scrape interval, default 15s)
curl -s 'http://prometheus:9090/api/v1/query?query=dora_deployment_timestamp' \
  | jq '.data.result[0].value[1] // "not yet scraped — wait 15s and retry"'
```

Reference: `references/dora.md` → Open-source instrumentation pattern

## Mode: dashboard

Generate a Grafana dashboard for all four DORA metrics.

Steps:
1. Confirm the four recording rules are deployed before building the dashboard:
   - `dora:deployment_frequency:rate30d`
   - `dora:lead_time_seconds:p50`
   - `dora:change_failure_rate:ratio30d`
   - `dora:mttr_seconds:p50`

   Verify with:
   ```bash
   curl -s 'http://prometheus:9090/api/v1/query?query=dora:deployment_frequency:rate30d' | jq '.data.result[0].value[1] // "no data"'
   ```
   If any query returns no data, check the recording rule deployment — see `references/dora.md` for the full rule set.

2. Dashboard structure: four panels arranged in a 2×2 grid, one per DORA metric:
   - **Panel 1 — Deployment Frequency**: stat + time-series, unit: deploys/day
   - **Panel 2 — Lead Time for Changes**: stat + time-series, unit: hours (p50)
   - **Panel 3 — Change Failure Rate**: stat + time-series, unit: percentage
   - **Panel 4 — MTTR**: stat + time-series, unit: hours (p50)

   Each panel includes DORA performance band overlays as threshold regions (Elite/High/Medium/Low). A time range selector provides 30/60/90 day views.

3. Import the complete dashboard JSON from `examples/dora/grafana-dashboard.json`:
   ```bash
   # Import via Grafana API
   curl -s -X POST http://grafana:3000/api/dashboards/import \
     -H "Content-Type: application/json" \
     -d @examples/dora/grafana-dashboard.json
   ```

4. Threshold values for each performance tier are embedded directly in the panel JSON as threshold bands. Update them in the panel `thresholds` field if your organisation uses different band definitions.

Reference: `references/dora.md` → DORA performance bands

## Mode: benchmark

Classify current metric values against DORA performance bands.

Steps:
1. Accept current metric values — either provided directly or queried from Prometheus:
   ```bash
   # Query current values
   curl -s 'http://prometheus:9090/api/v1/query?query=dora:deployment_frequency:rate30d' | jq '.data.result[0].value[1] // "no data"'
   curl -s 'http://prometheus:9090/api/v1/query?query=dora:lead_time_seconds:p50' | jq '.data.result[0].value[1] // "no data"'
   curl -s 'http://prometheus:9090/api/v1/query?query=dora:change_failure_rate:ratio30d' | jq '.data.result[0].value[1] // "no data"'
   curl -s 'http://prometheus:9090/api/v1/query?query=dora:mttr_seconds:p50' | jq '.data.result[0].value[1] // "no data"'
   ```

2. Map each metric to Elite / High / Medium / Low using the 2023 DORA performance bands:

   | Metric | Elite | High | Medium | Low |
   |---|---|---|---|---|
   | Deployment Frequency | Multiple/day | Weekly–monthly | Monthly–6 months | Less than 6 months |
   | Lead Time for Changes | < 1 hour | 1 day – 1 week | 1 week – 1 month | > 1 month |
   | Change Failure Rate | < 5% | 5–10% | 10–15% | > 15% |
   | MTTR | < 1 hour | < 1 day | 1 day – 1 week | > 1 week |

3. Identify the weakest metric — the one furthest from Elite — as the highest-leverage improvement target.

4. Suggest the most impactful improvement for that specific metric:
   - Low Deployment Frequency → reduce batch size, increase CI automation coverage
   - High Lead Time → eliminate manual approval gates, parallelize test stages
   - High Change Failure Rate → add pre-deploy smoke tests, feature flag risky changes
   - High MTTR → improve alerting signal-to-noise, add runbook links to alerts

5. Output: tier table + one-sentence recommendation per metric.

Reference: `references/dora.md` → DORA performance bands

## Mode: debug

Diagnose gaps in DORA metric data.

Steps:
1. **Missing deployment events**
   - Check: does the workflow step run on the correct trigger (`on: push` to main/release branch)?
     ```bash
     grep -A5 '^on:' .github/workflows/*.yaml
     ```
   - Check: can the runner reach the Pushgateway?
     ```bash
     curl http://pushgateway:9091/-/healthy
     ```
   - Check: is the Pushgateway scrape target present in Prometheus?
     ```bash
     curl -s http://prometheus:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "pushgateway")'
     ```

2. **Missing MTTR** (or stuck at 0)
   - Check: is the PagerDuty/OpsGenie webhook configured to send to the incident listener?
   - Check: does the webhook payload include both incident start and end timestamps?
   - Check: is the GitHub Actions workflow triggered by `repository_dispatch` events for incident lifecycle?
     ```bash
     grep -r 'repository_dispatch' .github/workflows/
     ```

3. **Change failure rate is exactly 0%**
   - Flag as anti-pattern: a CFR of 0% without confirmed incident source integration is a configuration gap, not a real measurement.
   - Check: is any incident source (PagerDuty, OpsGenie, Jira) connected and sending events?
   - Do not accept 0% CFR without evidence that the incident source is emitting resolved incident events.

4. **Metrics stop at a specific date**
   - Check: Pushgateway retention — metrics expire after the configured push interval if not refreshed:
     ```bash
     kubectl describe pod -n monitoring -l app=prometheus-pushgateway | grep -i retention
     ```
   - Check: Prometheus scrape config still includes the Pushgateway target after any config reload.
   - Check: was the Pushgateway restarted without persistence? Metrics in memory are lost on restart — enable persistence with `--persistence.file`.

Reference: `references/dora.md` → Anti-pattern detection

---

After completing this task, log errors and learnings via `/platform-skills:self-improve log`.

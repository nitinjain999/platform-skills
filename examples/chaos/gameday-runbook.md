# GameDay Runbook Template

Use this template for every planned chaos experiment. Fill in each section before injecting faults.

---

## 1. Steady-State Hypothesis

**System is healthy when:**

| Probe | Type | Condition |
|---|---|---|
| `http://my-service/healthz` returns 200 | HTTP | Must hold throughout experiment |
| `rate(http_errors[1m]) < 0.01` | Prometheus | Error rate below 1% |

**Acceptable degradation:** _[e.g., p99 latency may spike up to 2s for up to 10s]_

---

## 2. Blast Radius

| Parameter | Value |
|---|---|
| Namespace | `my-namespace` |
| Label selector | `app=my-service` |
| Fault type | `pod-delete` / `network-loss` / `cpu-stress` |
| Affected pods | 50% (first run) |
| Duration | 60s |
| Environment | staging |

---

## 3. Experiment

```bash
kubectl apply -f examples/chaos/pod-delete-experiment.yaml
kubectl get chaosengine pod-delete-engine -n my-namespace -w
```

---

## 4. Observation

| Time | Observation |
|---|---|
| T+0s | Fault injected |
| T+?s | Alert fired (if applicable) |
| T+?s | Probe failure first seen |
| T+60s | Fault terminated |
| T+?s | Steady-state probe restored |

---

## 5. Verdict

- [ ] **PASS** — steady-state probe held throughout; service recovered within SLO
- [ ] **FAIL** — probe failed OR recovery exceeded SLO OR alert did not fire

**Root cause (if FAIL):**

---

## 6. DORA Impact

| Metric | Observation |
|---|---|
| Change failure rate | Did this fault class appear in past incidents? |
| MTTR | Time from T+0 (fault) to steady-state restored |
| Recommendation | _[e.g., add PDB, increase HPA min replicas, add circuit breaker]_ |

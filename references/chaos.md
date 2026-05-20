# Chaos Engineering Reference

Covers Chaos Engineering on Kubernetes using Litmus Chaos v3 (CNCF graduated) and Chaos Mesh v2 (CNCF incubating). Both tools use Kubernetes CRDs for experiment definition and are GitOps-compatible.

---

## Litmus Chaos vs Chaos Mesh — Decision Matrix

| Scenario | Tool | Reason |
|---|---|---|
| General pod/node fault injection | Litmus Chaos | CNCF graduated, ChaosCenter UI, broad scaler support |
| Fine-grained network partitions | Chaos Mesh | NetworkChaos CRD supports bandwidth/latency/loss/partition |
| GitOps-driven scheduled experiments | Either | Both support CRD-based schedules |
| Already running Chaos Mesh | Chaos Mesh | No migration cost |
| New installation, no preference | Litmus Chaos | Larger community, more built-in experiments |

---

## Installing Litmus Chaos v3

```bash
helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/
helm repo update

helm upgrade --install chaos litmuschaos/litmus \
  --namespace litmus \
  --create-namespace \
  --version 3.9.0 \
  -f examples/chaos/litmus-install-values.yaml
```

Verify:
```bash
kubectl get pods -n litmus
# Expected: chaos-operator, chaos-exporter, workflow-controller all Running
```

---

## Installing Chaos Mesh v2

```bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update

helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh \
  --create-namespace \
  --version 2.7.0 \
  -f examples/chaos/chaos-mesh-install-values.yaml
```

Verify:
```bash
kubectl get pods -n chaos-mesh
# Expected: chaos-controller-manager, chaos-daemon (DaemonSet), chaos-dashboard all Running
```

---

## Fault Taxonomy

### Pod faults

| Fault | Litmus | Chaos Mesh |
|---|---|---|
| Delete a pod | `pod-delete` ChaosExperiment | `PodChaos` action: `pod-kill` |
| CPU stress in container | `pod-cpu-hog` | `StressChaos` stressors.cpu |
| Memory stress in container | `pod-memory-hog` | `StressChaos` stressors.memory |
| Kill container (not pod) | `container-kill` | `PodChaos` action: `container-kill` |

### Node faults

| Fault | Litmus | Chaos Mesh |
|---|---|---|
| Drain node | `node-drain` | not built-in (use Litmus) |
| CPU stress on node | `node-cpu-hog` | `StressChaos` with node selector |
| Memory stress on node | `node-memory-hog` | `StressChaos` with node selector |

**Node faults require privileged access.** Never run node faults on control-plane nodes or without a maintenance window.

### Network faults

| Fault | Litmus | Chaos Mesh |
|---|---|---|
| Packet loss | `pod-network-loss` | `NetworkChaos` action: loss |
| Latency injection | `pod-network-latency` | `NetworkChaos` action: delay |
| Packet corruption | `pod-network-corruption` | `NetworkChaos` action: corrupt |
| Network partition | not built-in | `NetworkChaos` action: partition |

### Stress / I/O faults

| Fault | Tool |
|---|---|
| Disk fill | Litmus `disk-fill` |
| I/O chaos (latency/error on disk ops) | Chaos Mesh `IOChaos` |

---

## Steady-State Hypothesis

**Required before every experiment.** A steady-state hypothesis defines what "the system is healthy" means in measurable terms. Without it, chaos is just destructive noise.

```yaml
# In a Litmus ChaosEngine probe:
probe:
- name: check-api-availability
  type: httpProbe
  httpProbe/inputs:
    url: http://my-service.my-namespace.svc.cluster.local/healthz
    insecureSkipVerify: false
    method:
      get:
        criteria: ==
        responseCode: "200"
  mode: Continuous
  runProperties:
    probeTimeout: 5000
    interval: 2000
    attempt: 3
    probePollingInterval: 2000

# Or a Prometheus-based probe:
- name: check-error-rate
  type: promProbe
  promProbe/inputs:
    endpoint: http://prometheus.monitoring.svc.cluster.local:9090
    query: rate(http_requests_total{status=~"5.."}[1m]) < 0.01
    comparator:
      type: float
      criteria: ==
      value: "1"
  mode: Edge
```

---

## Blast Radius Scoping Rules

1. **Always namespace-scope first experiments** — never cluster-wide
2. **Use label selectors** to target specific Deployments, not all pods:
   ```yaml
   appLabel: "app=my-service"
   ```
3. **Set `terminationGracePeriodSeconds`** (Litmus) or `duration` (Chaos Mesh) — experiments must self-terminate
4. **Never run pod-delete on a single-replica Deployment** without a PodDisruptionBudget
5. **Start in staging** — only promote GameDay experiments to production with a change window

---

## Litmus: ChaosEngine Structure

```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: pod-delete-engine
  namespace: my-namespace
spec:
  appinfo:
    appns: my-namespace
    applabel: "app=my-service"
    appkind: deployment
  chaosServiceAccount: litmus-admin
  experiments:
  - name: pod-delete
    spec:
      components:
        env:
        - name: TOTAL_CHAOS_DURATION
          value: "60"
        - name: CHAOS_INTERVAL
          value: "15"
        - name: FORCE
          value: "false"
        - name: PODS_AFFECTED_PERC
          value: "50"
      probe:
      - name: check-api-health
        type: httpProbe
        httpProbe/inputs:
          url: http://my-service/healthz
          method:
            get:
              criteria: ==
              responseCode: "200"
        mode: Continuous
        runProperties:
          probeTimeout: 5000
          interval: 2000
          attempt: 3
```

---

## Chaos Mesh: NetworkChaos Structure

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: network-loss-20pct
  namespace: my-namespace
spec:
  action: loss
  mode: all
  selector:
    namespaces:
    - my-namespace
    labelSelectors:
      app: my-service
  loss:
    loss: "20"
    correlation: "25"
  duration: 60s
  direction: to
```

---

## GitOps Integration

Store experiment CRDs in `experiments/` in your GitOps repo:
```
gitops-repo/
  apps/
    experiments/
      staging/
        pod-delete-weekly.yaml
        network-loss-soak.yaml
```

Apply via Flux or Argo CD. Experiments trigger on apply, complete within `duration`, then idle. Re-applying the same manifest re-runs the experiment.

---

## Rollback

Experiments are **time-bound and self-terminating**. On `duration` expiry, the tool auto-terminates and Kubernetes recovers the affected pods naturally.

Manual abort:
```bash
# Litmus
kubectl delete chaosengine pod-delete-engine -n my-namespace
# Chaos Mesh
kubectl delete networkchaos network-loss-20pct -n my-namespace
```

Chaos Mesh also has a pause API:
```bash
kubectl annotate networkchaos network-loss-20pct \
  chaos-mesh.org/pause=true -n my-namespace
```

---

## DORA Feedback Loop

After each experiment, record impact against DORA metrics:
- Did error rate spike beyond SLO? → contributes to **change failure rate**
- How long until steady-state was restored? → contributes to **MTTR**

Feed these observations into DORA tracking. See [references/dora.md](references/dora.md).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| ChaosEngine stuck `Initialized` | Missing ChaosServiceAccount or RBAC | Check `kubectl get sa,clusterrolebinding -n litmus` |
| `ChaosResult` shows `Fail` but pods look fine | Probe failing, not the service | Check probe URL and response code in ChaosResult |
| Chaos Mesh experiment not starting | Controller not running | `kubectl get pods -n chaos-mesh` |
| No pods targeted | Label selector matches zero pods | `kubectl get pods -n my-namespace -l app=my-service` |
| Experiment runs but no impact visible | `PODS_AFFECTED_PERC` too low or duration too short | Increase to 100% affected, 120s duration |
| Experiment won't terminate | `duration` field missing (Chaos Mesh) | Add `duration: 60s` to spec |

## Platform Rules

- Always define a steady-state hypothesis probe before injecting faults — never run chaos without a measurable health baseline.
- Scope experiments to a namespace and label selector — never cluster-wide for initial experiments.
- Never run pod-delete on a single-replica Deployment without a PodDisruptionBudget.
- Start all experiments in staging; promote to production only with a change window.

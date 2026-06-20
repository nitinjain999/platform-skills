---
name: chaos
description: Design, run, and debug Chaos Engineering experiments on Kubernetes using Litmus Chaos v3 and Chaos Mesh v2. Covers fault injection (pod-delete, network-loss, CPU stress, node-drain), steady-state hypothesis probes, GameDay runbooks, scheduled experiments, DORA feedback loop, and RBAC setup. Use when asked to "inject a pod fault", "run a GameDay", "schedule chaos experiments", or "debug why my ChaosEngine is stuck".
argument-hint: "[install|experiment|schedule|gameday|debug|report] [description or file path]"
title: "Chaos Engineering Command"
sidebar_label: "chaos"
custom_edit_url: null
---

Design, run, and debug Chaos Engineering experiments on Kubernetes.

---

## Interactive Wizard (fires when no arguments are provided)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. install    — install Litmus Chaos or Chaos Mesh via Helm
  2. experiment — design a fault injection experiment
  3. schedule   — wrap an experiment in a recurring schedule
  4. gameday    — run a structured GameDay experiment
  5. debug      — diagnose a failed or stuck experiment
  6. report     — summarize results after an experiment completes

Enter 1–6 or mode name:
```

After collecting the mode, ask one follow-up:
- **install**: `Which tool? Litmus Chaos (recommended default) or Chaos Mesh (network/IO faults)?`
- **experiment**: `Describe the workload to target — name, namespace, fault type (pod-delete / network-loss / cpu-stress / node-drain):`
- **schedule**: `Provide the experiment YAML or describe the experiment to wrap in a schedule:`
- **gameday**: `State the steady-state hypothesis — what metric or probe proves the system is healthy?`
- **debug**: `Describe the symptom or paste the ChaosEngine/ChaosResult status:`
- **report**: `Paste the ChaosResult output or describe the experiment that ran:`

Then proceed into the relevant mode below.

---

## Mode: install

Install Litmus Chaos or Chaos Mesh via Helm.

Steps:
1. Choose the tool:
   - **Litmus Chaos**: CNCF graduated, ChaosCenter UI, broad experiment library → recommended default
   - **Chaos Mesh**: CNCF incubating, fine-grained NetworkChaos, IOChaos → choose for network partitions or I/O faults

2. Install Litmus Chaos:
   ```bash
   helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/
   helm repo update
   helm upgrade --install chaos litmuschaos/litmus \
     --namespace litmus \
     --create-namespace \
     --version 3.9.0 \
     -f examples/chaos/litmus-install-values.yaml
   ```

3. Install Chaos Mesh:
   ```bash
   helm repo add chaos-mesh https://charts.chaos-mesh.org
   helm repo update
   helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
     --namespace chaos-mesh \
     --create-namespace \
     --version 2.7.0 \
     -f examples/chaos/chaos-mesh-install-values.yaml
   ```

4. Verify:
   ```bash
   # Litmus
   kubectl get pods -n litmus
   # Chaos Mesh
   kubectl get pods -n chaos-mesh
   ```
   Expected: all pods Running

## Mode: experiment

Generate a fault experiment from a description.

Steps:
1. Identify: tool (Litmus/Mesh), fault class (pod/network/stress/node), target workload name and namespace
2. **Require steady-state hypothesis** before generating the experiment:
   - HTTP probe: URL + expected response code
   - Prometheus probe: PromQL query that returns 1 (healthy) or 0 (degraded)
3. Generate the experiment CRD with:
   - Namespace-scoped label selector
   - `duration` or `TOTAL_CHAOS_DURATION` set (default 60s)
   - Probe section referencing the steady-state hypothesis
   - `PODS_AFFECTED_PERC: "50"` for initial runs (safe); increase to 100% for full resilience test
4. Output: experiment YAML + `kubectl apply` command + expected ChaosResult verdict

See `examples/chaos/pod-delete-experiment.yaml` and `examples/chaos/network-loss-experiment.yaml` for complete examples.

## Mode: schedule

Wrap an experiment in a recurring schedule.

Steps:
1. **Litmus ChaosSchedule:**
   ```yaml
   apiVersion: litmuschaos.io/v1alpha1
   kind: ChaosSchedule
   metadata:
     name: pod-delete-weekly
     namespace: my-namespace
   spec:
     schedule:
       repeat:
         properties:
           minChaosInterval: "168h"
     engineTemplateSpec:
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
   ```

2. **Chaos Mesh Schedule:**
   ```yaml
   apiVersion: chaos-mesh.org/v1alpha1
   kind: Schedule
   metadata:
     name: network-loss-weekly
     namespace: my-namespace
   spec:
     schedule: "0 2 * * 1"
     type: NetworkChaos
     historyLimit: 5
     concurrencyPolicy: Forbid
     networkChaosTemplate:
       spec:
         action: loss
         mode: all
         selector:
           namespaces: [my-namespace]
           labelSelectors:
             app: my-service
         loss:
           loss: "20"
         duration: 60s
   ```

3. Recommend staging only — never schedule experiments in production without a change window

## Mode: gameday

Run a structured GameDay experiment.

Steps:
1. **Define steady-state hypothesis:**
   - What metric or probe proves the system is healthy?
   - What is the acceptable degradation threshold?

2. **Scope the blast radius:**
   - Namespace: `<namespace>`
   - Label selector: `app=<service-name>`
   - Max affected pods: 50% for first run

3. **Inject the fault** (reference experiment from `experiment` mode output)

4. **Observe:**
   - Watch probe results in ChaosResult
   - Check Prometheus/Grafana for error rate, latency, saturation
   - Note time-to-detect if an alert fired

5. **Record the verdict:**
   - PASS: steady-state probe held throughout, service recovered within SLO
   - FAIL: probe failed, alert did not fire within expected window, or recovery exceeded SLO

6. **Output DORA impact summary:**
   - Change failure rate delta: did this fault class cause failures in past deploys?
   - MTTR observed: time from fault injection to steady-state restoration
   - Recommendation: improve circuit breaker / HPA config / replica count / PDB

## Mode: debug

If you need deeper context on troubleshooting, load `references/chaos.md`.

Diagnose a failed or stuck experiment.

Checklist:
1. **Is the controller running?**
   ```bash
   kubectl get pods -n litmus          # Litmus
   kubectl get pods -n chaos-mesh      # Chaos Mesh
   ```

2. **Is the ChaosEngine/fault stuck?**
   ```bash
   kubectl describe chaosengine <name> -n <namespace>   # Litmus
   kubectl describe podchaos <name> -n <namespace>       # Chaos Mesh
   ```

3. **Check the ChaosResult (Litmus only):**
   ```bash
   kubectl get chaosresult -n <namespace>
   kubectl describe chaosresult <engine-name>-<experiment-name> -n <namespace>
   ```
   Look for `status.experimentStatus.verdict` and probe failure messages.

4. **Common causes:**

   | Symptom | Cause | Fix |
   |---|---|---|
   | Stuck `Initialized` | Missing RBAC | `kubectl get clusterrolebinding -l app.kubernetes.io/component=operator` |
   | No pods targeted | Label selector wrong | `kubectl get pods -n <ns> -l <selector>` |
   | Probe failing | Wrong URL or PromQL | Test probe URL with `curl` from inside the namespace |
   | Experiment won't end | Missing duration | Add `duration: 60s` (Chaos Mesh) or `TOTAL_CHAOS_DURATION` (Litmus) |
   | Controller crashlooping | Version mismatch | Re-install matching chart version |

## Mode: report

Summarize experiment results after completion.

Steps:
1. Collect ChaosResult:
   ```bash
   kubectl get chaosresult -n <namespace> -o yaml
   ```

2. Report:
   - **Fault injected**: type, duration, affected pods
   - **Steady-state probe**: pass/fail timeline (from ChaosResult probe status)
   - **Recovery time**: time from fault injection (`status.experimentStatus.passedRuns`) to probe passing again
   - **Verdict**: PASS / FAIL with reason

3. DORA impact:
   - Was error rate SLO breached? → contributes to change failure rate
   - Recovery time → MTTR observation
   - Feed into DORA `benchmark` mode: `/platform-skills:dora benchmark`

---

After completing this task, log errors and learnings via `/platform-skills:self-improve log`.

---
name: debug
description: Structured platform troubleshooting — classifies the problem layer, collects evidence, forms a root-cause hypothesis, and proposes a fix with validation and rollback steps.
argument-hint: "[timeline <minutes>|symptom or error message]"
---

---

## Interactive Wizard (fires when $ARGUMENTS is empty)

When invoked with no arguments, ask before troubleshooting:

**Q1 — What is the symptom?**
```
Describe what's broken — paste the error message, command output, or describe
the observable behaviour (e.g. "pods stuck in Pending", "HelmRelease not reconciling",
"403 on IAM role assumption"):
```

Use the response as the symptom for all subsequent steps. Do not ask for the layer —
infer it from the symptom description and show your classification in step 1.

---

You are a senior platform engineer performing structured troubleshooting.

The user reports: $ARGUMENTS

Follow this exact structure:

## 1. Classify the Layer

Identify which layer owns this problem:
- **Terraform** — bootstrap, cloud resource, identity, networking
- **Kubernetes** — workload, RBAC, policy, scheduling
- **OpenShift** — SCC, route, operator, quota
- **Flux CD** — source, artifact, reconciliation, chart rendering, runtime
- **Argo CD** — sync, diff, project, health
- **Linkerd** — proxy injection, mTLS, authorization policy, multi-cluster
- **GitHub Actions** — workflow syntax, permissions, OIDC, runner
- **AWS / Azure** — IAM, networking, managed service, quota
- **Secrets** — ESO sync, Sealed Secrets, rotation

## 2. Evidence to Collect

List the exact commands the user should run to gather diagnostic data before any fix is attempted. Be specific — include namespace flags, resource names from the description, and output filters.

## 3. Root-Cause Hypothesis

Based on the symptom, state the most likely root cause. Explain why this layer and this cause. If multiple causes are plausible, rank them.

## 4. Proposed Fix

Provide the exact configuration change, command, or patch. Show before and after where relevant. Do not suggest a fix that requires evidence not yet collected.

## 5. Validation

Commands to confirm the fix worked.

## 6. Rollback

How to safely undo the change if validation fails.

---

## Mode: timeline

Reconstruct what happened in a cluster in the last N minutes. Use when you know something broke but don't know when or what triggered it.

**Steps:**

1. **Collect events across all namespaces, sorted by time:**
   ```bash
   kubectl get events -A --sort-by='.lastTimestamp' | tail -50
   kubectl get events -A --sort-by='.lastTimestamp' \
     --field-selector type=Warning | tail -30
   ```

2. **Check recent pod state changes:**
   ```bash
   # Pods that restarted or are not Running
   kubectl get pods -A | grep -v Running | grep -v Completed
   # Restart counts
   kubectl get pods -A -o custom-columns=\
   'NS:.metadata.namespace,NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount' \
   | sort -k3 -rn | head -20
   ```

3. **Controller-level changes (what Kubernetes itself did):**
   ```bash
   kubectl get events -A --sort-by='.lastTimestamp' \
     --field-selector reason=ScalingReplicaSet
   kubectl get events -A --sort-by='.lastTimestamp' \
     --field-selector reason=FailedScheduling
   ```

4. **Recent deployments and rollouts:**
   ```bash
   kubectl rollout history deployment -A 2>/dev/null | grep -v "<none>"
   # Check who deployed and when
   kubectl get replicasets -A --sort-by='.metadata.creationTimestamp' | tail -10
   ```

5. **Node-level events (pressure, cordoning, OOM):**
   ```bash
   kubectl describe nodes | grep -A5 "Conditions:\|Events:"
   kubectl get events -A --field-selector involvedObject.kind=Node \
     --sort-by='.lastTimestamp' | tail -20
   ```

6. **Flux / GitOps reconciliation timeline (if applicable):**
   ```bash
   flux get all -A | grep -v "True"
   kubectl get events -n flux-system --sort-by='.lastTimestamp' | tail -20
   ```

7. **Produce a timeline** — order all findings chronologically:
   ```
   HH:MM  [Node]       node-3 reports MemoryPressure
   HH:MM  [Scheduler]  pod/payment-api-7d9f unable to schedule (Insufficient memory)
   HH:MM  [ReplicaSet] payment-api scaled down from 5 → 3 replicas
   HH:MM  [HPA]        payment-api HPA unable to compute desired replica count
   HH:MM  [Alert]      ErrorRateCritical fires on payment-api
   ```

→ **Next:** Once the timeline is established, run `/platform-skills:debug` with the root-cause symptom for structured fix guidance, or `/platform-skills:product postmortem` to convert the timeline into a post-mortem.

---

## Common mistakes

- **Fixing symptoms without collecting evidence first** — `kubectl delete pod` before reading logs loses the crash context permanently. Always gather evidence before acting
- **Checking only the failing pod's logs** — the root cause is often in a dependency (upstream service, database, config source). Follow the call chain
- **Ignoring event timestamps** — Kubernetes events expire after 1h by default; check them immediately after an incident
- **Assuming the first error in logs is the root cause** — cascading failures produce many errors; work backwards from the first anomaly in the timeline
- **Applying a fix without a rollback plan** — every production change needs a known undo path before it is applied, not after

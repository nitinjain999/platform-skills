---
name: keda
description: Design, debug, and review KEDA ScaledObject/ScaledJob autoscaling. Covers all major scalers (Prometheus, SQS, Kafka, Redis, Cron, HTTP Add-on, Azure Service Bus), TriggerAuthentication, scaling lifecycle tuning, GitOps integration, and troubleshooting. Use when asked to "add KEDA autoscaling", "debug why my ScaledObject isn't scaling", "review my KEDA config", or "generate a ScaledObject for <trigger>".
argument-hint: "[scale|debug|review|generate] [description or file path]"
---

Design, debug, and review KEDA (Kubernetes Event-Driven Autoscaling) ScaledObject and ScaledJob resources.

## Mode: generate

Write a production-ready ScaledObject or ScaledJob from a description.

Steps:
1. Identify: target workload kind (Deployment / StatefulSet / Job), trigger type, and whether scale-to-zero is acceptable
2. Choose the right resource kind:
   - Long-running service → `ScaledObject`
   - Batch processing per message → `ScaledJob`
3. Generate with:
   - `apiVersion: keda.sh/v1alpha1`
   - `scaleTargetRef.name` matching the exact Deployment/StatefulSet/Job name
   - `minReplicaCount: 0` only if the service can tolerate cold-start latency; otherwise `minReplicaCount: 1`
   - `pollingInterval` and `cooldownPeriod` sized to the workload pattern (see table in `references/keda.md`)
   - Trigger-specific `metadata` with `activationThreshold`/`activationQueueLength` set to avoid flapping on sparse events
   - `authenticationRef` pointing to a `TriggerAuthentication` — never inline credentials in the ScaledObject
   - For AWS: prefer IRSA (`podIdentity.provider: aws`) over static key/secret pairs
4. Generate the companion `TriggerAuthentication` or `ClusterTriggerAuthentication`
5. Show validation command: `kubectl describe scaledobject <name> -n <ns>` and the expected `Active: true` condition

Reference: `references/keda.md` → ScaledObject, ScaledJob, TriggerAuthentication

## Mode: debug

Diagnose why a ScaledObject or ScaledJob is not scaling as expected.

Steps:
1. Collect:
   ```bash
   kubectl get scaledobject -n <namespace>
   kubectl describe scaledobject <name> -n <namespace>
   kubectl get hpa -n <namespace>
   kubectl describe hpa keda-hpa-<scaledobject-name> -n <namespace>
   kubectl logs -n keda -l app.kubernetes.io/name=keda-operator --tail=100
   kubectl logs -n keda -l app.kubernetes.io/name=keda-operator-metrics-apiserver --tail=100
   ```
2. Check the ScaledObject `Conditions` block:
   - `Active: false` → scaler is not detecting events (check trigger config and auth)
   - `Ready: false` → KEDA cannot reach the target deployment (check `scaleTargetRef.name`)
   - `Fallback: true` → metric fetch is failing; KEDA is using fallback replicas
3. Check HPA for `<unknown>` targets — indicates metrics adapter cannot reach the external source
4. Work through this checklist in order:
   - External source reachable from the KEDA namespace?
   - TriggerAuthentication secret exists and has correct keys?
   - `activationThreshold` too high for current event volume?
   - `minReplicaCount` preventing scale-to-zero?
   - Conflicting HPA on the same Deployment?
   - `cooldownPeriod` not yet elapsed?
5. State the most likely root cause with the exact field or resource to fix
6. Show the corrected spec section and the command to verify it

Reference: `references/keda.md` → Troubleshooting

## Mode: review

Review an existing ScaledObject or ScaledJob for correctness, security, and operational safety.

Review in this priority order:

**Correctness**
- Does `scaleTargetRef.name` match an existing Deployment/StatefulSet?
- Are `minReplicaCount` and `maxReplicaCount` consistent with the workload SLA?
- Is `pollingInterval` appropriate for the trigger type (SQS charges per API call)?
- Does the trigger `metadata` use the right field names for this scaler version?

**Security**
- Are credentials stored in TriggerAuthentication, not inlined in ScaledObject?
- Is IRSA / Workload Identity used instead of static access keys?
- Is TriggerAuthentication namespace-scoped unless cluster-wide sharing is justified?
- Does the IAM policy grant only the minimum permissions needed (read queue depth, not consume)?

**Operational safety**
- Is `minReplicaCount: 0` justified? What is the cold-start latency?
- Is `cooldownPeriod` long enough to prevent thrashing?
- Is `advanced.restoreToOriginalReplicaCount: true` set if the ScaledObject may be deleted?
- Are `activationThreshold`/`activationQueueLength` set to prevent premature activation on sparse events?
- Is HPA `scaleDown.stabilizationWindowSeconds` configured for latency-sensitive services?

**GitOps safety**
- Does the Flux/Argo Kustomization depend on KEDA CRDs being installed first?
- Is the TriggerAuthentication Secret rendered by External Secrets Operator (not committed to Git)?

Separate findings into:
- **Critical** — must fix before deploying (missing auth, wrong target, wildcard IAM permissions)
- **Improvement** — should fix (tune cooldownPeriod, add activationThreshold)
- **Note** — informational (consider IRSA, document cold-start expectations)

Reference: `references/keda.md` → Security Patterns, Scaling Lifecycle

## Mode: scale

Design the scaling strategy for a workload from requirements.

Steps:
1. Ask for (or infer from context):
   - Workload type: background job or synchronous service?
   - Event source: queue service, stream, metrics, time-based, HTTP?
   - Expected event volume range (min/max per minute)
   - Acceptable cold-start latency (drives min replicas decision)
   - Cloud provider (for auth pattern: IRSA vs Workload Identity vs static)
2. Apply the KEDA vs HPA decision matrix from `references/keda.md`
3. Recommend the trigger type(s) and explain why
4. Size `pollingInterval`, `cooldownPeriod`, and `minReplicaCount` based on the workload pattern
5. Recommend the authentication pattern (IRSA preferred on AWS, no static credentials)
6. If multiple triggers are needed (e.g., queue depth + cron business hours), explain the OR-max semantics
7. Output the complete ScaledObject, TriggerAuthentication, and IAM policy skeleton

Reference: `references/keda.md` → KEDA vs HPA decision matrix, Scalers

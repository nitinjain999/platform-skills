---
title: KEDA
custom_edit_url: null
---

# KEDA Reference

Covers KEDA (Kubernetes Event-Driven Autoscaling) v2.x — ScaledObject, ScaledJob, TriggerAuthentication, ClusterTriggerAuthentication, scalers (CPU, memory, Prometheus, Kafka, SQS, Redis, Cron, HTTP Add-on, Azure Service Bus), scaling lifecycle, security patterns, GitOps integration, and troubleshooting.

> **KEDA version baseline**
> This guide targets KEDA v2.14+ (stable). ScaledObject and ScaledJob use `keda.sh/v1alpha1`. The HTTP Add-on is a separate Helm chart (`kedacore/keda-add-ons-http`).

---

## What is KEDA?

KEDA extends Kubernetes HPA by adding an event-driven trigger layer. It:

1. Reads metrics from external sources (queues, topics, databases, custom APIs)
2. Converts those metrics into HPA-compatible values
3. Drives replicas from 0 → N (scale-from-zero) and back to 0 (scale-to-zero)

KEDA works alongside the Kubernetes HPA — it creates and manages an HPA object on your behalf. Do not create your own HPA for the same deployment.

### KEDA vs standard HPA decision matrix

| Scenario | Use | Reason |
|---|---|---|
| Scale on CPU or memory only | HPA directly | No external metric source needed |
| Scale on queue depth (SQS, Kafka, RabbitMQ) | KEDA | HPA cannot reach external APIs |
| Scale-from-zero (0 replicas when idle) | KEDA | HPA min replicas = 1 |
| Scale based on Prometheus query | KEDA | Prometheus scaler handles metric fetch |
| Scheduled scaling (time-based) | KEDA Cron scaler | HPA has no time concept |
| Batch job triggered by queue message | KEDA ScaledJob | HPA targets Deployments, not Jobs |
| Long-running service with custom metrics | Either | Prefer KEDA for simpler auth and multi-trigger |

---

## Architecture

```
External source (SQS, Kafka, Prometheus...)
          │
          ▼
    KEDA Metrics Adapter  ◄──  ScaledObject spec
          │
          ▼
    Kubernetes HPA  ──►  Deployment / StatefulSet / ReplicaSet
          │
          ▼
    Pod replicas (0 → maxReplicas)
```

KEDA installs three components:

| Component | Purpose |
|---|---|
| `keda-operator` | Watches ScaledObject/ScaledJob, creates HPA, runs scale-to-zero |
| `keda-operator-metrics-apiserver` | Serves external metrics to the HPA |
| `keda-admission-webhooks` | Validates ScaledObject/ScaledJob on admission |

---

## Installation

### Helm (recommended)

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm upgrade --install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  --version 2.14.0 \
  --set watchNamespace="" \
  --set resources.operator.requests.cpu=100m \
  --set resources.operator.requests.memory=100Mi \
  --set resources.operator.limits.cpu=1 \
  --set resources.operator.limits.memory=1000Mi \
  --set resources.metricServer.requests.cpu=100m \
  --set resources.metricServer.requests.memory=100Mi \
  --set resources.metricServer.limits.cpu=1 \
  --set resources.metricServer.limits.memory=1000Mi
```

`watchNamespace=""` means KEDA watches all namespaces. Set to a specific namespace for single-tenant installs.

### Verify

```bash
kubectl get pods -n keda
# keda-operator-xxx                Ready
# keda-operator-metrics-apiserver-xxx  Ready

kubectl get crd | grep keda.sh
# scaledobjects.keda.sh
# scaledjobs.keda.sh
# triggerauthentications.keda.sh
# clustertriggerauthentications.keda.sh
```

---

## ScaledObject

Drives autoscaling for a Deployment, StatefulSet, or any resource implementing `scale` subresource.

### Minimal example (Prometheus scaler)

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: orders-processor
  namespace: orders
spec:
  scaleTargetRef:
    name: orders-processor          # Deployment name
  minReplicaCount: 1                # 0 = scale-to-zero
  maxReplicaCount: 20
  pollingInterval: 30               # Seconds between metric polls
  cooldownPeriod: 300               # Seconds to wait before scaling to 0
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://prometheus.monitoring.svc.cluster.local:9090
        metricName: orders_queue_depth
        query: sum(orders_queue_depth)
        threshold: "10"             # Scale up when depth > 10 per replica
```

### Scale-to-zero (minReplicaCount: 0)

```yaml
spec:
  minReplicaCount: 0
  cooldownPeriod: 120    # Wait 120s after last event before scaling to 0
  triggers:
    - type: aws-sqs-queue
      metadata:
        queueURL: https://sqs.eu-central-1.amazonaws.com/123456789/orders
        queueLength: "5"
        awsRegion: eu-central-1
      authenticationRef:
        name: keda-sqs-auth
```

> **Cold-start latency**: scale-to-zero means the first request after idle may queue until a pod starts (usually 10–30 s depending on image pull and init time). Use `minReplicaCount: 1` for latency-sensitive services.

### Multiple triggers (OR logic)

When multiple triggers are defined, KEDA uses the trigger producing the highest desired replica count. Triggers do not all need to fire simultaneously.

```yaml
spec:
  triggers:
    - type: aws-sqs-queue
      metadata:
        queueURL: https://sqs.eu-central-1.amazonaws.com/123456789/orders
        queueLength: "5"
        awsRegion: eu-central-1
      authenticationRef:
        name: keda-sqs-auth
    - type: cron
      metadata:
        timezone: Europe/Berlin
        start: "0 9 * * 1-5"       # Ensure min replicas during business hours
        end: "0 18 * * 1-5"
        desiredReplicas: "3"
```

### Advanced spec fields

```yaml
spec:
  scaleTargetRef:
    apiVersion: apps/v1             # Default; override for custom resources
    kind: Deployment
    name: orders-processor
  minReplicaCount: 0
  maxReplicaCount: 50
  pollingInterval: 15
  cooldownPeriod: 300
  idleReplicaCount: 0               # When no events, stay at this replica count
  initialCooldownPeriod: 120        # Don't scale-to-zero for first N seconds after creation
  advanced:
    restoreToOriginalReplicaCount: true  # Restore replicas on ScaledObject deletion
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 300   # Slow scale-down
          policies:
            - type: Percent
              value: 25
              periodSeconds: 60
        scaleUp:
          stabilizationWindowSeconds: 0     # Fast scale-up
          policies:
            - type: Percent
              value: 100
              periodSeconds: 15
```

---

## ScaledJob

Triggers Kubernetes `Job` creation in response to events — each message spawns one (or more) Job pods. Use for batch workloads.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: report-generator
  namespace: reports
spec:
  jobTargetRef:
    parallelism: 1
    completions: 1
    backoffLimit: 2
    template:
      spec:
        containers:
          - name: report-generator
            image: myregistry.io/report-generator:1.2.0
            resources:
              requests:
                cpu: 500m
                memory: 512Mi
              limits:
                memory: 2Gi             # Omit cpu limit — it causes throttling
        restartPolicy: Never
  minReplicaCount: 0
  maxReplicaCount: 10               # Max concurrent jobs
  pollingInterval: 30
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 5
  scalingStrategy:
    strategy: accurate              # accurate | default | custom
  triggers:
    - type: aws-sqs-queue
      metadata:
        queueURL: https://sqs.eu-central-1.amazonaws.com/123456789/reports
        queueLength: "1"            # 1 message = 1 job
        awsRegion: eu-central-1
      authenticationRef:
        name: keda-sqs-auth
```

### Scaling strategies

| Strategy | Behavior |
|---|---|
| `default` | Create (messages - running jobs) jobs |
| `accurate` | Query queue depth on every poll cycle — more accurate but more API calls |
| `custom` | Custom function using `customScalingQueueLengthDeduction` and `customScalingRunningJobPercentage` |

---

## TriggerAuthentication

Stores credentials for scalers. Supports Kubernetes Secrets, Pod Identity (IRSA, Workload Identity, Azure AD), HashiCorp Vault, and environment variables.

### Kubernetes Secret reference

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: keda-sqs-auth
  namespace: orders
spec:
  secretTargetRef:
    - parameter: awsAccessKeyID
      name: keda-aws-credentials
      key: AWS_ACCESS_KEY_ID
    - parameter: awsSecretAccessKey
      name: keda-aws-credentials
      key: AWS_SECRET_ACCESS_KEY
```

> **Prefer Pod Identity over static credentials.** Static AWS keys require rotation and grant cluster-wide access if the Secret is over-permissioned. Pod Identity scopes credentials to the specific pod SA.

### IRSA (AWS IAM Roles for Service Accounts)

No static credentials needed. KEDA assumes an IAM role via OIDC federation.

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: keda-sqs-auth
  namespace: orders
spec:
  podIdentity:
    provider: aws                   # aws | azure | gcp | aws-eks
```

Prerequisites:
```bash
# 1. Create IRSA role with SQS read permissions and trust policy scoped to KEDA SA
# 2. Annotate KEDA operator SA with the role ARN
kubectl annotate serviceaccount keda-operator \
  -n keda \
  eks.amazonaws.com/role-arn=arn:aws:iam::123456789:role/keda-operator
```

Minimum IAM policy for SQS scaler:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl"
      ],
      "Resource": "arn:aws:sqs:eu-central-1:123456789:orders"
    }
  ]
}
```

### ClusterTriggerAuthentication

Cluster-scoped version — reusable across all namespaces. Reference with `kind: ClusterTriggerAuthentication` in ScaledObject.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ClusterTriggerAuthentication
metadata:
  name: cluster-sqs-auth            # No namespace
spec:
  podIdentity:
    provider: aws
```

```yaml
# In ScaledObject:
triggers:
  - type: aws-sqs-queue
    authenticationRef:
      name: cluster-sqs-auth
      kind: ClusterTriggerAuthentication
```

---

## Scalers

### CPU and Memory (built-in, no TriggerAuthentication needed)

```yaml
triggers:
  - type: cpu
    metricType: Utilization         # Utilization | AverageValue
    metadata:
      value: "60"                   # 60% CPU utilization
  - type: memory
    metricType: Utilization
    metadata:
      value: "70"                   # 70% memory utilization
```

CPU and memory triggers require resource requests to be set on the target containers — HPA cannot compute utilization without them.

### Prometheus

```yaml
triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus.monitoring.svc.cluster.local:9090
      metricName: http_requests_per_second
      query: rate(http_requests_total[2m])
      threshold: "100"
      activationThreshold: "10"    # Min value to activate scaling (avoids flapping)
      namespace: orders             # Prometheus namespace label filter (optional)
```

### AWS SQS

```yaml
triggers:
  - type: aws-sqs-queue
    metadata:
      queueURL: https://sqs.eu-central-1.amazonaws.com/123456789/orders
      queueLength: "10"            # Target messages per replica
      awsRegion: eu-central-1
      scaleOnInFlight: "true"      # Count in-flight messages too
      activationQueueLength: "1"   # Min depth before activating
    authenticationRef:
      name: keda-sqs-auth
```

### Apache Kafka

```yaml
triggers:
  - type: kafka
    metadata:
      bootstrapServers: kafka.kafka.svc.cluster.local:9092
      consumerGroup: orders-consumer
      topic: orders
      lagThreshold: "20"           # Messages behind per replica
      activationLagThreshold: "5"
      offsetResetPolicy: latest    # latest | earliest
    authenticationRef:
      name: keda-kafka-auth
```

TriggerAuthentication for SASL/TLS:
```yaml
spec:
  secretTargetRef:
    - parameter: sasl
      name: kafka-credentials
      key: sasl                    # plaintext | scram_sha256 | scram_sha512
    - parameter: username
      name: kafka-credentials
      key: username
    - parameter: password
      name: kafka-credentials
      key: password
    - parameter: tls
      name: kafka-credentials
      key: tls                     # enable | disable
```

### Redis (List)

```yaml
triggers:
  - type: redis
    metadata:
      address: redis.cache.svc.cluster.local:6379
      listName: order-queue
      listLength: "20"
      activationListLength: "5"
    authenticationRef:
      name: keda-redis-auth
```

### Cron (scheduled scaling)

Use when replica count should follow a predictable time-based pattern. The Cron scaler feeds a `desiredReplicas` metric into the KEDA-managed HPA — KEDA still creates and owns the HPA as with every other scaler. At the window boundary the metric value changes, and the HPA re-evaluates to scale up or down. If you want to delay or smooth scale-down after the window ends, configure `advanced.horizontalPodAutoscalerConfig.behavior.scaleDown` on the ScaledObject. `cooldownPeriod` is a separate KEDA setting used after triggers become inactive, primarily affecting scaling back toward `minReplicaCount`/0; it is not the knob the HPA uses to wait before scaling down.

```yaml
triggers:
  - type: cron
    metadata:
      timezone: Europe/Berlin      # IANA timezone — always explicit, never rely on UTC
      start: "0 8 * * 1-5"        # Scale up: 08:00 Mon-Fri
      end: "0 20 * * 1-5"         # Scale down: 20:00 Mon-Fri
      desiredReplicas: "10"
```

#### Multiple non-overlapping windows

Define a separate trigger entry for each time band. Overlapping windows produce undefined behavior.

```yaml
triggers:
  # Weekday morning ramp-up
  - type: cron
    metadata:
      timezone: Europe/Berlin
      start: "0 8 * * 1-5"
      end: "0 10 * * 1-5"
      desiredReplicas: "5"

  # Weekday peak
  - type: cron
    metadata:
      timezone: Europe/Berlin
      start: "0 10 * * 1-5"
      end: "0 20 * * 1-5"
      desiredReplicas: "20"

  # Weekday evening wind-down
  - type: cron
    metadata:
      timezone: Europe/Berlin
      start: "0 20 * * 1-5"
      end: "59 23 * * 1-5"
      desiredReplicas: "3"
```

#### Best practices

| Practice | Reason |
|---|---|
| Always set `timezone` explicitly | KEDA defaults to UTC — business-hours windows in other timezones will fire at wrong times |
| Always pair with a queue/Prometheus trigger | Cron only handles scheduled load; unexpected spikes need a real-time trigger as safety net |
| Keep `minReplicaCount: 1` | Outside any scheduled window KEDA returns to `minReplicaCount`; use 1 to keep a warm pod |
| Set `cooldownPeriod` appropriately and tune HPA scale-down stabilization when needed | `cooldownPeriod` is a KEDA cooldown setting, not an HPA behavior setting. To avoid premature downscale on short gaps between cron windows, tune `advanced.horizontalPodAutoscalerConfig.behavior.scaleDown.stabilizationWindowSeconds` |
| Set `restoreToOriginalReplicaCount: true` | On ScaledObject deletion, restores the previous replica count instead of leaving it at the last cron value |
| Annotate the schedule intent | Future engineers should not need to decode cron syntax to understand the scaling intent |

#### Outside scheduled windows

When no cron window is active, KEDA scales back to `minReplicaCount`. If other triggers (Prometheus, SQS) are also defined, KEDA uses whichever trigger demands the most replicas — the cron floor and event-driven ceiling work together.

```
08:00                      20:00
  │────── cron: 20 replicas ────│
  │                             │ ← event spike: Prometheus takes over → 30 replicas
  │                             │────── cron inactive: back to minReplicaCount: 1 ────
```

See [examples/keda/scaledobject-cron.yaml](../examples/keda/scaledobject-cron.yaml) for a full working example with weekday/weekend windows, a Prometheus safety-net trigger, and a PodDisruptionBudget.

### Azure Service Bus

```yaml
triggers:
  - type: azure-servicebus
    metadata:
      namespace: myservicebus
      queueName: orders             # or topicName + subscriptionName for topics
      messageCount: "10"
      activationMessageCount: "1"
    authenticationRef:
      name: keda-asb-auth
```

### HTTP Add-on (separate chart)

The HTTP Add-on requires installing `kedacore/keda-add-ons-http` separately. It adds an `HTTPScaledObject` kind that intercepts HTTP traffic and scales a Deployment from zero.

```bash
helm upgrade --install keda-add-ons-http kedacore/keda-add-ons-http \
  --namespace keda \
  --version 0.9.0
```

```yaml
apiVersion: http.keda.sh/v1alpha1
kind: HTTPScaledObject
metadata:
  name: orders-api
  namespace: orders
spec:
  hosts:
    - orders.example.com
  scaleTargetRef:
    name: orders-api
    port: 8080
  minReplicaCount: 0
  maxReplicaCount: 10
  scalingMetric:
    requestRate:
      granularity: 1s
      targetValue: 100             # Requests/sec per replica
      window: 1m
```

---

## Scaling Lifecycle

```
No events → 0 replicas (if minReplicaCount: 0)
          │
          │ Event detected (queue depth > activationThreshold)
          ▼
1 replica (activation replica)
          │
          │ Continued events / metric above threshold
          ▼
N replicas (up to maxReplicaCount)
          │
          │ Events drain / metric below threshold
          ▼
cooldownPeriod expires → back to minReplicaCount
```

### Tuning pollingInterval and cooldownPeriod

| Scenario | pollingInterval | cooldownPeriod |
|---|---|---|
| Low-latency queue processing | 5–15s | 30–60s |
| Batch overnight jobs | 60–120s | 300–600s |
| Web API with Prometheus metric | 30s | 300s |
| Business-hours cron + queue | N/A (cron) + 15s | 120s |

**Avoid too-low pollingInterval** — each poll is an API call to the external source. For SQS, AWS charges per API call. For Kafka, excessive polls add broker load.

---

## Security Patterns

### Least-privilege TriggerAuthentication

Never grant KEDA the ability to consume messages — it only needs to read queue depth metrics:

| Scaler | Minimum permission |
|---|---|
| SQS | `sqs:GetQueueAttributes`, `sqs:GetQueueUrl` |
| Kafka | Consumer group read (describe, offset fetch) — not produce |
| Azure Service Bus | `Listen` on the specific queue/subscription |
| Prometheus | No auth needed if Prometheus is cluster-internal |
| Redis | `LLEN` command on the target list only |

### Namespace-scoped vs cluster-scoped auth

Use `TriggerAuthentication` (namespace-scoped) by default. Use `ClusterTriggerAuthentication` only when:
- Multiple teams in multiple namespaces share the same external resource (e.g., a shared Kafka cluster)
- A platform team manages authentication centrally

Document which teams are permitted to reference a `ClusterTriggerAuthentication` — it bypasses namespace RBAC for credential access.

### RBAC for ScaledObject management

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: keda-scaledobject-editor
  namespace: orders
rules:
  - apiGroups: [keda.sh]
    resources: [scaledobjects, scaledjobs, triggerauthentications]
    verbs: [get, list, watch, create, update, patch, delete]
```

### Secrets for credentials

Never inline credentials in ScaledObject. Always use TriggerAuthentication with a Kubernetes Secret or Pod Identity. Seal secrets with External Secrets Operator or Sealed Secrets.

---

## GitOps Integration

### Flux example

```yaml
# infrastructure/keda/kustomization.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: keda
  namespace: flux-system
spec:
  interval: 10m
  path: ./infrastructure/keda
  sourceRef:
    kind: GitRepository
    name: platform
  prune: true
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: keda-operator
      namespace: keda
    - apiVersion: apps/v1
      kind: Deployment
      name: keda-operator-metrics-apiserver
      namespace: keda
```

### Ordering: KEDA before workloads

```yaml
# apps/orders/kustomization.yaml
spec:
  dependsOn:
    - name: keda                    # KEDA CRDs must exist before ScaledObject
```

### Storing TriggerAuthentication in Git safely

Store the TriggerAuthentication manifest without the Secret data. Pair it with an ExternalSecret that creates the Kubernetes Secret:

```yaml
# The TriggerAuthentication references a Secret by name — commit this
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: keda-sqs-auth
spec:
  secretTargetRef:
    - parameter: awsAccessKeyID
      name: keda-aws-credentials    # Created by ExternalSecret
      key: AWS_ACCESS_KEY_ID
```

The Secret itself is never committed — it's rendered by External Secrets Operator at runtime.

---

## Troubleshooting

### Diagnostic commands

```bash
# Check ScaledObject status
kubectl get scaledobject -n <namespace>
kubectl describe scaledobject <name> -n <namespace>

# Check the HPA KEDA created
kubectl get hpa -n <namespace>
kubectl describe hpa keda-hpa-<scaledobject-name> -n <namespace>

# Check KEDA operator logs
kubectl logs -n keda -l app.kubernetes.io/name=keda-operator --tail=100

# Check metrics server logs (auth issues show here)
kubectl logs -n keda -l app.kubernetes.io/name=keda-operator-metrics-apiserver --tail=100

# Fetch current metric value KEDA sees
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/<namespace>/<metric-name>"
```

### Common problems

#### ScaledObject never activates (stays at 0 replicas)

**Symptom:** `kubectl get scaledobject` shows `Active: false`, deployment stays at 0 replicas.

**Diagnosis:**
```bash
kubectl describe scaledobject <name> -n <ns>
# Look for: Conditions — Active, Ready, Fallback
kubectl logs -n keda -l app.kubernetes.io/name=keda-operator --tail=100 | grep -i error
```

**Common causes:**
- `activationThreshold` / `activationQueueLength` set too high — metric never crosses it
- TriggerAuthentication missing or misconfigured — KEDA can't read the external source
- External source unreachable from cluster — network policy blocking egress, or wrong endpoint

#### Deployment doesn't scale down to 0

**Symptom:** Deployment stays at 1 replica despite empty queue.

**Check:**
```bash
kubectl describe scaledobject <name> -n <ns>
# Look for: Idle Replica Count, Cooldown Period
```

**Common causes:**
- `minReplicaCount: 1` — explicitly prevents scale-to-zero
- `idleReplicaCount` set to 1 or above
- `cooldownPeriod` not yet elapsed — wait longer before diagnosing
- Multiple triggers: one trigger (e.g., Cron) keeps desired replicas > 0

#### KEDA creates HPA but HPA shows `<unknown>` metrics

**Symptom:** `kubectl get hpa -n <ns>` shows `TARGETS: <unknown>/10`.

**Diagnosis:**
```bash
kubectl describe hpa keda-hpa-<name> -n <ns>
# Look for: Warning FailedGetExternalMetric
kubectl logs -n keda -l app.kubernetes.io/name=keda-operator-metrics-apiserver --tail=50
```

**Common causes:**
- Metrics adapter pod not ready: `kubectl get pods -n keda`
- TriggerAuthentication secret key missing or wrong
- External source returns empty/null metric — check scaler-specific connection

#### Kafka: consumer group not found / offset reset issues

```bash
# Check consumer group exists and has members
kubectl exec -n kafka <kafka-pod> -- \
  kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group orders-consumer
```

If the consumer group doesn't exist yet, Kafka scalers return 0 lag. The group is created when the first consumer connects. Use `offsetResetPolicy: earliest` to start consuming from the beginning if needed.

#### SQS: KEDA has permissions but queue depth is always 0

```bash
# Test SQS GetQueueAttributes directly
aws sqs get-queue-attributes \
  --queue-url https://sqs.eu-central-1.amazonaws.com/123456789/orders \
  --attribute-names ApproximateNumberOfMessages \
  --region eu-central-1
```

If the AWS CLI returns the count correctly but KEDA reads 0, check `scaleOnInFlight` — by default KEDA uses `ApproximateNumberOfMessages`, not `ApproximateNumberOfMessagesNotVisible`. If your consumers leave messages in-flight, set `scaleOnInFlight: "true"`.

#### Conflicting HPA error on ScaledObject admission

```
Error: ScaledObject targets a resource that already has an HPA
```

KEDA refuses to create a ScaledObject if an HPA already targets the same Deployment. Delete the existing HPA first:

```bash
kubectl delete hpa <existing-hpa> -n <namespace>
```

#### ScaledObject deleted but deployment stays at scaled-up count

Set `advanced.restoreToOriginalReplicaCount: true` in the ScaledObject spec. Without this, KEDA leaves the last replica count in place on deletion.

---

## Observability

### Prometheus metrics from KEDA

KEDA exposes its own metrics on port 8080 (operator) and 9022 (metrics adapter):

```bash
kubectl port-forward -n keda svc/keda-operator 8080:8080
curl localhost:8080/metrics | grep keda_
```

Key metrics:

| Metric | Description |
|---|---|
| `keda_scaler_metrics_value` | Current metric value seen by KEDA |
| `keda_scaler_active` | Whether the scaler is active (1) or idle (0) |
| `keda_scaler_errors_total` | Errors fetching metrics from external source |
| `keda_scaled_object_errors_total` | Errors on the ScaledObject reconcile loop |
| `keda_resource_totals` | Count of ScaledObject/ScaledJob by namespace |

### Grafana dashboard

Import dashboard ID `17784` from Grafana.com — the official KEDA dashboard covers scaler health, active scalers, and error rates.

---

## Version Compatibility

| KEDA version | Kubernetes | Helm chart |
|---|---|---|
| 2.14 | 1.27–1.30 | 2.14.x |
| 2.13 | 1.26–1.29 | 2.13.x |
| 2.12 | 1.25–1.28 | 2.12.x |

Always check [keda.sh/docs](https://keda.sh/docs) for the current compatibility matrix before upgrading.

### Upgrade checklist

1. Check the KEDA release notes for removed scalers or changed metadata fields
2. Run `helm upgrade --dry-run` first
3. After upgrade, verify `kubectl get scaledobject -A` shows `Active: true` for all objects
4. Check KEDA operator logs for any deprecation warnings: `kubectl logs -n keda -l app.kubernetes.io/name=keda-operator --tail=200 | grep -i warn`
5. Rollback: `helm rollback keda -n keda` — ScaledObjects are preserved in etcd

---
name: kubernetes
description: Cluster baseline scaffolding, RBAC diagnosis and generation, workload hardening, and structured pod/scheduling debug for plain Kubernetes across all distributions.
argument-hint: "[baseline|rbac|workload|debug] [namespace or manifest path]"
title: "Kubernetes Command"
sidebar_label: "kubernetes"
custom_edit_url: null
---

# Kubernetes Command

Structured guidance for cluster baseline standards, RBAC, workload patterns, and operational debugging on Kubernetes.

## Activation

```
/platform-skills:kubernetes baseline   # generate namespace, RBAC, network policy, PDB, quota scaffold
/platform-skills:kubernetes rbac       # diagnose 401/403; generate Role/RoleBinding; simulate access
/platform-skills:kubernetes workload   # Deployment, HPA, probes, securityContext hardening
/platform-skills:kubernetes debug      # pod crashloop, OOMKill, pending scheduling, image pull errors
```

---

## Interactive Wizard (fires when no mode is provided)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. baseline  — namespace, RBAC, network policy, PDB, resource quota scaffold
  2. rbac      — diagnose 401/403, generate Role/RoleBinding, simulate access
  3. workload  — Deployment, HPA, probes, securityContext, PDB hardening
  4. debug     — crashloop, OOMKill, pending, image pull, general troubleshoot

Enter 1–4 or mode name:
```

**Q2 — Context** (after mode selected):
- **baseline**: `Which namespace? What team owns it? Any special requirements (privileged workloads, GPU, ingress)?`
- **rbac**: `Paste the 403 error message or describe which service account needs which access.`
- **workload**: `Paste the Deployment manifest or describe what the workload does.`
- **debug**: `Paste the pod describe output and recent logs, or describe the symptom.`

---

## Mode: baseline

**Triggers:** baseline, scaffold, new namespace, set up namespace, platform baseline

Read `references/kubernetes.md` before responding.

Generate the minimum platform baseline for a new namespace. Ask for namespace name and team before generating.

### Namespace with ownership labels

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app-team
  labels:
    team: app-team
    environment: production
    managed-by: platform
  annotations:
    contact: platform@org.com
```

### Resource quota

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: app-team-quota
  namespace: app-team
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "20"
    persistentvolumeclaims: "10"
```

### LimitRange — container defaults

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: container-defaults
  namespace: app-team
spec:
  limits:
    - type: Container
      default:
        cpu: 500m
        memory: 512Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
```

### Default-deny network policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: app-team
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
# Allow DNS egress — required for pod name resolution
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: app-team
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
```

### PodDisruptionBudget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app-pdb
  namespace: app-team
spec:
  minAvailable: 1          # keep at least 1 pod running during voluntary disruptions
  selector:
    matchLabels:
      app: app-team
```

### Validation

```bash
kubectl apply --dry-run=server -f namespace-baseline/

# Confirm quota is applied
kubectl describe resourcequota app-team-quota -n app-team

# Confirm network policy is in place
kubectl get networkpolicy -n app-team

# Test DNS still works from a pod
kubectl run dns-test --image=busybox --restart=Never --rm -it -n app-team \
  -- nslookup kubernetes.default
```

**Handoffs:**
- Policy enforcement on these namespaces → `/platform-skills:kyverno` or `/platform-skills:opa`
- Secrets strategy for the namespace → `/platform-skills:secrets`

---

## Mode: rbac

**Triggers:** 401, 403, forbidden, unauthorized, role, binding, service account, RBAC, can-i

Read `references/kubernetes.md` → RBAC troubleshooting section before responding.

### Step 1 — Diagnose 401 vs 403

| Code | Layer | First check |
|---|---|---|
| `401 Unauthorized` | Authentication failed | `kubectl auth whoami` — confirm identity |
| `403 Forbidden` | Authorized identity, missing permission | `kubectl auth can-i` — confirm what is allowed |

### Step 2 — Simulate the failing request

```bash
# Test exactly what the service account can do
kubectl auth can-i <verb> <resource> \
  --as=system:serviceaccount:<namespace>:<sa-name> \
  -n <namespace>

# Examples
kubectl auth can-i get pods \
  --as=system:serviceaccount:app-team:app-controller \
  -n app-team

kubectl auth can-i list secrets \
  --as=system:serviceaccount:app-team:app-controller \
  -n app-team
```

### Step 3 — Find existing bindings for the service account

```bash
kubectl get rolebindings,clusterrolebindings -A -o json \
  | jq -r '
    .items[]
    | select(
        .subjects[]?
        | select(.kind=="ServiceAccount"
            and .name=="<sa-name>"
            and .namespace=="<namespace>")
      )
    | "\(.kind)/\(.metadata.namespace)/\(.metadata.name) -> \(.roleRef.name)"'
```

### Step 4 — Generate minimum Role and RoleBinding

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: app-team
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: app-team
subjects:
  - kind: ServiceAccount
    name: app-controller
    namespace: app-team
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### Scope selection

| Situation | Use |
|---|---|
| Workload needs access within one namespace | `RoleBinding` → `Role` |
| Reuse a cluster role, scoped to one namespace | `RoleBinding` → `ClusterRole` |
| Controller needs cross-namespace or node access | `ClusterRoleBinding` → `ClusterRole` |

Prefer the narrowest scope. Audit `ClusterRoleBinding` usage regularly:

```bash
kubectl get clusterrolebindings -o json \
  | jq -r '.items[] | select(.subjects[]?.kind=="ServiceAccount") | "\(.metadata.name) -> \(.roleRef.name)"'
```

### Validation

```bash
kubectl auth can-i get pods \
  --as=system:serviceaccount:app-team:app-controller \
  -n app-team
# expected: yes

kubectl auth can-i delete pods \
  --as=system:serviceaccount:app-team:app-controller \
  -n app-team
# expected: no
```

**Rollback:** Delete the `RoleBinding`. Roles and bindings are additive — removing them revokes the access without affecting running workloads beyond that access.

---

## Mode: workload

**Triggers:** deployment, statefulset, HPA, probes, securityContext, harden, resources, requests, limits

Read `references/kubernetes.md` before responding.

### Hardened Deployment template

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: app-team
  labels:
    app: app
    version: "1.0.0"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      serviceAccountName: app-sa    # dedicated SA, not default
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 2000
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: app
          image: ghcr.io/org/app:1.0.0
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              memory: 256Mi           # no CPU limit — throttles unnecessarily
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 2
          startupProbe:             # protects slow-starting apps from liveness kills
            httpGet:
              path: /healthz
              port: 8080
            failureThreshold: 30
            periodSeconds: 10
```

### HPA — only when requests and metrics are defined

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app-hpa
  namespace: app-team
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

For event-driven or custom metric scaling → `/platform-skills:keda`

### Common hardening gaps

| Gap | Fix |
|---|---|
| No `resources.requests` | Pod is unschedulable under resource pressure; add requests |
| `resources.limits.cpu` set | Causes throttling even when cores are idle; remove CPU limit unless hard isolation is needed |
| `runAsRoot: true` or no `runAsNonRoot` | Run as non-root; most app images support UID 1000+ |
| No `readinessProbe` | Pod receives traffic before it is ready; add readiness probe |
| No `startupProbe` for slow apps | Liveness kills pods during slow start; add startup probe |
| `default` service account | Creates implicit access to cluster APIs; create a dedicated SA |

---

## Mode: debug

**Triggers:** crashloop, OOMKilled, pending, ImagePullBackOff, ErrImagePull, error, not starting, debug

Apply the structured checklist:

### Step 1 — Collect evidence

```bash
# Pod state and recent events
kubectl get pod <pod-name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace>

# Container logs — current and previous (if restarted)
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# Recent events in the namespace
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20
```

### Step 2 — Classify by symptom

**CrashLoopBackOff**

```bash
# Application is starting and exiting — check exit code and logs
kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Last State"
kubectl logs <pod-name> -n <namespace> --previous
```

Common causes: application error on startup, missing env var or secret, wrong entrypoint, liveness probe killing a slow-starting pod (add `startupProbe`).

**OOMKilled**

```bash
# Check memory usage vs limit
kubectl top pod <pod-name> -n <namespace> --containers
kubectl get pod <pod-name> -n <namespace> \
  -o jsonpath='{.spec.containers[*].resources}'

# Check OOM events
kubectl describe pod <pod-name> -n <namespace> | grep -i oom
```

Fix: increase `resources.limits.memory` or profile the application for a memory leak. Never remove the limit — set it correctly.

**Pending**

```bash
# Events show why scheduling failed
kubectl describe pod <pod-name> -n <namespace> | grep -A10 "Events:"
```

| Pending reason | Cause | Fix |
|---|---|---|
| `Insufficient cpu/memory` | No node has enough capacity | Add nodes, reduce requests, or check Karpenter/Cluster Autoscaler |
| `didn't match node selector/affinity` | Node labels don't match | Fix the `nodeSelector` or `affinity` block |
| `Unschedulable: taint` | Node has a taint the pod doesn't tolerate | Add the matching `toleration` to the pod spec |
| `PVC not bound` | PersistentVolumeClaim is pending | `kubectl describe pvc <name> -n <ns>` — check StorageClass and provisioner |

**ImagePullBackOff / ErrImagePull**

```bash
kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Failed"
```

Common causes: image tag does not exist, registry is private and `imagePullSecrets` is missing, incorrect registry hostname.

```bash
# Verify the image exists
docker manifest inspect ghcr.io/org/app:1.0.0

# Check imagePullSecrets are mounted
kubectl get pod <pod-name> -n <namespace> \
  -o jsonpath='{.spec.imagePullSecrets}'
```

### Validation

After applying a fix, confirm the pod reaches `Running` and passes readiness:

```bash
kubectl rollout status deployment/<name> -n <namespace>
kubectl get pod -n <namespace> -l app=<label> -w
```

### Rollback

```bash
# Roll back the Deployment to the previous revision
kubectl rollout undo deployment/<name> -n <namespace>

# Check rollout history
kubectl rollout history deployment/<name> -n <namespace>
```

---

## Common mistakes

- **Setting `resources.limits.cpu`** — CPU limits throttle containers even when other cores are idle. Set requests but omit the CPU limit unless hard isolation is specifically required.
- **Using the `default` service account** — it may have accumulated bindings over time and creates implicit API access. Always create a dedicated service account per workload.
- **No `startupProbe` for slow-starting apps** — liveness probes kill pods during startup if `initialDelaySeconds` is too short. Use a startup probe to gate liveness until the app is running.
- **`ClusterRoleBinding` when `RoleBinding` was sufficient** — grants access cluster-wide. Audit all ClusterRoleBindings with service account subjects.
- **`kubectl apply -f` in production without `--dry-run=server` first** — server-side dry-run catches admission errors, invalid API versions, and webhook rejections before they apply.

---

## Reference

Full guidance: `references/kubernetes.md`

For policy enforcement: `/platform-skills:kyverno` or `/platform-skills:opa`

For event-driven autoscaling: `/platform-skills:keda`

For node provisioning: `/platform-skills:karpenter`

Examples:
- `examples/kubernetes/deployment-baseline.yaml`
- `examples/kubernetes/namespace-baseline.yaml`
- `examples/kubernetes/network-policy-default-deny.yaml`
- `examples/kubernetes/pod-disruption-budget.yaml`

Status: Stable

# Kubernetes Examples

Baseline manifests for Kubernetes platform patterns. Apply across EKS, AKS, GKE, and vanilla clusters. Each file is a self-contained, production-hardened example you can copy directly into your GitOps repo.

## Examples

| File | What it shows | Key patterns |
|------|--------------|-------------|
| [namespace-baseline.yaml](namespace-baseline.yaml) | Namespace with ownership labels and pod security enforcement | `pod-security.kubernetes.io/enforce: restricted`, team/env labels |
| [deployment-baseline.yaml](deployment-baseline.yaml) | Deployment with resource limits, probes, and locked-down security context | `runAsNonRoot`, `readOnlyRootFilesystem`, `capabilities.drop: ALL`, no CPU limit |
| [network-policy-default-deny.yaml](network-policy-default-deny.yaml) | Default-deny ingress + example allow rule for ingress controller | Applied before workload; explicit allow for ingress controller namespace |
| [pod-disruption-budget.yaml](pod-disruption-budget.yaml) | PDB protecting minimum availability during node drain | `minAvailable: 1` — prevents simultaneous eviction |

## Quick Start

```bash
# 1. Apply namespace first — sets pod security admission before workloads land
kubectl apply -f namespace-baseline.yaml

# 2. Deploy the baseline workload
kubectl apply -f deployment-baseline.yaml

# 3. Lock down network — default deny then explicit allow
kubectl apply -f network-policy-default-deny.yaml

# 4. Protect availability during drain / rolling update
kubectl apply -f pod-disruption-budget.yaml

# Verify security context is in effect
kubectl get pod -n app-team -o jsonpath='{.items[0].spec.containers[0].securityContext}'
```

## Key Patterns

### Security context (required on every container)

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
```

### Resource management (no CPU limit — avoids throttling)

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    memory: "256Mi"   # CPU limit intentionally omitted
```

### Health probes (required for safe rolling updates)

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

## Checklist

- [ ] Namespace ownership labels present (`team`, `env`)
- [ ] Pod security admission enforced (`restricted` mode)
- [ ] Resource requests and limits on every container (no CPU limit)
- [ ] Liveness and readiness probes defined
- [ ] ServiceAccount explicitly set — not the `default` service account
- [ ] `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: ALL`
- [ ] `readOnlyRootFilesystem: true` (add `emptyDir` mounts for writable paths)
- [ ] Default-deny NetworkPolicy applied before any allow rules
- [ ] PodDisruptionBudget covers every deployment with `replicas >= 2`

## See Also

- [references/kubernetes.md](../../references/kubernetes.md) — cluster baselines, workload patterns, RBAC, network policy, pod security
- `/platform-skills:audit` — production-readiness review of any manifest
- `/platform-skills:debug` — structured diagnosis for Kubernetes issues

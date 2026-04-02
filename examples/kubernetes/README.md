# Kubernetes Examples

Baseline manifests for Kubernetes platform patterns. These apply across managed cluster distributions (EKS, AKS, GKE, vanilla).

Status: committed manifest snippets for the handbook. Adapt them into your own repo or GitOps structure.

## Files

| File | What it shows |
|---|---|
| [namespace-baseline.yaml](namespace-baseline.yaml) | Namespace with ownership labels and pod security enforcement |
| [deployment-baseline.yaml](deployment-baseline.yaml) | Deployment with resource limits, health probes, and locked-down security context |
| [network-policy-default-deny.yaml](network-policy-default-deny.yaml) | Default-deny ingress + example allow rule for ingress controller |
| [pod-disruption-budget.yaml](pod-disruption-budget.yaml) | PDB protecting minimum availability during node drain |

## Usage

Apply the namespace first, then the workload manifests:

```bash
kubectl apply -f namespace-baseline.yaml
kubectl apply -f deployment-baseline.yaml
kubectl apply -f network-policy-default-deny.yaml
kubectl apply -f pod-disruption-budget.yaml
```

## Checklist

- Namespace ownership labels present
- Resource requests and limits defined on every container
- Liveness and readiness probes defined
- ServiceAccount explicitly set (no default service account)
- Security context: `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: ALL`
- Default-deny NetworkPolicy applied before allow rules
- PodDisruptionBudget covers any deployment with `replicas >= 2`

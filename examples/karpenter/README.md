# Karpenter Examples

Status: Stable

Working NodePool, EC2NodeClass, and validation examples for Karpenter v1.x on Amazon EKS.

## Files

| File | Purpose |
|---|---|
| [nodepool-default-al2023.yaml](nodepool-default-al2023.yaml) | General-purpose NodePool — AL2023, mixed Spot/On-Demand, multi-AZ, Graviton included |
| [nodepool-spot-flex.yaml](nodepool-spot-flex.yaml) | Spot-optimised NodePool — broad instance families, batch workloads, high weight |
| [nodepool-critical-ondemand.yaml](nodepool-critical-ondemand.yaml) | On-Demand NodePool for SLA-bound workloads — pinned AMI, conservative disruption, PDB included |
| [nodepool-gpu.yaml](nodepool-gpu.yaml) | GPU NodePool — Bottlerocket AMI, g4dn/g5/p3 families, no disruption |
| [karpenter-validate.sh](karpenter-validate.sh) | Validation script — offline field checks + kubectl dry-run + live cluster health |

## Quick start

```bash
# Install Karpenter (OCI chart — not the deprecated charts.karpenter.sh repo)
helm upgrade --install karpenter \
  oci://public.ecr.aws/karpenter/karpenter \
  --version "1.12.1" \
  --namespace karpenter \
  --create-namespace \
  --set "settings.clusterName=my-cluster" \
  --set "settings.interruptionQueue=karpenter-my-cluster" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=<controller-role-arn>" \
  --wait

# Apply a NodePool and EC2NodeClass
kubectl apply -f nodepool-default-al2023.yaml

# Check status
kubectl get nodepool
kubectl describe nodepool default

# Validate examples
bash karpenter-validate.sh
```

## NodePool selection strategy

When multiple NodePools exist, Karpenter selects by `weight` (highest first) then cost:

```
spot-flex          weight: 100   Spot, broad families, batch workloads
critical-ondemand  weight: 50    On-Demand, SLA-bound workloads
default            weight: 10    General fallback
gpu                weight: 5     GPU only — requires nvidia.com/gpu toleration
```

Pods land on the lowest-weight matching NodePool unless a `nodeSelector` or `toleration` constrains them.

## Auth patterns

All examples use an EC2 instance profile (`instanceProfile: karpenter-node-profile`). The Karpenter controller itself uses either EKS Pod Identity (recommended) or IRSA for its own API calls.

See [references/karpenter.md](../../references/karpenter.md) for the full IAM policy, interruption queue setup, and Pod Identity vs IRSA comparison.

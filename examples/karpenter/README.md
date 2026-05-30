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
| [ec2nodeclass-private-cluster.yaml](ec2nodeclass-private-cluster.yaml) | Private cluster EC2NodeClass — explicit API endpoint, CA, and service CIDR in AL2023 userData |
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

NodePool selection combines weight and taint/toleration matching:

```
spot-flex          weight: 100   Spot, batch — requires spot-flex toleration (NoSchedule taint)
default            weight: 10    On-Demand, general — matches most pods with no special constraints
critical-ondemand  weight: 5     On-Demand, SLA — opt-in via nodeSelector: karpenter.sh/capacity-type: on-demand
gpu                weight: 5     GPU only — requires nvidia.com/gpu toleration (NoSchedule taint)
```

Karpenter selects the highest-weight NodePool whose requirements and taints the pod satisfies:
- `spot-flex` — only reachable by pods with a `spot-flex` toleration
- `default` — untainted On-Demand pool; matches most general pods with no special constraints
- `critical-ondemand` — weight 5 (below default); only selected when a pod explicitly sets `nodeSelector: { karpenter.sh/capacity-type: on-demand }`
- `gpu` — only reachable by pods with a `nvidia.com/gpu` toleration

## Auth patterns

All examples use an EC2 instance profile (`instanceProfile: karpenter-node-profile`). The Karpenter controller itself uses either EKS Pod Identity (recommended) or IRSA for its own API calls.

See [references/karpenter.md](../../references/karpenter.md) for the full IAM policy, interruption queue setup, and Pod Identity vs IRSA comparison.

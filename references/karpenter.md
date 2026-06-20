---
title: Karpenter
custom_edit_url: null
---

# Karpenter Reference

Covers Karpenter **v1.x** (`karpenter.sh/v1` API) on Amazon EKS. Resources: `NodePool`, `EC2NodeClass`, `NodeClaim`. The v0.x `Provisioner`/`AWSNodeTemplate` API was removed in v1.0.

> **Version baseline**
> This guide targets Karpenter **v1.12.1** (latest stable as of May 2026) with EKS 1.29+. Pod Identity is the preferred auth method (EKS 1.24+). IRSA is fully supported for older clusters. All APIs use `karpenter.sh/v1` and `karpenter.k8s.aws/v1`.

---

## What is Karpenter?

Karpenter is a node autoscaler that watches for unschedulable pods and provisions EC2 instances directly — bypassing the Managed Node Group (MNG) control loop. It replaces Cluster Autoscaler for most EKS workloads.

```
Unschedulable Pod
       │
       ▼
Karpenter controller
  ├── finds best NodePool match
  ├── selects optimal instance type
  ├── launches EC2 directly (RunInstances API)
  └── creates NodeClaim → Node registers → Pod schedules
```

Key differences from Cluster Autoscaler:

| Dimension | Cluster Autoscaler | Karpenter |
|---|---|---|
| Instance selection | Fixed MNG instance type | Dynamic — picks best fit from requirements |
| Provisioning latency | ~60–90s (MNG scale-out) | ~30–45s (direct RunInstances) |
| Spot diversity | Requires separate MNGs per type | Single NodePool, multiple families |
| Bin-packing | Limited | Consolidation removes underutilised nodes |
| Node expiry | Manual rotation | `expireAfter` TTL with automatic drain |

---

## Architecture

### Components

| Component | Runs on | Purpose |
|---|---|---|
| `karpenter` controller | Fargate or MNG (never on nodes it manages) | NodeClaim lifecycle, provisioning, disruption |
| Interruption queue | SQS + EventBridge | Receives Spot interruption, rebalance, and state-change events |

### Resource model

```
NodePool          — scheduling requirements, limits, disruption policy
  └── EC2NodeClass  — AMI, subnet, security group, instance profile
       └── NodeClaim — one per provisioned node, lifecycle-tracked by controller
            └── Node — the actual Kubernetes node
```

A NodePool references exactly one EC2NodeClass. Multiple NodePools can reference the same EC2NodeClass.

---

## Installation

### Prerequisites

```bash
# 1. EKS cluster with OIDC provider (for IRSA) or Pod Identity agent (for EKS Pod Identity)
aws eks describe-cluster --name <cluster> --region eu-north-1 \
  --query 'cluster.identity.oidc.issuer'

# 2. Node IAM role — separate from the EKS worker role, used by Karpenter-provisioned nodes
#    Attach: AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly
#    Plus: EC2 instance profile for the role

# 3. Controller IAM policy — allows Karpenter to call EC2, SQS, SSM, IAM
#    See minimum policy in the IAM section below

# 4. Tag subnets, node security groups, AND the EKS cluster security group for discovery.
#    Missing the cluster SG causes NodeClaim to fail with InvalidParameterValue: securityGroupIds.

# Tag all worker/node subnets
aws ec2 create-tags \
  --resources <subnet-id> <subnet-id-2> \
  --tags Key=karpenter.sh/discovery,Value=<cluster-name>

# Tag the node security group (the one attached to worker nodes)
aws ec2 create-tags \
  --resources <node-security-group-id> \
  --tags Key=karpenter.sh/discovery,Value=<cluster-name>

# Also tag the EKS cluster security group (the one EKS creates automatically)
CLUSTER_SG=$(aws eks describe-cluster --name <cluster-name> --region eu-north-1 \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
aws ec2 create-tags \
  --resources "$CLUSTER_SG" \
  --tags Key=karpenter.sh/discovery,Value=<cluster-name>

# 5. Register the node IAM role so the EKS API server trusts Karpenter-provisioned nodes.
#    Without this, nodes launch and immediately go NotReady with no Karpenter log error.

# EKS 1.29+ — access entry (replaces aws-auth)
aws eks create-access-entry \
  --cluster-name <cluster-name> \
  --principal-arn arn:aws:iam::<account-id>:role/<node-role-name> \
  --type EC2_LINUX \
  --region eu-north-1

# EKS < 1.29 — add to aws-auth ConfigMap instead:
# - groups: [system:bootstrappers, system:nodes]
#   rolearn: arn:aws:iam::<account-id>:role/<node-role-name>
#   username: system:node:{{EC2PrivateDNSName}}
```

### Interruption queue

Karpenter must receive Spot interruption and EC2 health events via SQS:

```bash
# Create SQS queue
aws sqs create-queue \
  --queue-name karpenter-<cluster-name> \
  --attributes MessageRetentionPeriod=300

# EventBridge rules (one per event type)
aws events put-rule --name KarpenterSpotInterruption \
  --event-pattern '{"source":["aws.ec2"],"detail-type":["EC2 Spot Instance Interruption Warning"]}'

aws events put-targets --rule KarpenterSpotInterruption \
  --targets Id=karpenter-queue,Arn=<sqs-arn>
# Repeat for: EC2 Instance Rebalance Recommendation, EC2 Instance State-change Notification
```

### Helm install (OCI chart — the only supported method)

```bash
# Log in to the public ECR registry (no credentials needed for public)
helm registry login public.ecr.aws --username AWS --password $(
  aws ecr-public get-login-password --region us-east-1
)

helm upgrade --install karpenter \
  oci://public.ecr.aws/karpenter/karpenter \
  --version "1.12.1" \
  --namespace karpenter \
  --create-namespace \
  --set "settings.clusterName=<cluster-name>" \
  --set "settings.interruptionQueue=karpenter-<cluster-name>" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=<controller-role-arn>" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait
```

> **OCI chart only** — `https://charts.karpenter.sh` was the v0.x Helm repo and is no longer updated. Always use `oci://public.ecr.aws/karpenter/karpenter`.

### Verify

```bash
kubectl get pods -n karpenter
# NAME                         READY   STATUS    RESTARTS
# karpenter-xxx                1/1     Running   0

kubectl get nodepool,ec2nodeclass -A
kubectl describe nodepool <name>   # Conditions: Ready=True
```

---

## IAM

### Controller IAM policy (minimum)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowScopedEC2InstanceActions",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:CreateFleet"
      ],
      "Resource": [
        "arn:aws:ec2:<region>::image/*",
        "arn:aws:ec2:<region>::snapshot/*",
        "arn:aws:ec2:<region>:*:security-group/*",
        "arn:aws:ec2:<region>:*:subnet/*",
        "arn:aws:ec2:<region>:*:launch-template/*"
      ]
    },
    {
      "Sid": "AllowScopedEC2InstanceActionsWithTags",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:CreateFleet",
        "ec2:CreateLaunchTemplate"
      ],
      "Resource": [
        "arn:aws:ec2:<region>:*:fleet/*",
        "arn:aws:ec2:<region>:*:instance/*",
        "arn:aws:ec2:<region>:*:volume/*",
        "arn:aws:ec2:<region>:*:network-interface/*",
        "arn:aws:ec2:<region>:*:launch-template/*",
        "arn:aws:ec2:<region>:*:spot-instances-request/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/kubernetes.io/cluster/<cluster-name>": "owned"
        },
        "StringLike": {
          "aws:RequestTag/karpenter.sh/nodepool": "*"
        }
      }
    },
    {
      "Sid": "AllowScopedDeletion",
      "Effect": "Allow",
      "Action": [
        "ec2:TerminateInstances",
        "ec2:DeleteLaunchTemplate"
      ],
      "Resource": [
        "arn:aws:ec2:<region>:*:instance/*",
        "arn:aws:ec2:<region>:*:launch-template/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/kubernetes.io/cluster/<cluster-name>": "owned"
        },
        "StringLike": {
          "aws:ResourceTag/karpenter.sh/nodepool": "*"
        }
      }
    },
    {
      "Sid": "AllowRegionalReadActions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeSubnets"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "<region>"
        }
      }
    },
    {
      "Sid": "AllowSSMReadActions",
      "Effect": "Allow",
      "Action": "ssm:GetParameter",
      "Resource": "arn:aws:ssm:<region>::parameter/aws/service/*"
    },
    {
      "Sid": "AllowInterruptionQueueActions",
      "Effect": "Allow",
      "Action": [
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:ReceiveMessage"
      ],
      "Resource": "arn:aws:sqs:<region>:<account-id>:karpenter-<cluster-name>"
    },
    {
      "Sid": "AllowPassingInstanceRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::<account-id>:role/<node-role-name>",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "ec2.amazonaws.com"
        }
      }
    },
    {
      "Sid": "AllowScopedInstanceProfileActions",
      "Effect": "Allow",
      "Action": [
        "iam:AddRoleToInstanceProfile",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:TagInstanceProfile"
      ],
      "Resource": "arn:aws:iam::<account-id>:instance-profile/karpenter*"
    },
    {
      "Sid": "AllowAPIServerEndpointDiscovery",
      "Effect": "Allow",
      "Action": "eks:DescribeCluster",
      "Resource": "arn:aws:eks:<region>:<account-id>:cluster/<cluster-name>"
    }
  ]
}
```

### Pod Identity vs IRSA

| | EKS Pod Identity | IRSA |
|---|---|---|
| EKS version | 1.24+ | Any |
| Setup | Pod Identity Agent add-on + association | OIDC provider + annotated SA |
| Token rotation | Automatic (15 min TTL) | SDK-managed (1h TTL) |
| Multi-cluster | One role, multiple associations | Separate OIDC conditions per cluster |
| Recommendation | Prefer for new clusters | Use for EKS < 1.24 |

**Pod Identity setup:**
```bash
# Install the agent add-on
aws eks create-addon \
  --cluster-name <cluster> \
  --addon-name eks-pod-identity-agent \
  --region eu-north-1

# Create association
aws eks create-pod-identity-association \
  --cluster-name <cluster> \
  --namespace karpenter \
  --service-account karpenter \
  --role-arn arn:aws:iam::<account-id>:role/karpenter-controller
```

**IRSA setup:**
```bash
# Annotate the Karpenter service account
kubectl annotate serviceaccount karpenter -n karpenter \
  eks.amazonaws.com/role-arn=arn:aws:iam::<account-id>:role/karpenter-controller
```

---

## EC2NodeClass

Defines the EC2-specific properties for nodes: AMI, subnet, security group, instance profile, user-data, EBS, and metadata options.

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  # AMI selection — alias resolves to the latest EKS-optimised AMI for the cluster version
  # Use alias for dev/staging; pin to a specific AMI ID for production stability
  amiSelectorTerms:
    - alias: al2023@latest       # AL2023 latest for this cluster's k8s version
    # - id: ami-0abc1234def56789  # Pin to a specific tested AMI for production

  # Subnet discovery — tags applied during cluster bootstrap
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: my-cluster

  # Security group discovery
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: my-cluster

  # Instance profile (for node IAM role)
  instanceProfile: karpenter-node-profile   # EC2 instance profile name

  # Block device — encryption and size
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi
        volumeType: gp3
        encrypted: true
        iops: 3000
        throughput: 125

  # IMDSv2 required — prevents SSRF attacks from pods accessing instance metadata
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpTokens: required           # IMDSv2 only
    httpPutResponseHopLimit: 1     # Prevents pods from reaching IMDS (hop 1 = instance only)

  # Tags applied to all provisioned nodes and volumes
  tags:
    Environment: production
    ManagedBy: karpenter
    karpenter.sh/discovery: my-cluster

  # Optional: custom user-data (AL2023 uses nodeadm YAML, not bash)
  # userData: |
  #   apiVersion: node.eks.aws/v1alpha1
  #   kind: NodeConfig
  #   spec:
  #     kubelet:
  #       config:
  #         maxPods: 110
```

### AMI families

| Family | `alias` prefix | Notes |
|---|---|---|
| AL2023 | `al2023` | Default, recommended. Uses `nodeadm` for user-data. |
| AL2 | `al2` | Legacy. Reaches EOS in June 2025. Migrate to AL2023. |
| Bottlerocket | `bottlerocket` | Read-only root FS, TOML user-data, SELinux enforcing by default |
| Windows 2022 | `windows2022` | No Spot in some regions; no ARM; separate node group required |
| Custom | (none) | Use `amiSelectorTerms[].id` — you own AMI scanning and updates |

### AMI rotation

When `alias: al2023@latest` is used, Karpenter detects AMI updates via SSM parameter changes and marks existing nodes as **drifted**. Drift triggers controlled replacement.

To stage AMI rotation safely in production:
1. Pin a tested AMI: `amiSelectorTerms[].id: ami-<tested>`
2. Test the new AMI in a separate NodePool or lower environment
3. Update the pin to the new AMI ID
4. Karpenter marks nodes as drifted and replaces them respecting PDBs
5. Monitor for bootstrap failures: `kubectl get nodeclaim -A`

Rollback: revert the AMI ID in `EC2NodeClass` — new nodes use the previous AMI; existing nodes are not affected.

---

## NodePool

Defines scheduling requirements, resource limits, and disruption policy.

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    metadata:
      labels:
        nodepool: default         # Useful for node selectors and log filtering
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default

      requirements:
        # Instance families — list at least 3 for Spot diversity
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: [m6i, m6a, m7i, m7a, c6i, c6a, r6i]
          minValues: 3            # Enforce diversity — fail if fewer than 3 families available

        # Instance size — allow medium through 2xlarge for flexible bin-packing
        - key: karpenter.k8s.aws/instance-size
          operator: In
          values: [medium, large, xlarge, 2xlarge]

        # Architecture — include Graviton for ~20% cost saving where workloads support it
        - key: kubernetes.io/arch
          operator: In
          values: [amd64, arm64]

        # Capacity type — Spot preferred; On-Demand fallback via NodePool weight
        - key: karpenter.sh/capacity-type
          operator: In
          values: [spot, on-demand]

        # AZ — tie to subnets where you have capacity
        - key: topology.kubernetes.io/zone
          operator: In
          values: [eu-north-1a, eu-north-1b, eu-north-1c]

      # startupTaints: only set when your CNI/device-plugin removes the taint on readiness.
      # karpenter.sh/not-ready has no built-in remover — omit it here.
      # Example (Cilium removes this after CNI is ready):
      # startupTaints:
      #   - key: node.cilium.io/agent-not-ready
      #     effect: NoExecute

      # Taints for workload isolation (optional)
      # taints:
      #   - key: workload-type
      #     value: batch
      #     effect: NoSchedule

      # Maximum time a node can run before Karpenter replaces it (AMI rotation, drift)
      expireAfter: 720h           # 30 days

      # Maximum time to wait for graceful termination before force-terminating
      terminationGracePeriod: 48h

  # Hard resource ceiling — never omit
  limits:
    cpu: "1000"                   # 1000 vCPUs max across all nodes in this NodePool
    memory: 4000Gi

  # NodePool selection when multiple pools exist — higher weight = preferred
  weight: 10

  disruption:
    # consolidationPolicy options:
    #   WhenEmpty               — only remove fully empty nodes
    #   WhenEmptyOrUnderutilized — also consolidate underutilised nodes (default recommendation)
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 5m          # Minimum safe value — 1m resets on every pod event and causes churn

    # Disruption budgets — protect critical workloads from simultaneous eviction
    budgets:
      - nodes: "10%"              # Default: max 10% of nodes disrupted at once
      - schedule: "0 9 * * 1-5"  # During business hours: disrupt max 0 nodes
        duration: 8h
        nodes: "0"
```

### Multiple NodePools

Use separate NodePools for different workload profiles. Karpenter selects the highest-`weight` NodePool that satisfies pod requirements.

```
NodePool: critical-ondemand   weight: 100   On-Demand only, m-family
NodePool: spot-flex           weight: 50    Spot preferred, broad families
NodePool: default             weight: 10    On-Demand fallback, general
```

Pods select a NodePool via `nodeSelector` or `tolerations`. Karpenter also uses cost as a tiebreaker when multiple NodePools match.

### `startupTaints` vs `taints`

| | `startupTaints` | `taints` |
|---|---|---|
| Applied | At node launch | Always |
| Removed | When node becomes Ready and DaemonSets are scheduled | Never (until NodePool changes) |
| Use for | Preventing premature pod placement | Workload isolation (GPU, batch) |

---

## Cost Strategy

### Spot diversity

**Rule:** Always list ≥3 instance families in Spot NodePools. `InsufficientCapacityError` on a single family stalls provisioning.

```yaml
requirements:
  - key: karpenter.k8s.aws/instance-family
    operator: In
    values: [m6i, m6a, m7i, m7a, c6i, c6a, c7i, c7a, r6i, r7i]
    minValues: 3    # Hard floor — Karpenter will not provision if fewer than 3 families available
  - key: karpenter.sh/capacity-type
    operator: In
    values: [spot, on-demand]   # spot preferred; on-demand fallback
```

### Instance exclusions

Use `NotIn` to block instance families that cause operational problems:

```yaml
requirements:
  # Block burstable instances — CPU credit behaviour causes latency spikes under sustained load
  - key: karpenter.k8s.aws/instance-family
    operator: NotIn
    values: [t2, t3, t3a, t4g]

  # Block previous-generation instances — worse price/performance than gen 6+
  - key: karpenter.k8s.aws/instance-generation
    operator: Gt
    values: ["5"]   # Only gen 6 and above (m6i, c6i, r6i, m7i, ...)

  # Combine with an In requirement to allow only specific families
  - key: karpenter.k8s.aws/instance-family
    operator: In
    values: [m6i, m6a, m7i, m7a, c6i, c6a, c7i, r6i, r7i]
```

> `NotIn` and `In` on the same key intersect — the final set is families that are In the allow-list AND not in the deny-list. You don't need both if your `In` list is already curated.

Use `weight` to bias toward Spot NodePools while keeping an On-Demand NodePool as fallback:

```yaml
# Spot-first NodePool (weight: 100) — Karpenter tries this first
# On-Demand fallback NodePool (weight: 10) — used when Spot unavailable
```

### Graviton (arm64) inclusion

Graviton instances (m7g, c7g, r7g families) are typically 20% cheaper than equivalent x86 for the same workload. Include `arm64` in `requirements` if your container images are multi-arch.

```yaml
- key: kubernetes.io/arch
  operator: In
  values: [amd64, arm64]
```

Verify images are multi-arch before enabling:

```bash
# DockerHub / public registry
docker manifest inspect <image>:<tag> | grep -i '"architecture"'
# Expected output: "architecture": "amd64" and "architecture": "arm64"

# ECR (private registry) — requires AWS credentials
aws ecr describe-image-scan-findings --repository-name <repo> --image-id imageTag=<tag> \
  --region eu-north-1 --query 'imageScanFindings' 2>/dev/null || \
aws ecr batch-get-image \
  --repository-name <repo> \
  --image-ids imageTag=<tag> \
  --query 'images[*].imageManifest' --output text | \
  python3 -c "import sys,json; m=json.load(sys.stdin); [print(e.get('platform',{}).get('architecture','?')) for e in m.get('manifests',[])]"

# Fastest check — pull the manifest and look for multi-arch index
crane manifest <image>:<tag> | jq '[.manifests[]?.platform.architecture]'
# crane: go install github.com/google/go-containerregistry/cmd/crane@latest
```

**The failure mode:** if `arm64` is in the NodePool requirements but an image is `amd64`-only, the pod is scheduled onto a Graviton node and immediately fails with:

```
exec /app/server: exec format error
```

This is not a Karpenter error — it is a container runtime error from the node. To diagnose: `kubectl describe pod <name>` → look for `exec format error` in the Events or `kubectl logs` output. Fix by either building a multi-arch image or removing `arm64` from the NodePool requirements.

### Reserved Instances and Savings Plans

Karpenter does not have explicit knowledge of your Reserved Instances or Savings Plans — it selects On-Demand instances based on cost and fit. AWS billing then automatically applies RIs and SPs post-hoc to matching On-Demand usage in the account and region.

**Implication:** your On-Demand NodePool *is* your RI/SP utilization strategy. If you have `m6i` RIs, include `m6i` in your On-Demand NodePool requirements. Karpenter will provision `m6i` On-Demand instances when cost-optimal, and AWS billing applies the RI discount automatically.

There is no need to manage RI utilization separately — just ensure your NodePool requirements include the families and sizes covered by your commitment. Use AWS Cost Explorer to verify RI utilization is >80% after migration.

### On-Demand Capacity Reservations (ODCR) and Capacity Blocks

Use ODCR or Capacity Blocks when you need **guaranteed** EC2 capacity — ML training runs, regulatory requirements, or DR scenarios where Spot availability cannot be relied on.

Karpenter v1.x supports `capacity-type: on-demand` with ODCR via `EC2NodeClass.spec.capacityReservationSelectorTerms`:

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: reserved-capacity
spec:
  amiSelectorTerms:
    - alias: al2023@latest

  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: my-cluster

  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: my-cluster

  instanceProfile: karpenter-node-profile

  # Target a specific Capacity Reservation or Capacity Block by ID or tag
  capacityReservationSelectorTerms:
    - id: cr-0abc1234def567890        # Specific ODCR ID
    # Or select by tag:
    # - tags:
    #     karpenter.sh/reservation-type: ml-training

  metadataOptions:
    httpTokens: required
    httpPutResponseHopLimit: 1

  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 100Gi
        volumeType: gp3
        encrypted: true

---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: reserved-gpu
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: reserved-capacity
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: [on-demand]       # ODCR uses on-demand capacity type
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: [p4d, p4de, p5]   # Match your reservation instance type exactly
        - key: topology.kubernetes.io/zone
          operator: In
          values: [eu-north-1a]     # ODCR is AZ-specific — must match reservation AZ
  limits:
    cpu: "768"                      # p4d.24xlarge = 96 vCPU; 8 nodes worth
  disruption:
    consolidationPolicy: WhenEmpty  # Never consolidate reserved capacity nodes
```

**Capacity Reservation priority:** Karpenter tries capacity in order: `reservation` → `spot` → `on-demand`. If a Capacity Reservation exists and is not full, Karpenter will use it before going to the open market.

**Check reservation utilization:**
```bash
aws ec2 describe-capacity-reservations \
  --capacity-reservation-ids cr-0abc1234def567890 \
  --query 'CapacityReservations[*].{Total:TotalInstanceCount,Available:AvailableInstanceCount,State:State}'
```

### Blue/green NodePool rotation

When you need to change instance families, AMI, or EC2NodeClass for an entire fleet without triggering mass drift, use blue/green NodePool rotation instead of editing the live NodePool:

```
1. Create new NodePool (e.g. default-v2) with updated config and weight: 200
   — higher weight than the existing pool (weight: 10)

2. New pods scheduled on default-v2; existing pods continue running on default

3. Cordon default NodePool nodes to prevent new scheduling:
   kubectl get nodes -l karpenter.sh/nodepool=default -o name | \
     xargs kubectl cordon

4. Drain default NodePool nodes (PDBs respected):
   kubectl get nodes -l karpenter.sh/nodepool=default -o name | \
     xargs -I{} kubectl drain {} \
       --ignore-daemonsets \
       --delete-emptydir-data \
       --grace-period=120 \
       --timeout=300s

5. Verify all workloads running on default-v2 nodes:
   kubectl get pods -A -o wide | grep -v default-v2

6. Delete the old NodePool (Karpenter terminates its now-empty nodes):
   kubectl delete nodepool default
```

**Why not just edit the NodePool in-place?** Updating instance families, AMI selector, or `EC2NodeClass` reference triggers drift on all nodes simultaneously. With a conservative `disruption.budgets: nodes: "10%"`, a 50-node fleet takes 50 drain cycles. Blue/green gives you explicit control over timing and rollback: if `default-v2` has issues, lower its weight and raise `default` back.

Rollback: lower `default-v2` weight below `default`, uncordon `default` nodes.

### DaemonSet overhead and instance sizing

Karpenter simulates pod placement — including all DaemonSets — before selecting an instance type. Heavy DaemonSets (Datadog agent ~250m CPU + 256Mi, Cilium ~100m + 200Mi, Falco ~200m + 512Mi) consume a significant fraction of smaller instances. This is expected and correct: Karpenter is choosing the cheapest instance that actually fits the workload *plus* its DaemonSets.

If you see pods landing on `xlarge` when you expect `large`, check actual allocatable capacity:

```bash
# See allocatable after DaemonSet overhead on a Karpenter node
kubectl describe node <karpenter-node> | grep -A 6 "Allocatable:"

# See what's consuming resources before your workload pod lands
kubectl describe node <karpenter-node> | grep -A 40 "Non-terminated Pods:"
```

To reduce overhead: review DaemonSet resource requests, remove DaemonSets that are not needed on all nodes (use `nodeSelector` to exclude Karpenter nodes for non-essential agents), or increase `karpenter.k8s.aws/instance-size` minimum.

### Consolidation

Consolidation bin-packs pods onto fewer nodes and terminates the rest. It respects PDBs, `do-not-disrupt` annotations, and `disruption.budgets`.

```yaml
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 5m   # Wait 5 min after underutilisation detected
```

**`consolidateAfter` semantics differ by policy:**
- `WhenEmpty`: timer starts when the node becomes fully empty
- `WhenEmptyOrUnderutilized`: timer resets on every pod scheduling event — a value of `1m` on a busy cluster causes aggressive churn as new pods constantly reset the clock. Use `5m`–`10m` minimum for `WhenEmptyOrUnderutilized`.

If workloads cannot tolerate consolidation (stateful, slow restart), either:
- Set `WhenEmpty` policy (only empty nodes consolidated)
- Annotate the pod: `karpenter.sh/do-not-disrupt: "true"`

### `expireAfter` for node rotation

Nodes that run indefinitely accumulate:
- AMI drift (security patches not applied)
- Log agent memory growth
- Fragmented bin-packing

Set `expireAfter` to force periodic rotation. Karpenter drains and replaces expired nodes one at a time, respecting PDBs.

```yaml
expireAfter: 720h   # 30 days — rotate monthly
```

For compliance environments requiring shorter rotation: `168h` (7 days).

### EKS cluster upgrade → node rotation workflow

When you upgrade the EKS control plane, worker nodes must be rotated to the new Kubernetes version. With Karpenter this is automatic if you use AMI aliases — but the sequence matters:

```
1. Upgrade EKS control plane
   aws eks update-cluster-version --name <cluster> --kubernetes-version 1.31

2. Wait for control plane upgrade to complete
   aws eks wait cluster-active --name <cluster>

3a. If using alias (al2023@latest):
    SSM parameter auto-updates → Karpenter detects AMI drift → nodes replaced rolling
    (no manual action needed, but watch disruption budgets)

3b. If using pinned AMI ID:
    Find the new EKS-optimised AMI for the new version:
    aws ssm get-parameter \
      --name /aws/service/eks/optimized-ami/1.31/amazon-linux-2023/x86_64/standard/recommended/image_id \
      --query Parameter.Value --output text
    Update EC2NodeClass amiSelectorTerms[].id → commit/merge → Karpenter drifts nodes

4. Monitor replacement progress
   kubectl get nodeclaim -A -w
   kubectl get nodes -o wide | grep -v v1.31   # Should go to zero

5. Verify workloads healthy after rotation
   kubectl get pods -A | grep -v Running | grep -v Completed
```

**Potential blockers during upgrade rotation:**

| Blocker | Symptom | Fix |
|---|---|---|
| PDB blocks drain | Node stays `SchedulingDisabled` for > 10m | Check `kubectl get pdb -A`, ensure `minAvailable` allows one replica down |
| `do-not-disrupt` annotation | Node never drained | Remove annotation, or wait for KEDA/HPA to scale the pod down first |
| `disruption.budgets: nodes: "0"` | No nodes replaced | Check budget schedule — may have a "no disruption during business hours" rule |
| Old nodes accumulating | NodePool `terminationGracePeriod` too long | Expected — nodes drain slowly; check `kubectl describe nodeclaim` for eviction status |

### Stateful workload protection recipe

For Kafka, Redis, Postgres, or any workload that cannot tolerate abrupt termination, use all three layers together:

```yaml
# 1. PDB — prevents simultaneous eviction during drain (Karpenter and kubectl drain both respect this)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: redis
  namespace: cache
spec:
  minAvailable: 2     # For a 3-replica StatefulSet: always keep 2 running
  selector:
    matchLabels:
      app: redis

---
# 2. Pod annotation — blocks consolidation and expiration on the node hosting this pod.
#    Add to the StatefulSet pod template, not just one pod.
metadata:
  annotations:
    karpenter.sh/do-not-disrupt: "true"

---
# 3. Match terminationGracePeriodSeconds to your actual shutdown time
spec:
  terminationGracePeriodSeconds: 300   # Must be >= your shutdown + checkpoint time
```

**When to remove `do-not-disrupt`:**
Do not leave it permanent — it prevents AMI rotation and consolidation indefinitely. Tie it to a maintenance window:

```bash
# Remove do-not-disrupt during a maintenance window to allow expiration/drift replacement
kubectl patch statefulset redis -n cache \
  --type=json \
  -p='[{"op":"remove","path":"/spec/template/metadata/annotations/karpenter.sh~1do-not-disrupt"}]'

# Re-add after replacement completes
kubectl patch statefulset redis -n cache \
  --type=merge \
  -p='{"spec":{"template":{"metadata":{"annotations":{"karpenter.sh/do-not-disrupt":"true"}}}}}'
```

---

## Disruption Strategy

### Disruption types

| Type | Trigger | Controlled? |
|---|---|---|
| Consolidation | Node underutilised or empty | Yes — respects PDBs and budgets |
| Drift | NodePool, EC2NodeClass, or AMI changed | Yes — rolling replacement |
| Expiration | `expireAfter` TTL elapsed | Yes — sequential drain |
| Interruption | Spot 2-minute notice (via SQS) | Reactive — Karpenter pre-empts AWS |

### Disruption budgets

```yaml
disruption:
  budgets:
    - nodes: "10%"             # Default: max 10% of NodePool nodes disrupted concurrently
    - schedule: "0 8 * * 1-5" # Business hours: no disruption
      duration: 8h
      nodes: "0"
    - schedule: "0 0 * * 6"   # Saturday midnight: allow up to 50% (maintenance window)
      duration: 6h
      nodes: "50%"
```

### Pod-level disruption protection

```yaml
# PodDisruptionBudget — protects the deployment during node drain
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: orders-api
  namespace: orders
spec:
  minAvailable: 1       # or maxUnavailable: 1
  selector:
    matchLabels:
      app: orders-api
```

```yaml
# Per-pod opt-out of disruption (use sparingly — prevents consolidation)
metadata:
  annotations:
    karpenter.sh/do-not-disrupt: "true"
```

### Spot interruption handling

When Karpenter receives a Spot interruption notice via SQS:
1. Marks the NodeClaim for termination
2. Cordons the node
3. Begins pod eviction with a 2-minute grace window
4. Provisions a replacement node concurrently

For this to work: the interruption queue must be created, EventBridge rules wired, and the controller must have `sqs:ReceiveMessage` / `sqs:DeleteMessage` permissions.

---

## Security

### Tag protection

The `karpenter.sh/discovery` tag on subnets and security groups is the access gate. Protect it:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Deny",
    "Action": ["ec2:CreateTags", "ec2:DeleteTags"],
    "Resource": "*",
    "Condition": {
      "ForAnyValue:StringLike": {
        "aws:TagKeys": ["karpenter.sh/*"]
      },
      "StringNotEquals": {
        "aws:PrincipalARN": "arn:aws:iam::<account>:role/karpenter-controller"
      }
    }
  }]
}
```

### IMDSv2 enforcement

`httpTokens: required` + `httpPutResponseHopLimit: 1` prevents pods (hop 2) from accessing instance metadata. Without this, any pod can reach IMDS and retrieve the node IAM role credentials.

```yaml
# In EC2NodeClass:
metadataOptions:
  httpTokens: required
  httpPutResponseHopLimit: 1
```

### EBS encryption

Always set `ebs.encrypted: true` in `blockDeviceMappings`. If your AWS account has a default EBS encryption KMS key, you can omit the `kmsKeyID` field — Karpenter will use the account default.

### Node IAM role scope

The node IAM role (attached via instance profile) should have only:
- `AmazonEKSWorkerNodePolicy`
- `AmazonEKS_CNI_Policy`
- `AmazonEC2ContainerRegistryReadOnly`

Do not attach `AdministratorAccess` or any IAM management permissions to the node role. Karpenter's controller role is separate.

---

## Private Cluster

In private clusters (no public EKS API endpoint), nodes must reach the API server and AWS services via VPC endpoints.

### Required VPC endpoints

| Endpoint | Type | Used for |
|---|---|---|
| `ec2` | Interface | Karpenter launching instances |
| `ecr.api` | Interface | Image pulls |
| `ecr.dkr` | Interface | Image pulls |
| `s3` | Gateway | ECR layer pulls |
| `sqs` | Interface | Interruption queue |
| `ssm` | Interface | SSM parameter for AMI resolution |
| `ssmmessages` | Interface | SSM Session Manager (optional but recommended) |
| `sts` | Interface | IRSA token exchange |

```bash
# Check which endpoints exist
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --query 'VpcEndpoints[*].{Service:ServiceName,State:State}'
```

### Karpenter on Fargate (recommended for control plane isolation)

Run the Karpenter controller on a Fargate profile so it never depends on Karpenter-managed nodes:

```bash
aws eks create-fargate-profile \
  --cluster-name <cluster> \
  --fargate-profile-name karpenter \
  --pod-execution-role-arn arn:aws:iam::<account>:role/eks-fargate-role \
  --selectors '[{"namespace":"karpenter"}]'
```

---

## Karpenter + Fargate Coexistence

Some workloads must run on Fargate (network isolation, compliance, or specific IAM requirements) while others run on Karpenter-managed nodes. The risk: if no Fargate profile selector is exclusive, Karpenter may attempt to provision a node for a pod that should land on Fargate, and both fight over scheduling.

**Pattern: use dedicated namespaces or labels to separate Fargate and Karpenter workloads**

```yaml
# Fargate profile — selects by namespace label (created via eksctl or Terraform)
# All pods in namespace 'secure-workloads' go to Fargate
aws eks create-fargate-profile \
  --cluster-name my-cluster \
  --fargate-profile-name secure \
  --pod-execution-role-arn arn:aws:iam::<account>:role/eks-fargate-role \
  --selectors '[{"namespace":"secure-workloads"}]'

# NodePool — exclude Fargate-targeted namespaces using nodeSelector
# Pods in 'secure-workloads' namespace will never match this NodePool because
# Karpenter only acts on pods that are not already matched by a Fargate profile.
# Karpenter and the Fargate scheduler do not interfere — the EKS scheduler
# assigns Fargate pods before Karpenter sees them as unschedulable.
```

**How the scheduler arbitrates:** when a pod is created in a namespace matched by a Fargate profile, the EKS Fargate scheduler binds it to a Fargate node. Karpenter only sees pods that remain `Pending` with no node binding — so Fargate-bound pods never reach Karpenter's scheduling queue.

**Common trap: Karpenter controller itself**

The Karpenter controller pod must run on a Fargate profile or a pre-existing MNG — never on a Karpenter-managed node. If the controller is on a Karpenter node and that node is disrupted, Karpenter cannot provision a replacement for itself.

```bash
# Verify Karpenter controller is on Fargate or a non-Karpenter node
kubectl get pod -n karpenter -l app.kubernetes.io/name=karpenter -o wide
kubectl get node <node-name> -o jsonpath='{.metadata.labels.karpenter\.sh/nodepool}'
# Should be empty (not a Karpenter-managed node) or show "fargate"
```

---

## Using Karpenter with KEDA

When KEDA scales up a Deployment and no node has capacity, pods go Pending. Karpenter detects these and provisions nodes — the combined flow is:

```
KEDA detects queue depth → scales Deployment replicas →
pods Pending (no node) → Karpenter provisions node → pods schedule
```

**Timing**: Expect 30–60s from KEDA scale event to pod running. If your workload has an SLA tighter than 60s, use `minReplicaCount: 1` in KEDA (keep one warm pod) and `minValues` in Karpenter (keep standby capacity).

**Spot interruption + KEDA**: When a Spot node is interrupted, KEDA-managed pods evict and reschedule. Karpenter provisions a replacement node concurrently. Set `minReplicaCount: 1` in your ScaledObject so the replacement pod can schedule before the queue backs up.

**`do-not-disrupt` risk**: If you annotate KEDA-managed pods with `karpenter.sh/do-not-disrupt: "true"`, consolidation is blocked until those pods are evicted by KEDA scale-in. This is usually correct — let KEDA own scale-in timing, let Karpenter own consolidation timing.

---

## Migration from Cluster Autoscaler

### Why CA and Karpenter must not coexist on the same nodes

CA manages Managed Node Groups (MNGs). If Karpenter also provisions nodes, both controllers may attempt to provision or remove the same capacity. CA does not understand `NodeClaim` and will try to scale up MNGs when Karpenter is already handling the request — this doubles cost and confuses both controllers.

**Correct migration sequence:**

1. Install Karpenter, create NodePool/EC2NodeClass, verify `Ready=True`
2. Scale CA to 0 replicas (`kubectl scale deployment cluster-autoscaler -n kube-system --replicas=0`) — do not delete yet
3. Cordon CA-managed nodes
4. Drain nodes — PDBs are respected; do not use `--force` unless no PDB exists
5. Verify all workloads running on Karpenter nodes
6. Delete CA deployment, ClusterRole, ClusterRoleBinding, and ServiceAccount
7. Optionally reduce MNG `minSize` to 0 or delete the MNG

### Annotations that block drain

```bash
# Find pods blocking eviction
kubectl get pods -A -o json | jq '
  .items[] |
  select(.metadata.annotations["cluster-autoscaler.kubernetes.io/safe-to-evict"] == "false") |
  {name: .metadata.name, ns: .metadata.namespace}
'
```

These pods must either be deleted or have the annotation removed before drain proceeds.

---

## Troubleshooting

### Diagnostic commands

```bash
# NodePool status and limit usage
kubectl get nodepool -A
kubectl describe nodepool <name>

# NodeClaim lifecycle
kubectl get nodeclaim -A
kubectl describe nodeclaim <name>   # Conditions block shows why it's stuck

# Karpenter controller logs (most signal is here)
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter \
  --since=30m --tail=300

# Pending pods
kubectl get pods -A --field-selector=status.phase=Pending
kubectl describe pod <name> -n <ns>   # Events: FailedScheduling tells you why
```

### Common problems

#### Pods stuck Pending: `0/3 nodes are available: 3 node(s) didn't match NodePool`

The pod's `nodeSelector`, `tolerations`, or `affinity` excludes all NodePools.

```bash
# Check what the pod requires
kubectl describe pod <name> -n <ns> | grep -A 20 "Node-Selectors\|Tolerations\|Affinity"

# Check what NodePool offers
kubectl describe nodepool <name> | grep -A 30 "Requirements"
```

Common mismatch: pod requires `kubernetes.io/os: linux` but NodePool has no OS requirement defined; or pod has a taint toleration that NodePool applies via `taints` but the pod does not tolerate it.

#### NodeClaim stuck in `Pending` phase

```bash
kubectl describe nodeclaim <name>
# Look for Conditions: Launched=False
# Common message: "UnauthorizedOperation" → IAM policy missing
# Common message: "InsufficientCapacityError" → Spot family too narrow
# Common message: "InvalidParameterValue: subnet" → subnet tags missing
```

For IAM errors:
```bash
# Test from inside the karpenter namespace
kubectl run -it --rm iamtest \
  --image=amazon/aws-cli \
  --serviceaccount=karpenter \
  --namespace=karpenter \
  -- ec2 describe-instance-types --region eu-north-1 --max-items 1
```

#### Node registers but immediately goes NotReady

Bootstrap failure — the node joined the cluster but kubelet or CNI failed.

```bash
# Get the node's cloud-init logs via SSM (if SSM agent is running)
aws ssm start-session --target <instance-id>
sudo journalctl -u cloud-init -n 200
sudo journalctl -u kubelet -n 200
```

Common causes:
- Wrong security group (kubelet cannot reach EKS API server)
- IAM permissions missing for CNI (`ec2:AssignPrivateIpAddresses`)
- AL2023 user-data format error (must be `nodeadm` YAML, not bash)

#### NodePool limits exhausted

```bash
kubectl describe nodepool <name> | grep -A 5 "Status"
# Resources: cpu=850/1000 (85% used)
```

Either raise `limits` or add a second NodePool with overflow capacity.

#### Consolidation evicting pods unexpectedly

Add a PDB for affected workloads and set `disruption.budgets` in the NodePool. To diagnose which pod was evicted:

```bash
# Disruption reason
kubectl get node <name> -o jsonpath='{.annotations.karpenter\.sh/disruption-reason}'

# Events
kubectl get events -n <workload-ns> \
  --field-selector reason=Evicted \
  --sort-by='.lastTimestamp'
```

#### Spot interruption not handled (pods not pre-emptively evicted)

Check the interruption queue is receiving messages:

```bash
aws sqs get-queue-attributes \
  --queue-url <queue-url> \
  --attribute-names NumberOfMessagesReceived \
  --region eu-north-1

# Verify EventBridge rule is enabled
aws events describe-rule --name KarpenterSpotInterruption --region eu-north-1
```

Check Karpenter has SQS permissions and the `settings.interruptionQueue` Helm value is set to the correct queue name.

#### Pods stuck Pending: topology spread constraints unsatisfiable

When pods have `topologySpreadConstraints` (common for HA across AZs), Karpenter respects these — but if the constraint cannot be satisfied given the available subnets or existing nodes, pods stay Pending with a misleading scheduling message.

```bash
# Look for this in pod events
kubectl describe pod <name> -n <ns> | grep -A 5 "didn't match pod's topology spread"
# or
kubectl describe pod <name> -n <ns> | grep -A 5 "ErrTopologySpreadConstraintNotSatisfiable"
```

Common causes:

| Symptom | Root cause | Fix |
|---|---|---|
| `maxSkew: 1` with 3 AZs but only 2 subnets tagged | Karpenter can only provision in 2 AZs | Tag subnets in all 3 AZs with `karpenter.sh/discovery` |
| Spread `whenUnsatisfiable: DoNotSchedule` blocks new pods | Existing pods already skewed | Temporarily set `whenUnsatisfiable: ScheduleAnyway` to unblock, then rebalance |
| `minDomains: 3` but only 2 nodes exist | Not enough existing topology domains | Scale up first or lower `minDomains` |
| Spread by `node` but consolidation collapses nodes to 1 | Consolidation violates spread | Add `do-not-disrupt` to spread-sensitive pods or use `WhenEmpty` consolidation |

---

## GitOps Integration

### Flux ordering

Karpenter CRDs must exist before NodePool/EC2NodeClass are applied:

```yaml
# infrastructure/karpenter/kustomization.yaml — installs Helm chart + CRDs
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: karpenter
  namespace: flux-system
spec:
  interval: 10m
  path: ./infrastructure/karpenter
  dependsOn:
    - name: eks-addons        # cluster-autoscaler removal happens here
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: karpenter
      namespace: karpenter

---
# infrastructure/karpenter-config/kustomization.yaml — NodePool + EC2NodeClass
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: karpenter-config
  namespace: flux-system
spec:
  interval: 10m
  path: ./infrastructure/karpenter-config
  dependsOn:
    - name: karpenter           # CRDs must exist first
  postBuild:
    substitute:
      CLUSTER_NAME: my-cluster
      NODE_ROLE_ARN: arn:aws:iam::123456789012:role/karpenter-node
```

### Argo CD ordering

Karpenter CRDs must exist before NodePool/EC2NodeClass are applied. Use `syncWave` annotations to enforce ordering:

```yaml
# Application: karpenter Helm chart (wave -1 — installs CRDs first)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: karpenter
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  source:
    repoURL: public.ecr.aws/karpenter
    chart: karpenter
    targetRevision: "1.12.1"
    helm:
      values: |
        settings:
          clusterName: my-cluster
          interruptionQueue: karpenter-my-cluster
  destination:
    server: https://kubernetes.default.svc
    namespace: karpenter
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true   # Required for Karpenter CRD installation

---
# Application: karpenter-config (NodePool + EC2NodeClass, wave 0 — after CRDs)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: karpenter-config
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  source:
    repoURL: https://github.com/my-org/gitops
    path: infrastructure/karpenter-config
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: karpenter
```

**`ignoreDifferences` — prevent OutOfSync noise:**

Argo CD diffs Karpenter-managed status fields and marks NodePool/EC2NodeClass as OutOfSync after every reconciliation. Suppress this with `ignoreDifferences`:

```yaml
# In the karpenter-config Application spec:
spec:
  ignoreDifferences:
    - group: karpenter.sh
      kind: NodePool
      jsonPointers:
        - /status
        - /metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration
    - group: karpenter.k8s.aws
      kind: EC2NodeClass
      jsonPointers:
        - /status
        - /spec/amiSelectorTerms    # Karpenter resolves alias → ID; Argo CD sees drift
```

The `amiSelectorTerms` `ignoreDifferences` entry is particularly important: when you use `alias: al2023@latest`, Karpenter resolves this to an actual AMI ID in the status. Argo CD then sees a diff between the alias in Git and the resolved ID in-cluster and marks the resource OutOfSync on every sync cycle.

### Drift via GitOps

When a NodePool or EC2NodeClass is updated via a Git push and Flux/Argo CD reconciles it, Karpenter detects the change and marks affected nodes as **drifted**. Drift replacement is automatic and rolling — it respects PDBs and `disruption.budgets`.

This means a GitOps push to change an AMI pin or instance family list triggers a node fleet rolling replacement. Treat NodePool/EC2NodeClass changes as you would a Deployment image update — use PRs and review blast radius before merging.

---

## FinOps and Cost Attribution

### Tag-based cost allocation

Karpenter nodes inherit tags from `EC2NodeClass.spec.tags`. Use these to attribute node costs to teams, environments, and services:

```yaml
# EC2NodeClass tags — applied to all EC2 instances and EBS volumes
tags:
  Environment: production
  Team: platform
  CostCenter: eng-platform-001
  karpenter.sh/discovery: my-cluster
```

Enable these tags as **AWS Cost Allocation Tags** in the Billing console so they appear in Cost Explorer and Cost and Usage Report.

```bash
# Check which tags are active as cost allocation tags
aws ce list-cost-allocation-tags \
  --status Active \
  --query 'CostAllocationTags[*].TagKey'

# Activate a new tag (takes up to 24h to appear in reports)
aws ce update-cost-allocation-tags-status \
  --cost-allocation-tags-status TagKey=Team,Status=Active
```

### Per-NodePool cost visibility

Add a `nodepool` label to each NodePool's node template so you can filter costs by pool:

```yaml
spec:
  template:
    metadata:
      labels:
        nodepool: spot-flex   # visible in kubectl, Datadog, Kubecost
    spec:
      nodeClassRef:
        name: spot-flex
```

```bash
# See current node cost breakdown by NodePool (requires Kubecost or OpenCost)
kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090
# Or query the Kubecost API:
curl "http://localhost:9090/model/allocation?window=1d&aggregate=label:nodepool"
```

### Savings tracking after CA → Karpenter migration

Key metrics to report to stakeholders after migration:

```bash
# Average node utilization (higher = better bin-packing)
kubectl top nodes | awk 'NR>1 {print $3}' | sort -n

# Node count trend (should decrease with consolidation)
kubectl get nodes --no-headers | wc -l

# Spot vs On-Demand ratio (Spot ~70-80% cheaper)
kubectl get nodes -o json | jq '[.items[] | .metadata.labels."karpenter.sh/capacity-type"] | group_by(.) | map({type: .[0], count: length})'
```

---

## Observability

### Karpenter Prometheus metrics

```bash
kubectl port-forward -n karpenter svc/karpenter 8080:8080
curl localhost:8080/metrics | grep karpenter_
```

| Metric | Alert threshold | Meaning |
|---|---|---|
| `karpenter_nodes_total` | Sudden drop | Node fleet size — watch for unexpected drain |
| `karpenter_nodeclaims_total{phase="Pending"}` | > 0 for > 5m | NodeClaims stuck in launch |
| `karpenter_provisioner_scheduling_queue_depth` | > 0 for > 5m | Pods waiting for node provision |
| `karpenter_interruption_received_messages_total` | Rate spike | Spot capacity pressure |
| `karpenter_disruption_evaluation_duration_seconds` | p99 > 30s | Consolidation loop slow |
| `karpenter_nodeclaims_disrupted_total` | Unexpected spike | Unplanned disruption event |

### Recommended alerts

```yaml
# NodeClaim stuck launching for > 5 minutes
- alert: KarpenterNodeClaimStuck
  expr: karpenter_nodeclaims_total{phase="Pending"} > 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Karpenter NodeClaim stuck in Pending"
    description: "{{ $value }} NodeClaim(s) have been Pending for > 5 minutes"

# No nodes in NodePool (unexpected drain)
- alert: KarpenterNodePoolEmpty
  expr: karpenter_nodes_total == 0
  for: 2m
  labels:
    severity: critical
```

---

## Version Compatibility

| Karpenter | EKS (Kubernetes) | Helm chart |
|---|---|---|
| v1.12.x (latest) | 1.29–1.35 | 1.12.x |
| v1.9.x | 1.29–1.35 | 1.9.x |
| v1.5.x | 1.29–1.33 | 1.5.x |
| v1.2.x | 1.29–1.32 | 1.2.x |
| v1.0.x | 1.29–1.31 | 1.0.x |

Minimum Kubernetes version per Karpenter release (from the official compatibility matrix):

| Kubernetes | Min Karpenter |
|---|---|
| 1.29 | >= 0.34 |
| 1.30 | >= 0.37 |
| 1.31 | >= 1.0.5 |
| 1.32 | >= 1.2 |
| 1.33 | >= 1.5 |
| 1.34 | >= 1.6 |
| 1.35 | >= 1.9 |

Always check the [Karpenter compatibility matrix](https://karpenter.sh/docs/upgrading/compatibility/) before upgrading EKS or Karpenter independently.

### Upgrade checklist (patch/minor)

1. Read release notes for changed defaults or deprecated fields
2. `helm diff upgrade` to preview changes
3. `helm upgrade --atomic --timeout 5m` — rolls back automatically on failure
4. Verify: `kubectl describe nodepool` shows `Ready=True`, no stuck NodeClaims
5. Rollback: `helm rollback karpenter -n karpenter` — NodePools/EC2NodeClasses preserved in etcd

### Webhook timeout tuning for large clusters

On clusters with 500+ nodes or high pod churn, the Karpenter admission webhook can time out during rolling updates or large deployments. Symptoms: pod admission hangs for 10–30 seconds, `context deadline exceeded` in kube-apiserver logs, or NodeClaim creation slows to a crawl.

**Diagnosis:**
```bash
# Check for webhook timeout errors in API server audit logs or kube-apiserver pods
kubectl logs -n kube-system -l component=kube-apiserver --tail=200 | \
  grep -i "karpenter\|webhook\|timeout\|deadline"

# Check Karpenter webhook pod responsiveness
kubectl get validatingwebhookconfigurations | grep karpenter
kubectl describe validatingwebhookconfiguration \
  validation.webhook.karpenter.sh | grep -A 5 "Timeout"
```

**Fix:** increase the webhook timeout and controller resource limits:

```bash
helm upgrade karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "1.12.1" \
  --namespace karpenter \
  --reuse-values \
  --set "webhook.timeoutSeconds=30" \
  --set "controller.resources.requests.cpu=2" \
  --set "controller.resources.requests.memory=2Gi" \
  --set "controller.resources.limits.cpu=4" \
  --set "controller.resources.limits.memory=4Gi"
```

Default webhook timeout is 10 seconds — increase to 30s for clusters with >300 nodes. Controller resource defaults (1 CPU / 1Gi) are tuned for small clusters; increase proportionally with fleet size.

**Batch scheduling:** if a large Deployment (500+ pods) is created simultaneously, Karpenter may queue NodeClaim creation. This is normal — Karpenter batches scheduling decisions every `--batch-max-duration` (default 10s). Increase if you need faster bulk provisioning:

```bash
helm upgrade karpenter ... --set "controller.env[0].name=BATCH_MAX_DURATION" \
  --set "controller.env[0].value=30s"
```

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

# 4. Tag subnets and security groups for discovery
aws ec2 create-tags \
  --resources <subnet-id> <subnet-id-2> \
  --tags Key=karpenter.sh/discovery,Value=<cluster-name>

aws ec2 create-tags \
  --resources <security-group-id> \
  --tags Key=karpenter.sh/discovery,Value=<cluster-name>
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

      # Prevent pods from scheduling until DaemonSets (e.g. CNI, log agent) are ready
      startupTaints:
        - key: karpenter.sh/not-ready
          effect: NoSchedule

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
    consolidateAfter: 1m          # How long a node must be underutilised before consolidation

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

Verify images are multi-arch before enabling: `docker manifest inspect <image> | grep -i arch`.

### Consolidation

Consolidation bin-packs pods onto fewer nodes and terminates the rest. It respects PDBs, `do-not-disrupt` annotations, and `disruption.budgets`.

```yaml
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 5m   # Wait 5 min after underutilisation detected
```

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

### Drift via GitOps

When a NodePool or EC2NodeClass is updated via a Git push and Flux reconciles it, Karpenter detects the change and marks affected nodes as **drifted**. Drift replacement is automatic and rolling — it respects PDBs and `disruption.budgets`.

This means a GitOps push to change an AMI pin or instance family list triggers a node fleet rolling replacement. Treat NodePool/EC2NodeClass changes as you would a Deployment image update — use PRs and review blast radius before merging.

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

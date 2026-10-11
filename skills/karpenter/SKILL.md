---
name: karpenter
description: Design, install, debug, review, plan capacity, audit scaling history, migrate from Cluster Autoscaler, and upgrade Karpenter v1.x on EKS. Covers NodePool, EC2NodeClass, NodeClaim, Spot diversity, disruption strategy, Pod Identity/IRSA, interruption queue, private clusters, AMI rotation, and GitOps integration. Use when asked to "set up Karpenter", "debug why nodes aren't provisioning", "review my NodePool", "what would Karpenter provision for this workload", "why did this node terminate", "migrate from CA", or "upgrade Karpenter".
argument-hint: "[generate|debug|review|audit|plan|migrate|upgrade] [description or file path]"
title: "Karpenter Command"
sidebar_label: "karpenter"
custom_edit_url: null
---

Design, install, debug, review, plan capacity, audit, migrate, and upgrade Karpenter on EKS.

# Verify current stable version before installing (Karpenter uses OCI, not a Helm repo):
crane ls public.ecr.aws/karpenter/karpenter | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -5
# Pin to the version from that output, e.g.:
# helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version x.y.z

All guidance targets the `karpenter.sh/v1` API. The v0.x `Provisioner`/`AWSNodeTemplate` API was removed in v1.0 — if you are on v0.x, use `migrate` mode first.

---

## Interactive Wizard (fires when no arguments are provided)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. generate — design NodePool and EC2NodeClass from requirements
  2. debug    — diagnose why nodes are not provisioning or pods are stuck Pending
  3. review   — production-readiness review of existing NodePool/EC2NodeClass
  4. audit    — reconstruct scale-out/scale-in history and explain why it happened
  5. plan     — predict what Karpenter would provision for a given workload before deploying
  6. migrate  — move from Cluster Autoscaler to Karpenter
  7. upgrade  — upgrade Karpenter version (including v0.x → v1.x CRD migration)

Enter 1–7 or mode name:
```

**Q2 — Environment context** (ask after mode, one question at a time):

```
1. EKS cluster version?  (e.g. 1.29, 1.30, 1.31)
2. Karpenter version currently installed (or target version for fresh install)?
3. Identity method for Karpenter controller?
     a) EKS Pod Identity  (recommended, requires EKS 1.24+)
     b) IRSA              (IAM Roles for Service Accounts)
4. Is this a private cluster (no public API endpoint)?  [yes/no]
5. Do you use Spot instances?  [yes / no / mixed]
6. Are you migrating from Cluster Autoscaler?  [yes/no]
```

Use the answers to set defaults for every section below. If the user pastes a manifest or error, infer as much as possible and skip questions already answered.

---

## Mode: generate

Design a production-ready NodePool and EC2NodeClass from requirements.

**Steps:**

1. Collect (or infer from context):
   - Workload profile: general-purpose / compute-optimised / memory-optimised / GPU / Spot-flex
   - Instance family preferences (e.g. `m`, `c`, `r`, `g4dn`) and architecture (`amd64`, `arm64`/Graviton, or both)
   - AMI family: `AL2023` (default, recommended) | `Bottlerocket` | `Windows2022`
   - Environment: **dev/staging** or **production** — this drives the AMI strategy
   - Whether scale-to-zero is needed (requires `limits` planning)
   - Disruption tolerance: can workloads survive consolidation? Are there PDBs?
   - GitOps method: Flux / Argo CD / direct kubectl

2. Generate `EC2NodeClass` with:
   - `amiSelectorTerms`: use `alias: al2023@latest` for dev/staging; use a **pinned AMI ID** (`id: ami-xxxx`) for production. Floating `@latest` in production means an untested AMI can land on fleet nodes during any scheduled SSM parameter update. Ask the user which environment this is for before choosing.
   > Ask user: "What is your EKS cluster name?" — substitute into `karpenter.sh/discovery: <cluster-name>` before applying.
   - `subnetSelectorTerms` and `securityGroupSelectorTerms` using `karpenter.sh/discovery: <cluster-name>` tags
   - `instanceProfile` or `role` matching the Karpenter node IAM role
   - `blockDeviceMappings` with encrypted EBS and IMDSv2 enforced via `metadataOptions`
   - `tags` including at minimum `karpenter.sh/discovery`, `Environment`, and billing tags

3. Generate `NodePool` with:
   - `spec.template.spec.requirements` covering at least 3 instance families and both `On-Demand`/`Spot` capacity types (or explicit single type)
   - `minValues` on instance family or size requirements to guarantee Spot diversity
   - `limits` on CPU and memory — **never omit**, uncapped NodePools can runaway
   - `weight` if this is one of multiple NodePools (higher weight = preferred)
   - `disruption` block: `consolidationPolicy`, `consolidateAfter`, `budgets`
   - `expireAfter` set to `720h` (30 days) unless the user has a reason to extend

4. Generate companion resources:
   - IRSA or Pod Identity IAM policy (minimum permissions — see references)
   - `PodDisruptionBudget` for stateful workloads that will land on Karpenter nodes
   - Flux `Kustomization` dependency or Argo CD `syncWave` annotation if GitOps is in use

5. Show validation:
   ```bash
   kubectl apply --dry-run=server -f ec2nodeclass.yaml
   kubectl apply --dry-run=server -f nodepool.yaml
   kubectl describe nodepool <name>   # check Conditions: Ready=True
   ```

Reference: `references/karpenter.md` → NodePool design, EC2NodeClass, IAM

**Rollback:** `kubectl delete nodepool <name> && kubectl delete ec2nodeclass <name>` — Karpenter immediately stops provisioning nodes from these templates. Existing nodes remain until drained by the scheduler or TTL.

---

## Mode: debug

Diagnose why pods are stuck Pending or nodes are not provisioning.

**Steps:**

1. Collect evidence first — do not suggest fixes before seeing output:
   ```bash
   # Pending pods and their scheduling failure reason
   kubectl get pods -A --field-selector=status.phase=Pending
   kubectl describe pod <name> -n <ns>   # look for Events: FailedScheduling

   # NodeClaim lifecycle
   kubectl get nodeclaim -A
   kubectl describe nodeclaim <name>     # look for Conditions block

   # NodePool status
   kubectl get nodepool -A
   kubectl describe nodepool <name>      # look for: Ready condition, limits

   # Karpenter controller logs (most diagnostic signal is here)
   kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter \
     --since=30m --tail=200

   # Node registration failures
   kubectl get nodes
   kubectl describe node <new-node-name>   # look for NotReady or taint issues
   ```

2. Work through this decision tree in order:

   | Symptom | Most likely cause | Field to check |
   |---|---|---|
   | `No NodePool found` in pod events | No NodePool matches pod requirements | NodePool `requirements` vs pod `nodeSelector`/`tolerations` |
   | `NodePool at resource limit` | NodePool `limits` exhausted | `kubectl describe nodepool` → Current Usage |
   | `NodeClaim stuck Pending` | IAM error launching instance | Karpenter logs for `EC2 error`, `UnauthorizedOperation` |
   | `NodeClaim launched but node NotReady` | Bootstrap failure, security group, subnet | `kubectl describe node`, user-data cloud-init logs |
   | `Spot capacity unavailable` | Single AZ or narrow instance family | Add instance families, enable multi-AZ subnets |
   | `Node registers then terminates immediately` | Drift triggered on launch | Check AMI selector — SSM alias resolved to drifted AMI |
   | `Pods evicted unexpectedly` | Consolidation or expiration | Node annotation `karpenter.sh/disruption-reason` |
   | Private cluster: `node never registers` | Karpenter cannot reach EC2/SQS APIs | VPC endpoints: EC2, SQS, ECR, SSM, S3 |

3. For IAM errors — test the exact API calls Karpenter makes:
   ```bash
   # Test from a pod in the karpenter namespace using the controller SA
   kubectl run -it --rm debug --image=amazon/aws-cli \
     --serviceaccount=karpenter -n karpenter -- \
     aws ec2 describe-instance-types --region eu-north-1
   ```

4. State the most likely root cause with the exact field or annotation to fix. Show the corrected spec section. Show the command to verify the fix worked.

Reference: `references/karpenter.md` → Troubleshooting

**Rollback:** If you edited NodePool/EC2NodeClass during debug: `kubectl apply -f <original-backup>.yaml` to restore. Always take a backup before editing: `kubectl get nodepool <name> -o yaml > nodepool-backup.yaml`.

---

## Mode: review

Production-readiness review of NodePool and EC2NodeClass manifests.

Review in this exact priority order:

**Correctness**
- Does `EC2NodeClass.spec.instanceProfile` or `.spec.role` reference a valid node IAM role?
- Are `subnetSelectorTerms` and `securityGroupSelectorTerms` using stable selectors (tags, not names which can change)?
- Does `NodePool.spec.template.spec.nodeClassRef.name` match the `EC2NodeClass` metadata name?
- Are `requirements` satisfiable — does the cluster have subnets in the selected AZs with enough IP space?
- Is `limits` set? An uncapped NodePool will provision nodes without bound on runaway workloads.

**Cost**
- Are at least 3 instance families listed for Spot (narrow families = frequent `InsufficientCapacityError`)?
- Is `minValues` set on instance family or size requirements to enforce Spot diversity?
- Is Graviton (`arm64`) included where workloads support it (~20% cheaper on EC2)?
- Is `consolidationPolicy: WhenEmptyOrUnderutilized` enabled? Idle nodes are silent cost leaks.
- Is `expireAfter` set? Nodes that run indefinitely accumulate AMI drift and resist consolidation.

**Reliability**
- Are PDBs in place for workloads that will land on these nodes?
- Does `disruption.budgets` protect critical workloads from simultaneous eviction?
- Is `terminationGracePeriod` set on the NodePool (default 48h — may be too long or too short)?
- Does `startupTaints` prevent workloads scheduling onto nodes before DaemonSets are ready?

**Security**
- Is `amiSelectorTerms` using `alias: al2023@latest` or a pinned, scanned AMI ID? (Floating `latest` in production means untested AMIs can land on nodes.)
- Is EBS encrypted? (`blockDeviceMappings[].ebs.encrypted: true`)
- Is IMDSv2 enforced? (`metadataOptions.httpTokens: required`, `httpPutResponseHopLimit: 1`)
- Do EC2 instance tags include `karpenter.sh/discovery: <cluster-name>` — and is this tag protected by an SCP/tag policy against modification?
- Does the node IAM role follow least privilege? (No `ec2:*`, no `iam:*`)

**GitOps safety**
- Does the Flux/Argo Kustomization `dependsOn` the Karpenter Helm release so CRDs exist before NodePool?
- Is the IAM role ARN injected via `postBuild.substitute` or Argo CD `ApplicationSet` parameter, not hardcoded?

Separate findings into:
- **Critical** — must fix before deploying to production
- **Improvement** — should fix (cost, resilience)
- **Note** — informational (consider Graviton, document disruption tolerance)

Reference: `references/karpenter.md` → NodePool design, Security, Cost strategy

---

## Mode: audit

Reconstruct what scaled out or in, when, and why — for post-incident analysis or cost review.

**Steps:**

1. Collect the timeline from three layers:
   ```bash
   # Layer 1: NodeClaim lifecycle events (node creation and termination)
   kubectl get events -A \
     --field-selector involvedObject.kind=NodeClaim \
     --sort-by='.lastTimestamp' | tail -50

   # Layer 2: Disruption reason on terminated nodes (if node still exists)
   kubectl get node <name> \
     -o jsonpath='{.annotations.karpenter\.sh/disruption-reason}'

   # Layer 3: Karpenter controller logs filtered to provisioning and disruption
   kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter \
     --since=3h | grep -E "provisioned|disrupted|consolidat|drift|interrupt|expir"

   # Layer 4: EC2 instance history (for Spot interruptions, verify in CloudWatch)
   aws ec2 describe-spot-instance-requests \
     --filters "Name=tag:karpenter.sh/nodepool,Values=<nodepool-name>" \
     --query 'SpotInstanceRequests[*].{ID:InstanceId,State:State,Fault:Fault}' \
     --region eu-north-1
   ```

2. Map each event to a cause:

   | `disruption-reason` annotation | Cause | What triggered it |
   |---|---|---|
   | `consolidation` | Node underutilised or empty | `consolidateAfter` timer elapsed |
   | `drift` | NodePool, EC2NodeClass, or AMI changed | GitOps push updated NodePool spec |
   | `expiration` | `expireAfter` TTL elapsed | Routine node rotation |
   | `interruption` | Spot 2-minute termination notice | AWS Spot capacity reclaim |
   | `emptiness` | No non-DaemonSet pods remained | Scale-in after workload removed |
   | (none / node gone) | Spot rebalance recommendation acted on | Check SQS interruption queue messages |

3. For scale-out events, correlate with the workload that triggered provisioning:
   ```bash
   # Find which pod triggered a NodeClaim
   kubectl describe nodeclaim <name> | grep -A 5 "Pod:"

   # Check what was Pending at the time (requires events within TTL)
   kubectl get events -n <workload-ns> \
     --field-selector reason=TriggeredScaleUp \
     --sort-by='.lastTimestamp'
   ```

4. Output a timeline table:
   ```
   TIME       EVENT          NODE/CLAIM           REASON         TRIGGER
   14:32:01   scale-out      ip-10-0-1-42         provisioned    orders-processor Pending (no capacity)
   14:32:44   node-ready     ip-10-0-1-42         —              Spot m6i.xlarge eu-north-1b
   15:45:10   scale-in       ip-10-0-1-42         consolidation  node underutilised after queue drain
   ```

5. **When Kubernetes events have aged out** (default TTL: 1h), fall back to CloudTrail for instance-level history:
   ```bash
   # Find RunInstances calls tagged with Karpenter nodepool — covers up to 90 days
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
     --start-time <iso-timestamp> \
     --end-time <iso-timestamp> \
     --region eu-north-1 \
     --query 'Events[*].CloudTrailEvent' --output text | \
     jq -r '. | fromjson | select(
       .requestParameters.tagSpecificationSet.items[]?.tags[]?
       | select(.key=="karpenter.sh/nodepool")
     ) | {time: .eventTime, instance: .responseElements.instancesSet.items[0].instanceId,
          type: .requestParameters.instanceType, az: .requestParameters.availabilityZone}'

   # Find TerminateInstances calls for Karpenter nodes
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventName,AttributeValue=TerminateInstances \
     --start-time <iso-timestamp> \
     --region eu-north-1 \
     --query 'Events[*].CloudTrailEvent' --output text | \
     jq -r '. | fromjson | {time: .eventTime,
       instance: .requestParameters.instancesSet.items[0].instanceId,
       user: .userIdentity.sessionContext.sessionIssuer.userName}'
   ```
   CloudTrail is the authoritative source when kubectl events are gone — use it as Layer 4 in the timeline.

6. Finish with a one-line verdict: what caused the scale event, whether it was expected, and whether any tuning is needed (e.g. disruption budget too loose, `consolidateAfter` too aggressive).

Reference: `references/karpenter.md` → Disruption strategy, Troubleshooting

---

## Mode: plan

Predict what Karpenter would provision before you deploy a workload — useful for cost estimates, pre-rollout capacity checks, and catching NodePool mismatches before they page you.

**Steps:**

1. Extract the scheduling requirements from the workload:
   ```bash
   # Get resource requests, nodeSelector, tolerations, affinity, and spread constraints
   kubectl get deployment <name> -n <ns> -o json | jq '{
     requests: .spec.template.spec.containers[].resources.requests,
     nodeSelector: .spec.template.spec.nodeSelector,
     tolerations: .spec.template.spec.tolerations,
     affinity: .spec.template.spec.affinity,
     topologySpread: .spec.template.spec.topologySpreadConstraints
   }'
   ```
   Or ask the user to paste the pod spec / Deployment YAML.

2. Walk through NodePool matching manually:
   - For each NodePool (highest `weight` first), check: do the pod's `nodeSelector` labels satisfy the NodePool `requirements`? Do the pod's `tolerations` cover all NodePool `taints`? Does the pod's `affinity` conflict with any NodePool zone requirements?
   - The first NodePool that satisfies all constraints is the target.
   - If no NodePool matches, state exactly which requirement is the blocker.

3. Predict instance selection within the matched NodePool:
   - Karpenter picks the cheapest instance type that fits: pod requests + DaemonSet overhead (typically 300–600m CPU + 512Mi–1Gi RAM depending on your DaemonSet stack)
   - For Spot: Karpenter uses current Spot pricing — check `aws ec2 describe-spot-price-history` for the region
   - State the likely instance family and size (e.g. "likely `m7i.large` in `eu-north-1b`, ~$0.03/hr Spot")

4. Check NodePool limits headroom:
   ```bash
   kubectl describe nodepool <name> | grep -A 8 "Status:"
   # Resources shows current usage vs limits — will the new workload fit?
   ```

5. Output:
   - Which NodePool would be selected and why
   - Likely instance type and AZ
   - Whether limits have headroom for the replica count
   - Any topology spread constraints that could block provisioning
   - Estimated cost per replica per hour (Spot or On-Demand)

Reference: `references/karpenter.md` → NodePool design, Cost strategy

---

## Mode: migrate

Move a cluster from Cluster Autoscaler to Karpenter safely.

**Steps:**

1. Collect current state:
   ```bash
   # CA version and configuration
   kubectl get deployment cluster-autoscaler -n kube-system -o yaml | \
     grep -E "image:|--node-group"

   # Existing node groups (Karpenter takes over scheduling; MNGs stay but CA stops managing them)
   aws eks describe-nodegroup --cluster-name <cluster> \
     --nodegroup-name <ng> --region eu-north-1 \
     --query 'nodegroup.{Min:scalingConfig.minSize,Max:scalingConfig.maxSize,Labels:labels}'

   # Pods currently running on CA-managed nodes
   kubectl get pods -A -o wide | grep <node-name>
   ```

2. Pre-migration checklist — **all must pass before proceeding**:
   - [ ] Karpenter controller installed and `NodePool` + `EC2NodeClass` created and `Ready=True`
   - [ ] Node IAM role tags include `karpenter.sh/discovery: <cluster-name>`
   - [ ] Interruption queue created and Karpenter controller has SQS permissions
   - [ ] `karpenter.sh/discovery` tag applied to subnets and security groups
   - [ ] Test NodePool provisions a node: `kubectl run test --image=nginx --restart=Never`
   - [ ] CA and Karpenter are NOT both active on the same nodes — they will fight

3. Cordon CA-managed nodes to prevent new scheduling, then drain:
   ```bash
   # Scale CA to 0 replicas first — stops CA from interfering
   kubectl scale deployment cluster-autoscaler -n kube-system --replicas=0

   # Cordon all CA-managed nodes
   for node in $(kubectl get nodes -l <ca-node-group-label> -o name); do
     kubectl cordon "$node"
   done

   # Drain with grace period — PDBs are respected
   for node in $(kubectl get nodes -l <ca-node-group-label> -o name); do
     kubectl drain "$node" \
       --ignore-daemonsets \
       --delete-emptydir-data \
       --grace-period=120 \
       --timeout=300s
   done
   ```
   Blast radius: pods on drained nodes will reschedule. If PDBs block drain, the command will wait — do not force.

4. After workloads reschedule onto Karpenter nodes and verify healthy:
   ```bash
   # Verify Karpenter provisioned new nodes
   kubectl get nodeclaim -A
   kubectl get nodes -l karpenter.sh/nodepool=<name>

   # Verify workloads are running
   kubectl get pods -A | grep -v Running | grep -v Completed
   ```

5. Remove CA:
   ```bash
   kubectl delete deployment cluster-autoscaler -n kube-system
   # Remove CA RBAC, ClusterRole, and ServiceAccount
   # Scale MNG minSize to 0 or delete if fully replaced by Karpenter
   ```

6. Critical migration risks:
   - **CA leaves nodes running** after you delete its deployment — drain explicitly, do not rely on CA to scale down
   - **`cluster-autoscaler.kubernetes.io/safe-to-evict: "false"` annotations** block drain — audit pods for this annotation before starting
   - **Karpenter will not manage existing MNG nodes** — it only provisions new ones via NodeClaim; running nodes remain until drained
   - **Two scalers competing** — the window between CA scale-down and Karpenter taking over is the riskiest moment; keep CA at 0 replicas, not deleted, until Karpenter is confirmed healthy

Reference: `references/karpenter.md` → Migration from Cluster Autoscaler

**Rollback:** If drain was initiated: `kubectl uncordon <node>` re-admits workloads immediately. Delete the new NodePool/EC2NodeClass with `kubectl delete nodepool <name>`. Restore the original node group config in Terraform before running `terraform apply`.

---

## Mode: upgrade

Upgrade Karpenter, including the v0.x → v1.x CRD migration.

**Steps:**

1. Identify the upgrade path:
   ```bash
   helm list -n karpenter
   kubectl get crd | grep karpenter
   # v0.x CRDs: provisioners.karpenter.sh, awsnodetemplates.karpenter.k8s.aws
   # v1.x CRDs: nodepools.karpenter.sh, ec2nodeclasses.karpenter.k8s.aws, nodeclaims.karpenter.sh
   ```

2. **v0.x → v1.x is a breaking migration** — follow this order:
   - Do NOT run `helm upgrade` directly from v0.x to v1.x — the CRDs are renamed and old resources will be orphaned
   - Read the Karpenter migration guide for the exact version pair (e.g. v0.37 → v1.0)
   - Steps:
     a. Export existing `Provisioner` and `AWSNodeTemplate` resources as YAML backups
     b. Install v1.x CRDs alongside v0.x (they have different names — no conflict)
     c. Create equivalent `NodePool` and `EC2NodeClass` from the v0.x YAML (field mapping below)
     d. Run `helm upgrade` to the v1.x chart — controller switches to v1 API
     e. Drain nodes managed under old `Provisioner` — they will reprovision as `NodeClaim`
     f. Delete old `Provisioner` and `AWSNodeTemplate` resources

3. v0.x → v1.x field mapping:

   | v0.x (`Provisioner`) | v1.x (`NodePool`) |
   |---|---|
   | `spec.requirements` | `spec.template.spec.requirements` |
   | `spec.limits.resources` | `spec.limits` |
   | `spec.ttlSecondsAfterEmpty` | `spec.disruption.consolidateAfter` |
   | `spec.ttlSecondsUntilExpired` | `spec.template.spec.expireAfter` |
   | `spec.providerRef` | `spec.template.spec.nodeClassRef` |

   | v0.x (`AWSNodeTemplate`) | v1.x (`EC2NodeClass`) |
   |---|---|
   | `spec.subnetSelector` | `spec.subnetSelectorTerms` (list) |
   | `spec.securityGroupSelector` | `spec.securityGroupSelectorTerms` (list) |
   | `spec.amiSelector` | `spec.amiSelectorTerms` (list) |
   | `spec.instanceProfile` | `spec.instanceProfile` or `spec.role` |

4. For patch/minor upgrades (v1.x → v1.y):
   ```bash
   # Check release notes for deprecated fields or changed defaults
   helm repo update
   helm diff upgrade karpenter oci://public.ecr.aws/karpenter/karpenter \
     --version <target-version> \
     --namespace karpenter \
     -f karpenter-values.yaml

   # Apply
   helm upgrade karpenter oci://public.ecr.aws/karpenter/karpenter \
     --version <target-version> \
     --namespace karpenter \
     --reuse-values \
     --atomic \
     --timeout 5m
   ```

5. Post-upgrade validation:
   ```bash
   kubectl get pods -n karpenter
   kubectl describe nodepool <name>      # Conditions: Ready=True
   kubectl get nodeclaim -A             # No stuck Pending claims
   kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter \
     --tail=100 | grep -i "error\|warn"
   ```

6. Rollback:
   ```bash
   helm rollback karpenter -n karpenter
   # NodePool/EC2NodeClass CRs are preserved in etcd — nodes continue running
   ```

Reference: `references/karpenter.md` → Upgrade, v0.x → v1.x migration

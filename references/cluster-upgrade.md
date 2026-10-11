---
title: Cluster Upgrade
custom_edit_url: null
---

# Cluster Upgrade Reference

Covers all `/platform-skills:cluster-upgrade` mode logic: planning a Kubernetes minor-version upgrade, finding removed APIs in source, rendered Helm and the live cluster, checking add-on compatibility, finding PodDisruptionBudgets that block node drains, rotating nodes, and rolling back on EKS.

**Verified against:** Amazon EKS version rollback (announced July 2026), AWS CLI 2.37 (`update-cluster-version --rollback-config` and `--force`, `list-insights`), pluto v5.24.4. Version-sensitive claims are marked inline.

## Contents

- Ownership boundary
- Upgrade rules that never change
- Phase 1: Removed APIs
- Phase 2: Add-on compatibility
- Phase 3: Drain blockers
- Phase 4: Control plane
- Phase 5: Node rotation
- Rollback
- Validation
- Common mistakes

## Ownership boundary

| Question | Authoritative skill |
|---|---|
| "Plan, run or roll back a cluster minor-version upgrade" | **`/platform-skills:cluster-upgrade`** |
| A deprecated API in one PR diff | `/platform-skills:pr-review` (upgrade dimension) |
| Karpenter's own version upgrade, NodePool or AMI drift | `/platform-skills:karpenter` |
| OpenShift cluster upgrades (channels, ClusterVersion) | `/platform-skills:openshift` |
| A Flux or Helm release that fails after the upgrade | `/platform-skills:gitops` |
| A restore drill before an upgrade | `/platform-skills:backup-dr` |

## Upgrade rules that never change

| Rule | Why |
|---|---|
| One minor version at a time | The control plane (EKS, AKS, GKE and upstream kubeadm) upgrades sequentially; 1.31 → 1.33 is two upgrades |
| Control plane first, then nodes | The version skew policy forbids a kubelet newer than the API server. A kubelet can be up to three minor versions older, which is what makes the node rotation a separate, later step |
| Removed APIs are fixed before the upgrade, not after | Once the API server stops serving an apiVersion, objects stored at it are still in etcd but every client that sends the old version (Helm, Flux, kubectl apply) fails |
| Add-ons are upgraded deliberately | EKS does not upgrade managed add-ons with the control plane, and rollback does not downgrade them |
| Every phase has its own validation and rollback | A failed node rotation is not a reason to roll back the control plane, and the reverse |

## Phase 1: Removed APIs

Scan three places. Each finds things the others miss.

| Where | Finds | Command |
|---|---|---|
| Source manifests in Git | Plain YAML that will be applied again | `pluto detect-files -d <dir> --target-versions k8s=v<target>` |
| Rendered Helm charts | apiVersions only visible after templating, including chart defaults | `helm template <release> <chart> -f values.yaml \| pluto detect - --target-versions k8s=v<target>` |
| Deployed Helm releases | What Helm will send on the next upgrade, from the release manifest | `pluto detect-helm -owide --target-versions k8s=v<target>` |
| The live API | Objects whose last applied apiVersion is deprecated, across all namespaces | `pluto detect-api-resources -owide --target-versions k8s=v<target>` |
| Everything in the cluster at once | Helm releases plus API resources | `pluto detect-all-in-cluster -o wide --target-versions k8s=v<target>` |

`--target-versions` takes a `v` prefix (`k8s=v1.34.0`). Add `--only-show-removed` (`-r`) when only what breaks the upgrade matters. Exit codes gate CI: `2` deprecated found, `3` removed found, `4` deprecated with no available replacement; `--ignore-deprecations` keeps only removals failing.

On EKS, also read the provider's own scan of audit logs, which sees clients that call deprecated APIs even when no stored object uses them:

```bash
aws eks list-insights --cluster-name <cluster> \
  --filter '{"categories": ["UPGRADE_READINESS"]}'
aws eks describe-insight --cluster-name <cluster> --id <insight-id>
```

A finding in Git or a rendered chart is fixed by changing the source and letting GitOps apply it. A finding only in the live API usually means an object nobody owns in Git: find its owner before the upgrade, because nothing will reconcile it afterwards.

## Phase 2: Add-on compatibility

Do not trust a remembered matrix. Query each component for the target version at the time of the upgrade.

| Component | Source of truth | How to check |
|---|---|---|
| EKS managed add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI) | EKS add-on catalogue | `aws eks describe-addon-versions --kubernetes-version <target> --addon-name <name> --query 'addons[].addonVersions[].addonVersion'` |
| Karpenter | Karpenter compatibility matrix (karpenter.sh docs) | Upgrade Karpenter first if the current version does not list the target Kubernetes version; see `/platform-skills:karpenter` |
| Flux | Flux supported Kubernetes versions | `flux check --pre` against the cluster after the control plane upgrade, and before it on a staging cluster at the target version |
| KEDA | KEDA Kubernetes compatibility table (keda.sh) | Check before upgrading; KEDA versions support a fixed range of Kubernetes versions |
| Ingress / Gateway controller, service mesh, CSI drivers, admission controllers | Each project's release notes | Admission webhooks matter most: a webhook that fails closed and does not support the new API version blocks every write it intercepts |

Upgrade an add-on before the control plane when its current version does not support the target, and after it when the new add-on version requires the target. Record the order in the plan.

## Phase 3: Drain blockers

A node rotation drains every node. A PodDisruptionBudget that currently allows zero disruptions stops the drain at that node:

```bash
# PDBs that block any eviction right now
kubectl get pdb -A -o json | jq -r '
  .items[] | select(.status.disruptionsAllowed == 0)
  | "\(.metadata.namespace)/\(.metadata.name)  minAvailable=\(.spec.minAvailable // "-")  maxUnavailable=\(.spec.maxUnavailable // "-")  healthy=\(.status.currentHealthy)/\(.status.expectedPods)"'
```

| Cause | Fix before the upgrade |
|---|---|
| `minAvailable` equals the replica count (often `minAvailable: 1` on one replica) | Scale to at least two replicas, or use `maxUnavailable: 1` |
| Pods not ready, so `currentHealthy` is below `desiredHealthy` | Fix the workload first; draining it now would cause an outage anyway |
| A PDB selector that matches pods from two workloads | Narrow the selector |
| Karpenter `karpenter.sh/do-not-disrupt` or NodePool disruption budgets | Expected to delay voluntary disruption; plan the window around them |

Also list pods that will not be rescheduled: bare pods with no controller, and pods with `emptyDir` data that matters.

## Phase 4: Control plane

```bash
aws eks update-cluster-version --name <cluster> --kubernetes-version <target>
aws eks describe-update --name <cluster> --update-id <id>
```

`--force` overrides failed upgrade-readiness checks. Use it only when an insight is understood to be a false positive, and record why.

## Phase 5: Node rotation

| Node type | Rotation |
|---|---|
| Managed node groups | `aws eks update-nodegroup-version --cluster-name <c> --nodegroup-name <ng> --kubernetes-version <target>`; respects the group's `maxUnavailable` |
| Karpenter | New nodes come from the EC2NodeClass AMI selection; an AMI alias or selector that resolves to the new version makes existing nodes drift and be replaced within disruption budgets. See `/platform-skills:karpenter` |
| Self-managed (ASG) | New launch template version with the new AMI, then an instance refresh |
| EKS Auto Mode | Managed by EKS |
| Fargate | Pods pick up the new version when they are recreated |

Rotate one pool at a time, smallest blast radius first, and watch for pods stuck `Pending` (capacity, topology spread, PDB) before starting the next.

## Rollback

> **The control plane is no longer a one-way door on EKS, but only for a week and only one step.** Since July 2026, EKS can roll a control plane back to the previous minor version within 7 days of an in-place upgrade. Outside those limits, rollback still means a blue/green cluster.

| Situation | Rollback |
|---|---|
| Within 7 days of an in-place upgrade, one minor version back | **EKS version rollback** (below) |
| More than 7 days, or the cluster was created at the current version, or already upgraded again | Not possible in place. Move traffic to a cluster at the old version (blue/green) |
| Only the node rotation failed | Roll the node pool back (managed node group `update-nodegroup-version` to the old version, or the previous launch template / AMI); the control plane can stay |
| Only an add-on failed | Downgrade that add-on with `aws eks update-addon --addon-version <previous>` |

**EKS version rollback, in order:**

1. Read the rollback readiness insights: `aws eks list-insights --cluster-name <c> --filter '{"categories": ["ROLLBACK_READINESS"]}'`. ERROR or UNKNOWN blocks the rollback.
2. Confirm applications and controllers still work on the previous version; resources created with APIs only the new version serves will break.
3. Roll worker nodes back first (managed node groups with `update-nodegroup-version --kubernetes-version <previous>`; self-managed and hybrid nodes are yours). Auto Mode does this itself. Fargate pods on the new version must be deleted first.
4. Downgrade any add-on whose version does not support the previous Kubernetes version. Rollback does not touch add-ons.
5. Start the rollback with the same command as an upgrade, at the previous version: `aws eks update-cluster-version --name <c> --kubernetes-version <previous>`. The update type is `VersionRollback`.
6. Watch `aws eks describe-update`.

**What rollback does not undo:** etcd data (objects created at new apiVersions stay, and with `--force` they are not cleaned up), add-on versions, node versions, and extended-support charges if the previous version is in extended support. `--force` bypasses insight checks only, never the 7-day, creation-version or one-step limits.

**Blue/green, when in-place rollback is unavailable:** keep the old cluster running and serving until the new one has passed the soak criteria. With GitOps, the new cluster reconciles the same repository; traffic moves by DNS or load balancer weight. Stateful workloads need a data plan (replication or a restore drill) before cutover; see `/platform-skills:backup-dr`.

## Validation

After each phase:

```bash
kubectl get nodes -o wide                          # every node Ready, versions as expected
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
aws eks describe-addon --cluster-name <c> --addon-name <name> --query 'addon.status'
flux get kustomizations -A && flux get helmreleases -A   # GitOps converged
pluto detect-all-in-cluster -o wide --target-versions k8s=v<target> --only-show-removed
```

## Common mistakes

- **Scanning only Git.** Charts render apiVersions that never appear in the repository, and the live API holds objects nobody owns.
- **Trusting a compatibility table from memory.** Query the add-on catalogue and each project's matrix at upgrade time.
- **Rotating nodes before fixing drain blockers.** The rotation stalls at the first node that hosts a zero-disruption PDB.
- **Assuming rollback is always possible.** It is one step, seven days, and in-place only; outside that, the plan needs a blue/green cluster.
- **Rolling the control plane back with nodes still on the new version.** The skew policy forbids nodes newer than the API server; roll nodes back first.

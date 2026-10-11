---
name: cluster-upgrade
description: Plan, run and roll back a Kubernetes minor-version upgrade, EKS first. Finds removed APIs in Git, rendered Helm charts and the live cluster with pluto and EKS upgrade insights, checks add-on compatibility (VPC CNI, CoreDNS, kube-proxy, Karpenter, Flux, KEDA, admission webhooks) against the target version, finds PodDisruptionBudgets that block node drains, plans the node rotation per pool, and picks the right rollback, including EKS one-step version rollback within 7 days or a blue/green cluster. Use when asked to "upgrade the cluster to 1.x", "what breaks if we upgrade", "find deprecated APIs before the upgrade", "why is the node drain stuck", or "roll back the EKS upgrade". One PR diff with a deprecated API → /platform-skills:pr-review. Karpenter's own upgrade → /platform-skills:karpenter.
argument-hint: "[plan|scan|addons|drain|rotate|rollback|validate] [cluster or target version]"
title: "Cluster Upgrade Command"
sidebar_label: "cluster-upgrade"
custom_edit_url: null
---

Upgrade a cluster one minor version without an outage, and know before starting how each step is undone.

Read `references/cluster-upgrade.md` before responding. It holds the scan commands for each place removed APIs hide, the add-on checks, the drain-blocker query, node rotation per pool type, the EKS rollback rules (one minor version, 7 days, in-place upgrades only) and blue/green as the fallback.

**This skill is interactive by default.** With no arguments, ask for the cluster platform (EKS, AKS, GKE, other), the current and target versions, how nodes are provisioned (managed node groups, Karpenter, self-managed, Auto Mode, Fargate) and how workloads are delivered (Flux, Argo CD, Helm, kubectl), then run `plan`. Never run `update-cluster-version`, `update-nodegroup-version` or a drain yourself: produce the commands, the checks and the rollback, and let the user run them.

## Mode dispatch

| Mode | What it does | Mutates anything? |
|---|---|---|
| `plan` | Full phased plan: scans, add-on order, drain blockers, control plane, node rotation, rollback per phase | No |
| `scan` | Removed and deprecated APIs in Git, rendered Helm, deployed releases and the live API, plus EKS upgrade insights | No |
| `addons` | Add-on compatibility for the target version and the upgrade order (before or after the control plane) | No |
| `drain` | PDBs and pods that will block or lose data in a node drain, with fixes | No |
| `rotate` | Node rotation plan per pool, smallest blast radius first | No |
| `rollback` | The right rollback for the phase and time elapsed: EKS version rollback, node pool rollback, add-on downgrade, or blue/green | No |
| `validate` | Post-phase checks | No |

## Mode: plan

1. Confirm the jump is one minor version. If not, plan each step separately.
2. Run `scan`, `addons` and `drain` and fold their findings into one ordered checklist.
3. For each phase (APIs, add-ons, control plane, nodes), state the blast radius, the validation and the rollback.
4. State the rollback window explicitly. On EKS: in-place rollback is available for 7 days after the upgrade completes and only to the previous minor version; after that, rollback means a blue/green cluster. If the plan needs a longer safety window, recommend blue/green from the start.

## Mode: scan

Use the commands in the reference's Phase 1 table, all with `--target-versions k8s=v<target>`:

```bash
pluto detect-files -d <repo dir> --target-versions k8s=v<target>
helm template <release> <chart> -f <values> | pluto detect - --target-versions k8s=v<target>
pluto detect-all-in-cluster -o wide --target-versions k8s=v<target>
aws eks list-insights --cluster-name <cluster> --filter '{"categories": ["UPGRADE_READINESS"]}'
```

Report each finding with where it lives (Git path, chart and value, or live object), its replacement apiVersion, and its owner. Flag live-only objects as ownerless: nothing will reconcile them after the upgrade.

## Mode: addons

Query, never recall. For EKS managed add-ons use `aws eks describe-addon-versions --kubernetes-version <target> --addon-name <name>`; for Karpenter, Flux, KEDA, the mesh, CSI drivers and admission webhooks, read each project's compatibility matrix for the target version. Output one table: add-on, current version, minimum version supporting the target, upgrade before or after the control plane, rollback version.

## Mode: drain

Run the PDB query from the reference. For each blocker, give the fix (replicas, `maxUnavailable`, selector, unhealthy workload) and the exact change. List bare pods and pods whose `emptyDir` data would be lost.

## Mode: rotate

Per pool type, from the reference's Phase 5 table. Order pools by blast radius, smallest first. After each pool: no `Pending` pods, all nodes `Ready`, GitOps converged.

## Mode: rollback

Ask what failed and when the control plane upgrade completed, then choose:

- **Node pool only:** roll that pool back; keep the control plane.
- **Add-on only:** downgrade the add-on.
- **Control plane, EKS, within 7 days, one step, in-place upgrade:** EKS version rollback, in the reference's order: read `ROLLBACK_READINESS` insights, roll nodes back first, downgrade incompatible add-ons, then `aws eks update-cluster-version --kubernetes-version <previous>`. State what it does not undo: etcd objects at new apiVersions, add-on versions, node versions.
- **Anything else:** blue/green. Traffic to a cluster at the old version, with a data plan for stateful workloads.

Never recommend `--force` without naming the specific insight it bypasses and why that insight is a false positive.

## Mode: validate

Run the reference's validation block for the phase just finished and report each check as pass or fail.

## Output format

Every mode ends with:

- **Findings or plan**, with exact commands and files
- **Blast radius**, in one line per phase
- **Validation**, as commands
- **Rollback**, for the phase in question, including whether in-place rollback is still available

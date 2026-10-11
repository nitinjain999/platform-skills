---
title: Backup and DR
custom_edit_url: null
---

# Backup and DR Reference

Covers all `/platform-skills:backup-dr` mode logic: Velero install and configuration on EKS, schedules and retention, what a backup does and does not contain, restore drills that measure recovery time, cross-cluster restore for disaster recovery, and rollback.

**Verified against:** Velero 1.18 (chart `vmware-tanzu/velero` 12.2.1), velero-plugin-for-aws 1.14.x (the plugin's compatibility table pairs 1.14.x with Velero 1.18.x). Working example: `examples/backup-dr`.

## Ownership boundary

| Question | Authoritative skill |
|---|---|
| Back up, restore, drill, or plan DR for Kubernetes workloads | **`/platform-skills:backup-dr`** |
| GameDay that breaks things on purpose | `/platform-skills:chaos` (then run the restore drill as recovery) |
| Blue/green cluster for an upgrade rollback | `/platform-skills:cluster-upgrade` |
| Secrets that must exist before restored workloads start | `/platform-skills:secrets` |
| Database point-in-time recovery (RDS, Aurora) | Out of scope: use the database's own backups; Velero restores Kubernetes objects and volumes |

## What Velero backs up, and what it does not

| Included | Not included |
|---|---|
| Kubernetes objects in the selected namespaces, plus cluster-scoped objects they need | Managed databases and anything outside the cluster |
| Persistent volumes, as EBS snapshots (volume snapshot location) or file-level copies (node agent) | Application consistency: a snapshot of a running database volume is crash-consistent, not transaction-consistent, unless you add pre/post hooks |
| | Data written after the backup: your recovery point is the schedule interval |

**GitOps changes the job.** With Flux, everything in Git can be recreated by reconciling the repository. Velero's value is the state Git does not hold: persistent volume data, objects created at runtime (certificates issued, CRs created by operators), and a fast way back for a whole namespace. Design the schedule around that state, not around manifests.

## Configuration decisions

| Decision | Recommendation | Reason |
|---|---|---|
| Credentials | IRSA or EKS Pod Identity, `credentials.useSecret: false` | No long-lived access key in the cluster |
| IAM | The plugin's actions, S3 scoped to one bucket, `Describe*` limited by `aws:RequestedRegion`, snapshot create, restore and delete limited to snapshots tagged `velero.io/backup` | Only the Describe calls need `"Resource": "*"`. Velero tags every snapshot with `velero.io/backup` and `velero.io/pv`, so a `Null` condition on that tag key stops a compromised role from deleting snapshots it did not take |
| Bucket | Versioning, a lifecycle that keeps noncurrent versions past the time you need to notice a deletion, and a bucket policy that denies version deletion, versioning suspension, lifecycle and policy changes, and bucket deletion to everyone but a break-glass role (`examples/backup-dr/bucket`); in another account for DR. Object Lock in compliance mode is stronger still: run a full backup and restore against it before relying on it | Velero needs `s3:DeleteObject` to expire backups, so ransomware or a compromised cluster credential holds it too. On a versioned bucket that delete only adds a marker, and only the break-glass role can remove the versions behind it |
| Schedule | Nightly for all namespaces, more often for namespaces whose data changes fast | The schedule interval is your recovery point |
| Retention | `ttl` on the schedule template (`720h` = 30 days) | Velero garbage-collects expired backups |
| Snapshot region | Same region as the volumes; copy snapshots to a second region for regional DR | An EBS snapshot restores only in its own region |

## Restore drills

A backup that has never been restored is untested. The drill (`examples/backup-dr/restore-drill.sh`):

1. Picks the latest backup created by the schedule (label `velero.io/schedule-name`) and refuses anything not `Completed`.
2. Creates `<namespace>-drill` with the source namespace's labels and a default-deny `NetworkPolicy` before restoring anything. Only pod-to-pod traffic inside the drill namespace, DNS ports to the DNS pods (selected by namespace name and pod label: `kube-system` and `k8s-app=kube-dns` by default, `--dns-namespace`/`--dns-pod-label` for OpenShift DNS or others, `--node-local-dns <ip>` for NodeLocal DNSCache), and any `--allow-egress <cidr>` test dependencies are allowed. An empty `namespaceSelector` on the DNS rule would let pods reach anything in any namespace listening on port 53 or 5353. The restored workloads carry production Secrets, so without this they could write to production databases, call external APIs or consume live queues. This needs a CNI that enforces egress policy; otherwise drill in a separate cluster.
3. Restores one namespace into `<namespace>-drill` with `--namespace-mappings`, excluding HTTPRoutes, Ingresses, Services and NetworkPolicies (a restored policy could reopen egress), then recreates each Service as an internal ClusterIP (or headless) copy. The copy cannot claim a production hostname, provision a load balancer or open a node port.
4. Waits for every pod to be Ready and reports the elapsed time: the measured recovery time for that namespace.
5. Deletes the drill namespace on every exit, including a failed restore or a readiness timeout, so restored workloads holding production Secrets never outlive the drill. `--keep` preserves it for inspection; delete it yourself afterwards.

Run it on a schedule (weekly is a good start) and after any change to storage classes, CSI drivers or Velero. Record each result; a growing recovery time is a finding.

**GameDay pairing:** with `/platform-skills:chaos`, delete a namespace (or a node pool) on purpose, then use the drill as the recovery step and compare the measured time against the recovery-time objective.

## Disaster recovery to another cluster

1. Install Velero in the new cluster pointing at the same bucket, with the backup location set to `accessMode: ReadOnly`, so the new cluster cannot overwrite or expire the backups it is restoring from.
2. Bootstrap Flux so controllers, CRDs and platform configuration come from Git first.
3. Restore application namespaces with `velero restore create --from-backup <backup> --include-namespaces <ns>`.
4. Switch the backup location back to `ReadWrite` only once the new cluster becomes the primary.

Velero's own documentation describes the same read-only switch (`kubectl patch backupstoragelocation default --namespace velero --type merge --patch '{"spec":{"accessMode":"ReadOnly"}}'`).

## Rollback

| Situation | Action |
|---|---|
| A restore brought back the wrong data | Delete the restored namespace and restore from an earlier backup; Velero never overwrites existing objects by default |
| A Velero upgrade broke backups | Revert the chart and plugin versions in Git; existing backups stay readable |
| A schedule change dropped a namespace | Revert in Git; the next scheduled run covers it again. Take a manual `velero backup create` if the gap matters |

## Troubleshooting

| Symptom | Likely cause | Check |
|---|---|---|
| Backup `PartiallyFailed` | A volume snapshot or an object failed | `velero backup describe <name> --details` and `velero backup logs <name>` |
| Backup location `Unavailable` | IAM role or bucket policy | `kubectl -n velero get backupstoragelocations`; the Velero pod's IRSA annotation |
| Restored pods `Pending` | Snapshot in another region or AZ, or a storage class missing in the target | PVC events in the restored namespace |
| Restore skipped objects | They already exist; Velero does not overwrite by default | `velero restore describe <name> --details` |

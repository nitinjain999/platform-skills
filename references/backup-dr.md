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
| IAM | The plugin's documented actions, S3 scoped to one bucket, EC2 limited by `aws:RequestedRegion` | The Describe calls need `"Resource": "*"`; narrow everything else |
| Bucket | Versioning and Object Lock or a deny-delete policy for anyone but Velero; in another account for DR | Ransomware and a compromised cluster credential must not be able to delete backups |
| Schedule | Nightly for all namespaces, more often for namespaces whose data changes fast | The schedule interval is your recovery point |
| Retention | `ttl` on the schedule template (`720h` = 30 days) | Velero garbage-collects expired backups |
| Snapshot region | Same region as the volumes; copy snapshots to a second region for regional DR | An EBS snapshot restores only in its own region |

## Restore drills

A backup that has never been restored is untested. The drill (`examples/backup-dr/restore-drill.sh`):

1. Picks the latest backup created by the schedule (label `velero.io/schedule-name`) and refuses anything not `Completed`.
2. Restores one namespace into `<namespace>-drill` with `--namespace-mappings`, excluding HTTPRoutes and Ingresses so the copy never receives production traffic.
3. Waits for every pod to be Ready and reports the elapsed time: the measured recovery time for that namespace.
4. Deletes the drill namespace.

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

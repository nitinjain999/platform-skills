---
name: backup-dr
description: Back up and restore Kubernetes workloads with Velero, and prove recovery works. Covers Velero on EKS via Flux (IRSA, S3 backup location, EBS snapshots), schedules and retention, what a backup does not contain, restore drills that restore a namespace into an isolated copy and measure recovery time, cross-cluster disaster recovery with a read-only backup location, and GameDay pairing with chaos experiments. Use when asked to "set up cluster backups", "test our restore", "what's our recovery time", "restore a deleted namespace", or "plan DR to another cluster". Breaking things on purpose → /platform-skills:chaos. Upgrade rollback by blue/green → /platform-skills:cluster-upgrade.
argument-hint: "[install|schedule|drill|restore|dr|debug] [namespace or cluster]"
title: "Backup and DR Command"
sidebar_label: "backup-dr"
custom_edit_url: null
---

A backup is only as good as the last time it was restored. Set up Velero, then prove each namespace comes back and measure how long it takes.

Read `references/backup-dr.md` before responding. It holds what Velero does and does not capture (and how GitOps changes that), configuration decisions, the restore drill, cross-cluster DR, rollback and troubleshooting. The working files are in `examples/backup-dr`.

**This skill is interactive by default.** With no arguments, ask what must be recoverable (namespaces, volumes, the whole cluster), the recovery point and recovery time objectives, and whether the target is the same cluster or a new one, then run `schedule` or `dr`. Never run a restore, delete a namespace, or patch a backup location yourself: produce the commands and let the user run them.

## Mode dispatch

| Mode | What it does |
|---|---|
| `install` | The protected backup bucket from `examples/backup-dr/bucket` (versioning, noncurrent-version retention, a bucket policy that lets only break-glass roles delete versions or lift the protection), then Velero via Flux from `examples/backup-dr` with IRSA and the scoped IAM policy |
| `schedule` | Schedules and retention derived from the recovery point objective; which namespaces need more frequent backups |
| `drill` | Run and interpret `restore-drill.sh`; compare the measured time with the recovery time objective |
| `restore` | Restore a namespace or specific resources, including into a different namespace |
| `dr` | Recovery into a new cluster: Flux bootstrap first, read-only backup location, then application namespaces |
| `debug` | Failed or partial backups and restores, from `velero backup/restore describe --details` and logs |

## Output format

Every mode ends with:

- **Changes or commands**, exact
- **Blast radius**, in one line
- **Validation**, as commands (a drill counts)
- **Rollback**

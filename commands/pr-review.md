---
name: pr-review
description: Comprehensive PR review across six dimensions — cost impact, environment drift, ownership gaps, SOC 2 compliance, deprecated API / version hygiene, and rollback feasibility. Each mode inspects the diff and current file state, reports findings with severity, and recommends concrete fixes. Use when preparing a PR for merge, conducting a pre-deployment readiness check, or performing a post-merge risk assessment.
argument-hint: "[cost|drift|ownership|compliance|upgrade|rollback|full] [PR number or diff]"
title: "PR Review Command"
sidebar_label: "pr-review"
custom_edit_url: null
---

You are a senior platform engineer performing a structured pre-merge risk review.

Input: `$ARGUMENTS` — one of the modes below, optionally followed by a PR number or pasted diff.

If no PR number or diff is provided, ask the user to paste the diff or provide `gh pr diff <number>` output before proceeding.

---

## Interactive Wizard (fires when no mode is specified)

When invoked without a mode argument, ask:

**Q1 — Review type?**
```
What type of review do you need?
  1. cost       — estimate resource cost delta from infrastructure changes
  2. drift      — compare values across dev / staging / prod environments
  3. ownership  — identify ownerless or high-blast-radius resources
  4. compliance — check against security and compliance frameworks
  5. upgrade    — assess breaking changes and migration effort
  6. rollback   — score reversibility and blast radius before merging
  7. full       — run all six modes in sequence

Enter 1–7 or mode name:
```

Then proceed into the selected mode.

---

## Mode: cost

Identify changes in the diff that will increase or decrease cloud spend.

### What to check

**Compute**
- Instance type changes (e.g. `t3.medium` → `m5.xlarge`) — flag cost multiplier
- Replica count increases in Deployment, HPA `minReplicas`, or Karpenter `NodePool` `limits`
- New node groups or node pools — estimate baseline cost from instance type
- Removal of Spot/preemptible usage in favour of On-Demand

**Storage**
- New PersistentVolumeClaim — flag size and StorageClass (`gp2` vs `gp3` vs `io1`)
- `gp2` → flag: `gp3` is 20% cheaper at equal performance
- EBS volume type changes that affect IOPS cost
- New S3 buckets without lifecycle rules — unbounded storage growth risk
- RDS storage changes — `allocated_storage` increases are irreversible without snapshot/restore

**Network**
- New NAT Gateway — ~$32/month per AZ plus $0.045/GB data processing
- Cross-AZ load balancer targets — invisible per-GB charge
- New NLB or ALB — ~$16–22/month base plus LCU cost
- CloudFront distribution additions
- VPN or Direct Connect attachment changes

**Data transfer**
- New inter-region replication (S3, RDS, DynamoDB)
- New egress paths (new public endpoints, new internet-facing services)

**Managed services**
- New RDS instance or Aurora cluster — note instance class and Multi-AZ flag
- New ElastiCache cluster
- New MSK or Kinesis stream
- New EKS managed node group with on-demand instances

### Output format

For each finding:
```
[COST] <resource name> — <change description>
  Estimated delta: +$X/month (basis: <pricing reference>)
  Severity: HIGH / MEDIUM / LOW
  Recommendation: <concrete action to reduce cost or accept with justification>
```

End with a **Cost Summary** table:

| Resource | Change | Est. Delta/month | Severity |
|---|---|---|---|

Flag any change with no resource requests/limits set — these lead to silent overprovisioning.

Reference: `references/pr-review.md` → Cost Impact

---

## Mode: drift

Detect configuration drift between environments (dev/staging/prod, or cluster overlays).

### What to check

**Kustomize / overlay drift**
- A base or overlay changed for one environment but not its siblings — scan for `overlays/dev`, `overlays/staging`, `overlays/prod` patterns
- `kustomization.yaml` patch added to one overlay but missing from another
- Image tag pinned differently across overlays

**Helm values drift**
- `values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml` — if one changed, check siblings
- Replica counts, resource limits, ingress hostnames, feature flags that differ without explanation
- A values key present in dev but absent in prod (would fall back to chart default silently)

**Terraform workspace / environment drift**
- `environments/dev/main.tf` changed but `environments/prod/main.tf` not touched
- Module version pinned to different versions across environments
- Variable values diverged without a comment explaining why

**GitOps source drift**
- Flux `HelmRelease` or `Kustomization` with different `spec.interval`, `spec.timeout`, or `spec.retries` between clusters
- Argo CD `Application` targeting different target revisions per environment without explicit promotion intent

**Feature flag drift**
- ConfigMap or environment variable that enables a feature in staging but is absent from prod equivalent

### Output format

For each finding:
```
[DRIFT] <file> vs <sibling file>
  Field: <key path>
  Dev value: <x>   Staging value: <y>   Prod value: <z or MISSING>
  Severity: HIGH / MEDIUM / INFO
  Recommendation: Align values or add a comment explaining intentional divergence
```

Ask: "Is this drift intentional or an oversight?" — flag HIGH if it affects a path that runs in prod but not lower environments.

Reference: `references/pr-review.md` → Environment Drift

---

## Mode: ownership

Identify governance gaps introduced or exposed by the diff.

### What to check

**CODEOWNERS**
- New top-level directory with no CODEOWNERS entry
- New `references/`, `commands/`, or `examples/` subdirectory not covered by an existing glob
- Deleted directory that still has a CODEOWNERS entry (stale rule)

**Kubernetes resource ownership**
- New Namespace with no `team:` or `owner:` label
- New Deployment, StatefulSet, or CronJob with no `app.kubernetes.io/team` label
- ServiceAccount with no owning team annotation

**Terraform module ownership**
- New module directory with no `README.md` describing purpose, inputs, outputs, and team
- `variables.tf` with no `description` on any variable
- Module consumed with no `source` pinned to a version tag

**PR governance**
- No linked issue or ticket reference in PR description (search for `#`, `JIRA-`, `LINEAR-`)
- PR author would be the only required reviewer (self-merge risk) — note if CODEOWNERS has no coverage for changed paths
- No `CHANGELOG.md` update when `version` changed in `plugin.json`, `marketplace.json`, `Chart.yaml`, or `package.json`

**Policy coverage**
- New Namespace with no matching Kyverno `ValidatingPolicy` or `NetworkPolicy`
- New workload type not covered by existing admission policies

### Output format

```
[OWNERSHIP] <file or resource>
  Gap: <description of missing ownership signal>
  Severity: HIGH / MEDIUM / LOW
  Recommendation: <exact addition needed>
```

Reference: `references/pr-review.md` → Ownership and Governance

---

## Mode: compliance

Assess SOC 2 Trust Services Criteria impact of the diff.

Map each finding to a SOC 2 control area:

| Code | Area |
|---|---|
| CC6.1 | Logical access — least privilege, RBAC, no wildcard IAM |
| CC6.2 | Authentication — MFA, OIDC, no static credentials |
| CC6.6 | Network security — VPC isolation, security groups, private subnets |
| CC6.7 | Encryption — at-rest and in-transit on all data stores |
| CC6.8 | Vulnerability management — IaC scanning, image scanning |
| CC7.1 | Detection — GuardDuty, CloudWatch, Security Hub |
| CC7.2 | Audit logging — CloudTrail, VPC flow logs, API access logs |
| CC8.1 | Change management — PR workflow, plan review, state locking |
| A1.2  | Backup — automated backups, retention ≥ 35 days |

### What to check

**CC6.1 — Logical access**
- IAM policy with `Action: "*"` or `Resource: "*"` — wildcard must have explicit justification
- RBAC ClusterRole with `verbs: ["*"]` or `resources: ["*"]`
- New service account bound to a ClusterRole with broad permissions
- IRSA / Workload Identity role with no condition narrowing to a specific namespace/SA

**CC6.2 — Authentication**
- Static AWS access keys (`aws_access_key_id`) anywhere in diff — critical
- Long-lived tokens or passwords in ConfigMaps or environment variables
- New GitHub Actions workflow using `aws-actions/configure-aws-credentials` without OIDC

**CC6.6 — Network**
- Security group with `0.0.0.0/0` ingress on non-80/443 ports
- New publicly accessible RDS instance (`publicly_accessible = true`)
- Kubernetes Service of type `LoadBalancer` with no annotation restricting source CIDRs
- NetworkPolicy removed from a namespace

**CC6.7 — Encryption**
- New S3 bucket without `server_side_encryption_configuration`
- RDS instance with `storage_encrypted = false`
- EBS volume with `encrypted = false`
- Secret stored in a ConfigMap instead of a Secret resource or external secrets backend

**CC7.2 — Audit logging**
- CloudTrail trail disabled or logging bucket changed
- S3 bucket access logging removed
- Kubernetes audit policy weakened (reduced log level)

**CC8.1 — Change management**
- Terraform state backend changed without documented migration plan
- `prevent_destroy = true` removed from a stateful resource
- Direct push to main/protected branch bypassing PR workflow

### Output format

```
[COMPLIANCE] CC<X.X> — <control area>
  Finding: <description>
  File: <path>
  Severity: CRITICAL / HIGH / MEDIUM
  Remediation: <exact fix with code example>
  Auditor evidence: <command to produce evidence for auditors>
```

End with a **Compliance Summary** listing all affected control codes and whether each is a blocker.

Reference: `references/pr-review.md` → Compliance and SOC 2, `references/compliance.md`

---

## Mode: upgrade

Detect deprecated APIs, EOL versions, and version hygiene issues.

### What to check

**Kubernetes API versions**

Check each resource `apiVersion` in the diff against the target cluster version:

| Deprecated API | Removed in | Replacement |
|---|---|---|
| `extensions/v1beta1` Ingress | 1.22 | `networking.k8s.io/v1` |
| `networking.k8s.io/v1beta1` Ingress | 1.22 | `networking.k8s.io/v1` |
| `policy/v1beta1` PodSecurityPolicy | 1.25 | Kyverno / OPA / PSA |
| `policy/v1beta1` PodDisruptionBudget | 1.25 | `policy/v1` |
| `autoscaling/v2beta1` HPA | 1.26 | `autoscaling/v2` |
| `batch/v1beta1` CronJob | 1.25 | `batch/v1` |
| `apiextensions.k8s.io/v1beta1` CRD | 1.22 | `apiextensions.k8s.io/v1` |
| `kyverno.io/v1` ClusterPolicy | deprecated 1.17, removal 1.20 | `policies.kyverno.io/v1` |

**Terraform provider versions**
- Provider constraint too loose: `>= 3.0` allows major version jumps with breaking changes — recommend `~> X.Y`
- `required_terraform` version missing or too broad
- Module `source` without a version tag (e.g. `source = "git::..."` with no `ref=`)

**GitHub Actions**
- Action pinned to a branch (`@main`, `@master`) — must be pinned to a SHA or immutable tag
- Action using a deprecated major version (e.g. `actions/checkout@v2` when `v4` is current)
- `runs-on: ubuntu-18.04` or `ubuntu-20.04` — both EOL on GitHub Actions

**Container images**
- `:latest` tag — not reproducible, breaks rollback
- Image from an unverified registry without digest pinning
- Base image with a known EOL tag (e.g. `node:14`, `python:3.7`)

**Helm**
- `apiVersion: v1` chart when `v2` features are used (dependencies, type field)
- Deprecated chart values that map to removed chart keys (validate against chart schema)

**Tool versions in CI**
- `terraform` version pinned to a specific patch but not aligned with `required_version` constraint
- `kubectl` version more than one minor version skew from the cluster version
- `helm` version not pinned (uses runner default)

### Output format

```
[UPGRADE] <file>:<line>
  Found: <deprecated item>
  Target version: <cluster/provider/tool version>
  Removed in: <version where this breaks>
  Replacement: <exact updated value>
  Migration effort: LOW / MEDIUM / HIGH
```

Flag any item that will break on the next minor version upgrade as **BREAKING**.

Reference: `references/pr-review.md` → Upgrade and Version Hygiene

---

## Mode: rollback

Score the rollback feasibility of the changes in the diff.

### Rollback feasibility scoring

Score each change on two axes:

**Reversibility** (can you undo this by reverting the commit?)
- `FULL` — revert commit restores previous state completely
- `PARTIAL` — revert restores config but side effects persist (e.g. DNS TTL, cache)
- `MANUAL` — revert is not enough; manual steps required
- `NONE` — change is irreversible without data loss or significant effort

**Blast radius** (what breaks if rollback is needed?)
- `LOCAL` — one service or namespace
- `CLUSTER` — all workloads in a cluster
- `PLATFORM` — shared infrastructure (IAM, VPC, DNS, state backend)
- `DATA` — data store schema, backup policy, or retention change

### What to check

**Database / stateful changes**
- Schema migration without a corresponding down migration → Reversibility: NONE
- `allocated_storage` increase on RDS → irreversible without snapshot/restore
- DynamoDB table attribute or key schema change → Reversibility: NONE
- Backup retention period reduced → audit trail gap even after revert

**Kubernetes resource renames**
- Resource renamed (Deployment, ConfigMap, Secret) with `prune: true` in Kustomization → old resource deleted on sync, new resource created — rollback requires re-creating old resource
- Service rename with active DNS records → clients cache old name

**Terraform destructive operations**
- `-/+` replace in plan output for any stateful resource (RDS, EKS node group, ElastiCache)
- `prevent_destroy = true` removed from a resource
- `force_destroy = true` added to an S3 bucket or EKS cluster
- State backend migration without locking

**GitOps**
- `prune: true` Kustomization + resource deletion → rollback recreates resource but loses any out-of-band state
- HelmRelease with `remediation.uninstall: true` — rollback triggers full uninstall, not just version pin
- Image tag changed to a mutable tag (`:latest`) — rollback points to different image than before

**Secrets and credentials**
- Secret rotation without grace period — old clients fail immediately on rollback
- IRSA / Workload Identity role ARN changed — pods need restart to pick up new token

**IAM and RBAC**
- IAM role deleted or trust policy changed — dependent services break immediately
- RBAC ClusterRole deleted — ServiceAccounts lose permissions immediately

### Output format

```
[ROLLBACK] <resource / file>
  Change: <description>
  Reversibility: FULL / PARTIAL / MANUAL / NONE
  Blast radius: LOCAL / CLUSTER / PLATFORM / DATA
  Rollback procedure: <exact steps if not a simple git revert>
  Pre-merge requirement: <what must be in place before merging — backup, snapshot, migration script>
```

End with a **Rollback Risk Score**:

| Risk Level | Criteria |
|---|---|
| 🟢 LOW | All changes FULL reversibility, LOCAL blast radius |
| 🟡 MEDIUM | Any PARTIAL reversibility or CLUSTER blast radius |
| 🔴 HIGH | Any MANUAL/NONE reversibility or PLATFORM/DATA blast radius |

If risk is HIGH, recommend: require a pre-merge snapshot, runbook, or explicit sign-off before merge.

Reference: `references/pr-review.md` → Rollback Feasibility

---

## Mode: full

Run all six modes in sequence against the same diff. Output sections in this order:

1. **Cost** — spend delta
2. **Drift** — environment alignment
3. **Ownership** — governance gaps
4. **Compliance** — SOC 2 control impact
5. **Upgrade** — deprecated APIs and version hygiene
6. **Rollback** — feasibility and risk score

End with a **Merge Readiness Summary**:

```
Cost delta:      +$X/month (N findings)
Drift:           N environment mismatches
Ownership gaps:  N findings
Compliance:      N control areas affected (K critical)
Upgrade risk:    N deprecated items (K breaking)
Rollback score:  🟢 LOW / 🟡 MEDIUM / 🔴 HIGH

Blockers (must fix before merge):
  - <item 1>
  - <item 2>

Recommended (should fix, not blocking):
  - <item 1>

Informational:
  - <item 1>
```

Reference: `references/pr-review.md`

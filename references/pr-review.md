---
title: PR Review
custom_edit_url: null
---

# PR Review Reference

Comprehensive pre-merge risk review across six dimensions: cost impact, environment drift, ownership and governance, SOC 2 compliance, deprecated API / version hygiene, and rollback feasibility.

Use this reference when running `/platform-skills:pr-review` or when manually performing a structured pre-merge review.

---

## How to Run a PR Review

```bash
# Get the diff for a PR
gh pr diff 42

# Or pipe directly into context
gh pr diff 42 | pbcopy   # macOS — paste into Claude

# Check all open review threads (bot comments to triage)
gh api repos/<owner>/<repo>/pulls/42/comments --jq '.[] | {id, path, body: .body[0:300], in_reply_to_id}'

# Check unresolved threads via GraphQL
gh api graphql -f query='
{
  repository(owner: "<owner>", name: "<repo>") {
    pullRequest(number: 42) {
      reviewThreads(first: 20) {
        nodes { id isResolved comments(first: 1) { nodes { path body } } }
      }
    }
  }
}'
```

---

## Cost Impact

### Principles

- Every infrastructure change has a cost implication. The default is to make it visible, not to block.
- Cost findings are informational unless the delta is significant (> $100/month unexplained) or the change disables cost controls (removes lifecycle rules, removes Spot usage, removes resource limits).
- Resource limits missing on new workloads is a cost risk — it allows unbounded CPU/memory consumption on shared nodes.

### Instance and compute costs (AWS reference)

| Instance | vCPU | RAM | On-Demand (us-east-1) |
|---|---|---|---|
| t3.micro | 2 | 1 GB | ~$8/month |
| t3.medium | 2 | 4 GB | ~$30/month |
| m5.large | 2 | 8 GB | ~$70/month |
| m5.xlarge | 4 | 16 GB | ~$140/month |
| m5.4xlarge | 16 | 64 GB | ~$550/month |
| c5.2xlarge | 8 | 16 GB | ~$260/month |

Spot savings: 60–80% vs On-Demand for stateless workloads.

### Storage cost reference

| Type | Cost |
|---|---|
| gp2 EBS | $0.10/GB/month |
| gp3 EBS | $0.08/GB/month (20% cheaper, same baseline perf) |
| io1 EBS | $0.125/GB/month + $0.065/provisioned IOPS |
| S3 Standard | $0.023/GB/month |
| S3 Infrequent Access | $0.0125/GB/month |

**Rule:** Flag any new `gp2` volume — `gp3` is cheaper at equal performance for most workloads.

### Network cost reference

| Resource | Cost |
|---|---|
| NAT Gateway | ~$32/month per AZ + $0.045/GB processed |
| ALB | ~$22/month base + LCU ($0.008/LCU-hour) |
| NLB | ~$16/month base + NLCU |
| Cross-AZ data transfer | $0.01/GB (both directions) |
| Internet egress (AWS) | $0.09/GB first 10 TB |

**Rule:** Any new NAT Gateway is a significant cost addition. Verify it's not duplicating an existing one. Prefer a shared NAT Gateway per AZ over per-subnet.

### Cost review checklist

```
□ Replica count changes — multiply by instance cost
□ New PVC — check StorageClass and size; recommend gp3 over gp2
□ New S3 bucket — lifecycle rules present? versioning enabled (doubles storage)?
□ New NAT Gateway — is an existing one available in the same AZ?
□ New load balancer — justify vs reusing existing ingress controller
□ Resource requests/limits set on all new containers
□ HPA minReplicas — what is the floor cost at minimum scale?
□ RDS instance class — Multi-AZ doubles cost; flag if not required in dev
□ New managed service — is there a cheaper self-hosted alternative for non-prod?
```

---

## Environment Drift

### Principles

- Drift between environments is normal for intentional differences (resource sizing, replica counts, hostnames). It is a bug when it affects feature availability, security controls, or configuration correctness.
- The review goal is to make drift **visible and intentional** — not to enforce identical environments.
- Any drift in security controls, network policy, or admission policies between prod and lower environments is HIGH severity.

### Common drift patterns

**Silent fallback risk**
A values key present in `values-dev.yaml` but absent from `values-prod.yaml` means prod silently uses the chart default. If the chart default is insecure or incorrect, it only manifests in prod.

```yaml
# values-dev.yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"

# values-prod.yaml
ingress: {}    # ← ssl-redirect falls back to chart default (false)
```

**Overlay patch missing**
```
overlays/
  dev/kustomization.yaml    # patches resource limits
  prod/kustomization.yaml   # no resource limit patch → uses base (no limits)
```

**Module version drift**
```hcl
# environments/dev/main.tf
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"
}

# environments/prod/main.tf
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"    # ← different major — different behaviour
}
```

### Drift review checklist

```
□ For every changed values file, check sibling environment files
□ For every changed overlay, check sibling overlays
□ For every changed Terraform environment, check sibling environments
□ Feature flags enabled in staging but absent from prod equivalent
□ Ingress annotations (TLS, CORS, rate limiting) consistent across envs
□ NetworkPolicy present in all environments, not just prod
□ ResourceQuota and LimitRange consistent across tenant namespaces
□ Kyverno/OPA policies applied to all clusters, not just production
```

---

## Ownership and Governance

### CODEOWNERS patterns

```
# Root catch-all — every file needs at least one owner
*                          @platform-team

# Platform domains
references/                @platform-team
commands/                  @platform-team
examples/kubernetes/       @kubernetes-team
examples/terraform/        @infra-team

# Protect release files
.claude-plugin/            @platform-leads
CHANGELOG.md               @platform-leads
```

**Rule:** Any new top-level directory with no CODEOWNERS entry means PRs touching it have no required reviewers — anyone can merge.

### Kubernetes resource ownership labels

Every Namespace, Deployment, StatefulSet, DaemonSet, and CronJob should carry:

```yaml
labels:
  app.kubernetes.io/name: <service-name>
  app.kubernetes.io/team: <team-name>
  app.kubernetes.io/part-of: <platform-or-product>
```

Use a `ValidatingPolicy` to enforce this at admission:
```yaml
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: require-team-label
spec:
  validationActions: [Audit]
  matchConstraints:
    resourceRules:
      - apiGroups: [apps]
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [deployments, statefulsets, daemonsets]
  validations:
    - expression: >-
        has(object.metadata.labels) &&
        'app.kubernetes.io/team' in object.metadata.labels
      message: "app.kubernetes.io/team label is required"
```

### Terraform module ownership checklist

Every module directory must have:
- `README.md` — purpose, inputs, outputs, example usage, owning team
- `variables.tf` — every variable has a `description`
- `outputs.tf` — every output has a `description`
- Version tag in any consuming `source` reference

### PR governance checklist

```
□ PR description explains WHY (not just what changed)
□ Issue or ticket reference present (#123, JIRA-456, LINEAR-789)
□ CHANGELOG updated if version bumped in any manifest
□ CODEOWNERS covers all changed top-level paths
□ New namespace has team label and ResourceQuota
□ New Terraform module has README with owner
□ All variables in new modules have descriptions
```

---

## Compliance and SOC 2

### Control mapping quick reference

| SOC 2 Code | Platform control | Terraform resource |
|---|---|---|
| CC6.1 | IAM least privilege | `aws_iam_policy`, `aws_iam_role` |
| CC6.1 | Kubernetes RBAC scoped | `kubernetes_cluster_role_binding` |
| CC6.2 | OIDC over static keys | `aws_iam_role` assume_role_policy |
| CC6.6 | Security groups restricted | `aws_security_group_rule` |
| CC6.6 | No public RDS | `aws_db_instance.publicly_accessible` |
| CC6.7 | S3 encryption | `aws_s3_bucket_server_side_encryption_configuration` |
| CC6.7 | RDS encryption | `aws_db_instance.storage_encrypted` |
| CC7.2 | CloudTrail enabled | `aws_cloudtrail` |
| CC7.2 | S3 access logging | `aws_s3_bucket_logging` |
| CC8.1 | State locking | `aws_dynamodb_table` for lock |
| A1.2 | RDS backup retention | `aws_db_instance.backup_retention_period >= 35` |

### Critical patterns (automatic blockers)

```hcl
# ❌ CC6.1 — wildcard IAM (CRITICAL)
Statement = [{
  Effect   = "Allow"
  Action   = "*"
  Resource = "*"
}]

# ✅ CC6.1 — scoped to specific actions and ARN
Statement = [{
  Effect = "Allow"
  Action = ["s3:GetObject", "s3:ListBucket"]
  Resource = [
    "arn:aws:s3:::${var.bucket_name}",
    "arn:aws:s3:::${var.bucket_name}/*"
  ]
}]
```

```hcl
# ❌ CC6.7 — unencrypted RDS (CRITICAL)
resource "aws_db_instance" "main" {
  storage_encrypted = false
}

# ✅ CC6.7
resource "aws_db_instance" "main" {
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn
}
```

```hcl
# ❌ CC6.6 — public RDS (CRITICAL)
resource "aws_db_instance" "main" {
  publicly_accessible = true
}
```

### Evidence collection commands

```bash
# CC6.1 — list all IAM roles and policies
aws iam list-roles --query 'Roles[*].RoleName'
aws iam get-role-policy --role-name <role> --policy-name <policy>

# CC7.2 — verify CloudTrail is logging
aws cloudtrail get-trail-status --name <trail-name> --query 'IsLogging'

# CC6.7 — verify S3 bucket encryption
aws s3api get-bucket-encryption --bucket <bucket>

# CC6.7 — verify RDS encryption
aws rds describe-db-instances --query 'DBInstances[*].{ID:DBInstanceIdentifier,Encrypted:StorageEncrypted}'

# A1.2 — verify backup retention
aws rds describe-db-instances --query 'DBInstances[*].{ID:DBInstanceIdentifier,Retention:BackupRetentionPeriod}'

# CC6.6 — list security group rules with open ingress
aws ec2 describe-security-groups --filters "Name=ip-permission.cidr,Values=0.0.0.0/0" \
  --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName}'
```

---

## Upgrade and Version Hygiene

### Kubernetes API deprecation timeline

| API | Deprecated | Removed | Replacement |
|---|---|---|---|
| `extensions/v1beta1` Ingress | 1.14 | **1.22** | `networking.k8s.io/v1` |
| `networking.k8s.io/v1beta1` Ingress | 1.19 | **1.22** | `networking.k8s.io/v1` |
| `policy/v1beta1` PodSecurityPolicy | 1.21 | **1.25** | Kyverno / OPA / PSA |
| `policy/v1beta1` PodDisruptionBudget | 1.21 | **1.25** | `policy/v1` |
| `autoscaling/v2beta1` HPA | 1.23 | **1.26** | `autoscaling/v2` |
| `batch/v1beta1` CronJob | 1.21 | **1.25** | `batch/v1` |
| `apiextensions.k8s.io/v1beta1` CRD | 1.16 | **1.22** | `apiextensions.k8s.io/v1` |
| `kyverno.io/v1` ClusterPolicy | 1.17 | **1.20** | `policies.kyverno.io/v1` |

Check manifest API versions against the cluster's target upgrade version — not just the current version.

```bash
# Scan a directory for deprecated API versions
kubectl convert --dry-run -f ./manifests/ 2>&1 | grep -i "deprecated\|removed"

# Or use pluto (purpose-built tool)
pluto detect-files -d ./manifests/ --target-versions k8s=v1.28.0
```

### Terraform version hygiene

```hcl
# ❌ Too loose — allows major version jumps
terraform {
  required_providers {
    aws = { version = ">= 3.0" }
  }
}

# ✅ Pessimistic constraint — locks major version
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = "~> 1.7"
}
```

### GitHub Actions version hygiene

```yaml
# ❌ Floating branch — unpinned, non-reproducible
- uses: actions/checkout@main

# ❌ Major tag — can be moved by owner
- uses: actions/checkout@v3

# ✅ SHA pin — immutable
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4.1.1
```

Current recommended major versions (as of v1.12.0) — use these as the comment label on your SHA-pinned lines, not as the actual ref:

| Action | Minimum recommended major | Example SHA-pinned usage |
|---|---|---|
| `actions/checkout` | `v4` | `actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4.1.1` |
| `actions/setup-node` | `v4` | `actions/setup-node@60edb5dd545a775178f52524783378180af0d1f8 # v4.0.2` |
| `actions/setup-python` | `v5` | `actions/setup-python@0a5c61591373683ec8de3e43c37e6e526f26a9b8 # v5.0.0` |
| `actions/upload-artifact` | `v4` | `actions/upload-artifact@5d5d22a31266ced268874388b861e4b58bb5c2f3 # v4.3.1` |
| `aws-actions/configure-aws-credentials` | `v4` | `aws-actions/configure-aws-credentials@e3dd6a429d7300a6a4c196c26e071d42e0343502 # v4.0.2` |
| `hashicorp/setup-terraform` | `v3` | `hashicorp/setup-terraform@651471c36a6092792c552e8b1bef71e592b462d8 # v3.1.1` |

Always pin the `uses:` field to the full commit SHA. The major version tag in the comment is for human readability only — the SHA is what actually controls which code runs.

### Container image hygiene

```yaml
# ❌ Mutable tag — different image on rollback
image: nginx:latest
image: nginx:1.25

# ✅ Digest pin — immutable
image: nginx:1.25.3@sha256:a3e2f7e2b1c4d9f8e6a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4
```

```bash
# Get digest for an image
docker inspect --format='{{index .RepoDigests 0}}' nginx:1.25.3
# or
crane digest nginx:1.25.3
```

### Upgrade review checklist

```
□ All Kubernetes apiVersions checked against target cluster version
□ Terraform provider constraints use ~> not >=
□ required_version set in all root modules
□ Module source refs include a version tag
□ GitHub Actions pinned to SHA or immutable release tag
□ No :latest image tags
□ Node/Python/Go runtime versions not EOL
□ ubuntu-18.04 / ubuntu-20.04 runner replaced with ubuntu-latest or ubuntu-22.04
□ kyverno.io/v1 ClusterPolicy replaced with policies.kyverno.io/v1
```

---

## Rollback Feasibility

### Rollback decision matrix

| Change type | Reversibility | Notes |
|---|---|---|
| Kubernetes Deployment image tag | FULL | Revert commit → GitOps re-syncs |
| ConfigMap / Secret value change | FULL | Revert commit → GitOps re-syncs |
| Kubernetes resource rename | MANUAL | Old resource deleted, new created; clients need update |
| HelmRelease version bump | FULL | Revert pinned version → GitOps re-installs |
| HelmRelease with `uninstall` remediation | MANUAL | Rollback triggers full uninstall |
| Terraform variable change | FULL | Plan shows delta; apply reverses |
| RDS `allocated_storage` increase | NONE | AWS does not support storage decrease |
| RDS instance class change | PARTIAL | Change requires maintenance window |
| IAM role trust policy change | MANUAL | Services using old trust break immediately |
| IAM role deletion | NONE | Must recreate; ARN changes if not controlled |
| S3 bucket deletion (`force_destroy`) | NONE | Data permanently lost |
| Database schema migration (no down) | NONE | Application must handle both old and new schema |
| Secret rotation (no grace period) | MANUAL | Old clients fail; must re-issue old secret |
| DNS record change | PARTIAL | TTL delay; old record may be cached |
| Kustomization `prune: true` + resource delete | MANUAL | Resource removed from cluster; restore from Git |

### Pre-merge requirements for high-risk changes

**For NONE reversibility:**
- [ ] Database backup or snapshot taken and verified before merge
- [ ] Down migration script written and tested (for schema changes)
- [ ] Data export confirmed for destructive storage operations
- [ ] Explicit sign-off from owning team and/or on-call

**For MANUAL reversibility with PLATFORM blast radius:**
- [ ] Runbook written and reviewed
- [ ] Rollback tested in a non-prod environment
- [ ] Maintenance window scheduled
- [ ] Stakeholders notified

**For stateful Terraform changes:**
```bash
# Always take a state backup before applying destructive changes
terraform state pull > terraform.tfstate.backup.$(date +%Y%m%d%H%M%S)

# Verify the backup
terraform state list
```

### GitOps rollback patterns

```bash
# Flux — force rollback to previous image
flux suspend image updateautomation <name>
kubectl set image deployment/<name> <container>=<previous-image>
git revert HEAD && git push

# Argo CD — rollback to previous sync
argocd app rollback <app-name> <revision>

# Helm — rollback to previous release
helm rollback <release-name> <revision>
helm history <release-name>  # find the revision number
```

### Rollback checklist

```
□ Every stateful resource change has a pre-merge backup requirement noted
□ Schema migrations have a corresponding down migration
□ Resource renames document the rollback procedure
□ Secret rotations have a grace period defined
□ IAM role ARN changes identify all dependent services
□ GitOps prune behaviour understood for deleted resources
□ HelmRelease remediation policy reviewed (uninstall vs rollback)
□ Maintenance window identified for changes requiring it
```

---

## Bot Comment Triage

When a PR has open review threads from Copilot, GitHub Actions bots, Dependabot, or similar:

### Evaluation steps

1. **Read the comment** — understand exactly what it claims is wrong
2. **Read the current file state** — not the diff, the actual file after all commits
3. **Classify the comment:**
   - **Valid** — the issue exists in the current file state → fix it
   - **Stale** — the issue was fixed in a later commit → reply and resolve
   - **Invalid** — the comment is technically incorrect → reply with specific reason and resolve

### Resolving threads via CLI

```bash
# List all unresolved threads
gh api graphql -f query='
{
  repository(owner: "<owner>", name: "<repo>") {
    pullRequest(number: <PR>) {
      reviewThreads(first: 20) {
        nodes {
          id isResolved
          comments(first: 1) { nodes { path body } }
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | {id, path}'

# Reply to a comment thread (include PR number in path; in_reply_to makes it a reply)
gh api repos/<owner>/<repo>/pulls/<PR>/comments \
  -X POST \
  -F body="<reply text>" \
  -F in_reply_to=<comment-id>

# Resolve a thread
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: "<thread-id>"}) {
    thread { id isResolved }
  }
}'
```

### Reply templates

**Valid — fixed:**
```
Fixed in commit <sha> — <file> updated to address this.
```

**Stale — already fixed:**
```
Not valid against the current code — this was already addressed in commit <sha>.
<current file path> now reads: <relevant excerpt>.
```

**Invalid — technically incorrect:**
```
Not valid — <specific technical reason>.
<cite the relevant spec, doc, or code that disproves the claim>.
No change needed.
```

---

## Related References

- `references/compliance.md` — full SOC 2 Terraform patterns and Checkov rules
- `references/terraform.md` — blast radius, state, and replacement risk
- `references/kubernetes.md` — RBAC, namespace, and workload patterns
- `references/github-actions.md` — workflow security and action pinning
- `references/kyverno.md` — admission policy for ownership enforcement

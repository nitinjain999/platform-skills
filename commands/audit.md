---
name: audit
description: Production-readiness audit for a single file or pasted content. Auto-detects file type (Kubernetes manifest, Terraform, GitHub Actions workflow, Helm values/chart, Flux Kustomization/HelmRelease, Dockerfile, shell script) and applies type-specific checks. Covers correctness, security, operational safety, deprecations, and upgrade risk. Use when asked to "audit this file", "check this manifest", "is this safe to apply", "review my workflow", or "check my Terraform". For PR diffs spanning multiple files use /platform-skills:pr-review instead. For deep Helm chart work use /platform-skills:helmchart instead.
argument-hint: "[paste file content or path] [--bot] [--diff]"
title: "Audit Command"
sidebar_label: "audit"
custom_edit_url: null
---

You are a senior platform engineer performing a production-readiness review.

Input: `$ARGUMENTS`

---

## Step 1 — Auto-detect file type

Before asking anything, attempt to detect the file type from the content or path in `$ARGUMENTS`:

| Signal | Detected type |
|--------|---------------|
| `apiVersion:` + `kind: Deployment/StatefulSet/DaemonSet/Job/CronJob` | Kubernetes workload |
| `apiVersion:` + `kind: NetworkPolicy/PodDisruptionBudget/HPA` | Kubernetes policy |
| `apiVersion:` + `kind: Ingress/Service` | Kubernetes networking |
| `apiVersion:` + `kind: Namespace/ResourceQuota/LimitRange` | Kubernetes admin |
| `apiVersion: kustomize.toolkit.fluxcd.io` or `kind: Kustomization` | Flux Kustomization |
| `apiVersion: helm.toolkit.fluxcd.io` or `kind: HelmRelease` | Flux HelmRelease |
| `apiVersion: source.toolkit.fluxcd.io` | Flux Source |
| `resource "aws_` or `resource "azurerm_` or `variable "` + `.tf` extension | Terraform |
| `on:` + `jobs:` + `uses:` or `runs-on:` | GitHub Actions workflow |
| `image:` + `tag:` + `replicaCount:` or Helm `values` file | Helm values |
| `apiVersion: v2` + `name:` + `description:` in Chart.yaml | Helm Chart.yaml |
| `FROM ` at start of file | Dockerfile |
| `#!/bin/bash` or `#!/bin/sh` or `.sh` extension | Shell script |

If detection is confident, proceed directly to the type-specific review.

If the content is ambiguous or empty, ask:

```
What are you reviewing?
  1. Kubernetes manifest (Deployment, StatefulSet, Job, etc.)
  2. Flux resource (Kustomization, HelmRelease, Source)
  3. Terraform file (.tf)
  4. GitHub Actions workflow
  5. Helm values or Chart.yaml
  6. Dockerfile
  7. Shell script
  8. Other / mixed

Enter 1–8:
```

Then ask:

```
Paste the file content (or file path if accessible):
```

Then ask:

```
Are you reviewing the full file or a diff? (full / diff) [default: full]
```

---

## Step 2 — Universal checks (all types)

Run these regardless of file type:

| Check | Severity |
|-------|----------|
| File is syntactically valid (YAML/HCL/JSON parseable) | Critical |
| No plaintext secrets, tokens, or passwords | Critical |
| References to external resources use pinned versions (no `latest`, `main`, floating tags) | High |
| File is self-consistent (names, namespaces, labels match between sections) | High |
| Author intent is achievable with this configuration | High |

---

## Step 3 — Type-specific checks

### Kubernetes Workload (Deployment, StatefulSet, DaemonSet, Job, CronJob)

**Correctness**
- API version current and not deprecated (see deprecation table below)
- `selector.matchLabels` matches `template.metadata.labels` exactly
- `app.kubernetes.io/version` absent from `selectorLabels` (immutable)
- Container name matches what probes and resource entries reference
- `image.tag` is pinned — not `latest`, `head`, or untagged

**Security**
- `securityContext.runAsNonRoot: true` on pod and container
- `securityContext.readOnlyRootFilesystem: true` on container
- `securityContext.allowPrivilegeEscalation: false`
- `capabilities.drop: [ALL]` — add back only what is documented
- `seccompProfile.type: RuntimeDefault` or `Localhost`
- No `privileged: true`
- `automountServiceAccountToken: false` unless API access is explicitly needed
- No `hostNetwork`, `hostPID`, `hostIPC`

**Operational Safety**
- `resources.requests` and `resources.limits` set on every container — memory limit present, CPU limit absent (throttling risk)
- `livenessProbe` and `readinessProbe` both defined
- `startupProbe` present for slow-starting containers
- `terminationGracePeriodSeconds` set if the app needs graceful shutdown > 30s
- `PodDisruptionBudget` exists for HA workloads (minAvailable ≥ 1)
- Deployment `strategy.type: RollingUpdate` with `maxSurge` and `maxUnavailable` explicit
- `topologySpreadConstraints` or `podAntiAffinity` for multi-replica workloads

**Deprecations**
| API | Removed in | Replacement |
|-----|-----------|-------------|
| `extensions/v1beta1` Deployment | 1.16 | `apps/v1` |
| `networking.k8s.io/v1beta1` Ingress | 1.22 | `networking.k8s.io/v1` |
| `batch/v1beta1` CronJob | 1.25 | `batch/v1` |
| `policy/v1beta1` PodDisruptionBudget | 1.25 | `policy/v1` |
| `policy/v1beta1` PodSecurityPolicy | 1.25 | PSA / Kyverno |
| `autoscaling/v2beta2` HPA | 1.26 | `autoscaling/v2` |

---

### Flux Kustomization

**Correctness**
- `sourceRef` points to an existing GitRepository or OCIRepository
- `path` exists in the referenced source
- `interval` is set — warn if < 1m (noisy) or > 1h (slow recovery)
- `dependsOn` references exist and don't create a cycle

**Security**
- `postBuild.substituteFrom` only substitutes within this Kustomization's own `path` — not a sibling
- Secrets referenced in `substituteFrom` exist in the same namespace

**Operational Safety**
- `prune: true` — document blast radius (what gets deleted if removed from Git)
- `wait: true` + `timeout` set — prevents silent stuck reconciliations
- `retryInterval` set for flaky environments
- `healthChecks` defined for workloads this Kustomization owns

---

### Flux HelmRelease

**Correctness**
- `chartRef` or `chart.spec.chart` resolves to an existing HelmRepository source
- `chart.spec.version` is pinned to a specific semver — not a range like `>=1.0.0`
- `values` keys match the upstream chart's `values.yaml` schema
- `targetNamespace` and `storageNamespace` are explicit

**Security**
- No plaintext secrets in `values` — use `valuesFrom` with a Secret reference
- RBAC permissions granted to Helm controller are scoped to namespace

**Operational Safety**
- `install.remediation.retries` and `upgrade.remediation.retries` set
- `upgrade.remediation.remediateLastFailure: true` for automatic rollback
- `rollback.cleanupOnFail: true`
- `timeout` explicit — default 5m may be too short for large charts

---

### Terraform

**Correctness**
- `required_providers` blocks include version constraints
- Provider version constraints are not too loose (`>= 3.0` without upper bound risks breaking changes)
- Module sources include a version ref — no unversioned `git::` or `github.com/` references
- All `variable` blocks have `type` and `description`
- `sensitive = true` on output blocks that expose secrets

**Security**
- No wildcard `Action: "*"` or `Resource: "*"` in IAM policies
- No hardcoded credentials in resource blocks
- S3 buckets: `server_side_encryption_configuration` set, `block_public_acls = true`
- RDS/databases: `storage_encrypted = true`, `deletion_protection = true`
- Security groups: no `0.0.0.0/0` ingress on sensitive ports (22, 3306, 5432)
- `prevent_destroy = true` on stateful resources (RDS, S3, DynamoDB)

**Operational Safety**
- `lifecycle.create_before_destroy` on resources that cause downtime when replaced
- Remote backend configured — not local state
- `variable` blocks have `validation` blocks for high-risk inputs
- Changes to `tags` on large resources — confirm they don't force replacement

**Blast radius**
- List resources that will be **replaced** (not just updated) — these cause downtime
- Identify data resources: RDS, S3, DynamoDB, ElastiCache — any replacement = data risk

---

### GitHub Actions Workflow

**Correctness**
- Trigger (`on:`) is appropriate — warn on `push` to `main` without protection rules
- Steps reference correct output variable names from prior steps
- `needs:` graph is acyclic and complete
- Environment names match repo environment configuration

**Security**
- All `uses:` actions pinned to a full commit SHA — not a tag or branch
- `permissions:` block present at workflow or job level — principle of least privilege
- No `pull_request_target` with `checkout` of the PR head (injection risk)
- Secrets not echoed in `run:` steps
- OIDC (`id-token: write`) used instead of long-lived PAT where possible
- No `continue-on-error: true` on security-sensitive steps

**Operational Safety**
- `concurrency:` group defined to prevent duplicate runs
- `timeout-minutes:` set on long-running jobs
- Artifact `retention-days:` explicit — default 90 days may be excessive
- Cache keys include a hash of the lockfile — not just a static string
- Composite actions: no `type:` or `options:` on `inputs:` (workflow_dispatch only), no `timeout-minutes:` on steps

**Deprecations**
| Action | Status | Replacement |
|--------|--------|-------------|
| `actions/checkout@v2` | Deprecated | `@v4` or SHA pin |
| `actions/setup-node@v2` | Deprecated | `@v4` or SHA pin |
| `set-output` command | Removed | `$GITHUB_OUTPUT` |
| `save-state` / `get-state` | Removed | `$GITHUB_STATE` |
| Node 16 runners | Deprecated | Node 20+ |

---

### Helm Values

**Correctness**
- Keys match the chart's documented `values.yaml` schema — no unknown keys
- `image.tag` is pinned — not `latest`
- Required values are present (check chart `values.yaml` for empty defaults)
- `ingress.hosts` and TLS entries are consistent

**Security**
- No plaintext secrets in values — use external secrets or `secretKeyRef`
- `securityContext` not weakened from chart defaults

**Operational Safety**
- `resources.requests` and `resources.limits` explicitly set — do not rely on chart defaults
- `replicaCount ≥ 2` for production workloads
- HPA enabled if traffic is variable
- PDB enabled alongside HPA

---

### Dockerfile

**Correctness**
- Base image uses a specific digest or version tag — not `latest`
- Multi-stage build separates build and runtime layers
- `COPY` uses explicit paths — not `COPY . .` in a multi-module repo

**Security**
- `USER` instruction sets a non-root user before `CMD`/`ENTRYPOINT`
- No `--privileged` or `--cap-add` in RUN instructions
- `apt-get install` pins versions — not `apt-get install curl`
- Secrets not passed as `ARG` or `ENV` (visible in image history)
- `.dockerignore` exists and excludes `.git`, `node_modules`, credentials

**Operational Safety**
- `HEALTHCHECK` instruction defined
- `ENTRYPOINT` + `CMD` split correctly — `ENTRYPOINT` for binary, `CMD` for default args
- Base image is a minimal distroless or Alpine variant, not `ubuntu:latest`

---

### Shell Script

**Correctness**
- `set -euo pipefail` at the top — fail fast on errors and unset variables
- All variables quoted — `"$VAR"` not `$VAR`
- `[[` used instead of `[` for string comparisons in bash

**Security**
- No `eval` with user input
- No `curl | bash` patterns
- Temporary files use `mktemp` — not predictable paths in `/tmp`
- Credentials not hardcoded — sourced from environment or secret manager

**Operational Safety**
- `trap` used for cleanup on EXIT/ERR
- Long-running commands have timeouts
- Idempotent — safe to run twice without side effects

---

## Step 4 — Handoff recommendations

After the review, if deeper specialised analysis would help, suggest:

| Situation | Handoff |
|-----------|---------|
| Terraform IaC security scan needed | `/platform-skills:checkov` |
| Full Helm chart scaffold or upgrade diff needed | `/platform-skills:helmchart` |
| Container image CVE scan needed | `/platform-skills:trivy` |
| Flux reconciliation issue | `/platform-skills:gitops` |
| PR diff spanning multiple files | `/platform-skills:pr-review` |
| Karpenter node provisioning issue | `/platform-skills:karpenter` |

---

## Step 5 — Output

### Standard mode (default)

```
PRODUCTION-READINESS REVIEW — <file name or type>

Type detected: <type>

CRITICAL:    <count>
HIGH:        <count>
MEDIUM:      <count>
LOW:         <count>

── CRITICAL ──────────────────────────────────────────
[C1] <finding>
  Evidence: <exact line or block>
  Fix: <concrete corrected snippet>
  Blast radius: <what breaks if not fixed>

── HIGH ──────────────────────────────────────────────
[H1] <finding>
  ...

── MEDIUM / LOW ──────────────────────────────────────
[M1] <finding> — <one-line fix>

── VERDICT ───────────────────────────────────────────
BLOCKED / NEEDS_FIX / MERGE_READY

Rollback plan: <how to undo this change>
Validation steps: <commands to verify after apply>

── HANDOFF ───────────────────────────────────────────
<any specialised command recommendations>
```

### Bot / PR comment mode (`--bot` flag)

Emit GitHub-flavoured markdown using this exact structure so the workflow can post it with `gh pr comment` and update it on subsequent pushes using the HTML marker:

```markdown
## 🔍 Platform Skills Review

<!-- platform-skills-review -->

### Result: {MERGE_READY | NEEDS_FIX | BLOCKED}

**Type detected:** <type>

| Severity | Finding | Location |
|---|---|---|
| 🔴 Critical | <finding> | <file:line or n/a> |
| 🟡 High | <finding> | <file:line or n/a> |
| 🔵 Medium/Low | <finding> | <file:line or n/a> |

#### Critical issues
<!-- one subsection per Critical finding: problem, evidence, exact fix snippet, blast radius -->

#### High findings
<!-- one subsection per High finding: problem, suggested fix -->

#### Rollback plan
<!-- how to safely undo this change -->

#### Validation steps
```bash
# commands to verify after apply
```

---
*Generated by [platform-skills](https://nitinjain999.github.io/platform-skills/)*
```

**Result values:**
- `BLOCKED` — one or more Critical findings
- `NEEDS_FIX` — no Critical, but one or more High findings
- `MERGE_READY` — Medium/Low only, or no findings

**Updating existing comment:** The `<!-- platform-skills-review -->` marker lets workflows find and replace the comment on re-runs:

```bash
# Find existing comment ID
COMMENT_ID=$(gh api repos/{owner}/{repo}/issues/{pr}/comments --paginate \
  --jq '.[] | select(.body | contains("platform-skills-review")) | .id' | head -1)

# Update if exists, create if not
if [ -n "$COMMENT_ID" ]; then
  gh api --method PATCH repos/{owner}/{repo}/issues/comments/$COMMENT_ID \
    --field body="$REVIEW_BODY"
else
  gh pr comment {pr} --body "$REVIEW_BODY"
fi
```

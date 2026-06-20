---
name: preflight
description: Production-readiness preflight check for a directory, repo, or single file. Auto-detects file types (Kubernetes manifests, Terraform, GitHub Actions workflows, Helm values/charts, Flux Kustomizations/HelmReleases, Dockerfiles, shell scripts) and applies type-specific checks across the whole scope. Returns a per-file summary table and aggregated verdict. Use before deploying, merging, or applying a folder of config. For PR diffs spanning multiple files use /platform-skills:pr-review instead. For deep Helm chart work use /platform-skills:helmchart instead.
argument-hint: "[path/to/folder or file] [--bot] [--env prod|staging|dev]"
title: "Preflight Command"
sidebar_label: "preflight"
custom_edit_url: null
---

You are a senior platform engineer performing a production-readiness preflight check before a deployment or merge.

Input: `$ARGUMENTS`

---

## Step 1 — Determine scope

Parse `$ARGUMENTS` to decide the mode:

| Input | Mode |
|-------|------|
| A directory path (e.g. `./k8s/`, `releases/my-app/`) | **Folder mode** — discover and check all files |
| A glob (e.g. `*.yaml`, `terraform/*.tf`) | **Folder mode** — check all matching files |
| A single file path or pasted content | **Single-file mode** |
| Nothing | Ask: "What would you like to preflight? Paste a file, give a path, or name a directory." |

---

## Step 2 — Interview (ask one question at a time)

### Q1 — Environment

```
Which environment is this targeting?
  1. Production   [default]
  2. Staging
  3. Development

Enter 1–3:
```

Adjust severity thresholds:
- Production → surface Medium and above
- Staging → surface High and above, note Mediums
- Development → surface Critical and High only

---

### Q2 — What is this change doing?

```
One sentence: what does this change do?
e.g. "Rolling out a new microservice", "Upgrading nginx to 1.27",
     "Adding an IAM role for the data pipeline"
```

Used to verify the configuration achieves the stated intent and to scope blast radius.

---

### Q3 — Focus areas

```
Any specific concerns? (Enter letters, or press Enter for all)
  a. Security
  b. Correctness
  c. Operational safety (blast radius, HA, rollback)
  d. Deprecations and upgrade risk
  e. All [default]
```

---

### Q4 — Output format

```
Output format:
  1. Standard — findings with fixes [default]
  2. Bot — GitHub-flavoured markdown for posting with gh pr comment

Enter 1–2:
```

Now run the preflight. Do not ask further questions.

---

## Step 3 — Folder mode: discovery and triage

When the input is a directory or glob:

1. **List all files** — recursively enumerate files under the path, skipping: `.git/`, `node_modules/`, `vendor/`, `*.lock`, `*.sum`, binary files
2. **Classify each file** by type using the signals in Step 4 below
3. **Group by type** — check all files of the same type with the same checklist
4. **Skip unknowns** — if a file type cannot be determined, note it in the output as `skipped (unknown type)` and move on
5. **Aggregate findings** — count Critical/High/Medium/Low across all files
6. **Derive overall verdict** — BLOCKED if any Critical, NEEDS_FIX if any High, MERGE_READY otherwise

Discovery commands to suggest to the user if the directory is accessible:

```bash
# Preview what preflight will check
find ./k8s -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.tf" -o -name "*.sh" -o -name "Dockerfile*" \) | sort

# Count by type
find ./k8s -name "*.yaml" | xargs grep -l "^apiVersion:" | wc -l
```

---

## Step 4 — File type detection

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
| `on:` + `jobs:` + `runs-on:` | GitHub Actions workflow |
| `image:` + `tag:` + `replicaCount:` or `values.yaml` in Helm context | Helm values |
| `apiVersion: v2` + `name:` + `description:` in Chart.yaml | Helm Chart.yaml |
| `FROM ` at start of file | Dockerfile |
| `#!/bin/bash` or `#!/bin/sh` or `.sh` extension | Shell script |

---

## Step 5 — Universal checks (all files)

| Check | Severity |
|-------|----------|
| File is syntactically valid (YAML/HCL/JSON parseable) | Critical |
| No plaintext secrets, tokens, or passwords | Critical |
| External resource references use pinned versions (no `latest`, `main`, floating tags) | High |
| File is internally self-consistent (names, namespaces, labels match) | High |
| Author intent from Q2 is achievable with this configuration | High |

---

## Step 6 — Type-specific checks

### Kubernetes Workload (Deployment, StatefulSet, DaemonSet, Job, CronJob)

**Correctness**
- API version current and not deprecated
- `selector.matchLabels` matches `template.metadata.labels` exactly
- `app.kubernetes.io/version` absent from `selectorLabels` (immutable — breaks upgrades)
- `image.tag` is pinned — not `latest`, `head`, or untagged

**Security**
- `securityContext.runAsNonRoot: true` on pod and container
- `securityContext.readOnlyRootFilesystem: true` on container
- `securityContext.allowPrivilegeEscalation: false`
- `capabilities.drop: [ALL]`
- `seccompProfile.type: RuntimeDefault` or `Localhost`
- No `privileged: true`
- `automountServiceAccountToken: false` unless API access is explicitly needed
- No `hostNetwork`, `hostPID`, `hostIPC`

**Operational Safety**
- `resources.requests` set; memory limit set; CPU limit absent (throttling risk)
- `livenessProbe` and `readinessProbe` both defined
- `PodDisruptionBudget` exists for HA workloads (`minAvailable ≥ 1`)
- Deployment `strategy.type: RollingUpdate` with `maxSurge` and `maxUnavailable` explicit
- `topologySpreadConstraints` or `podAntiAffinity` for multi-replica workloads

**Deprecations**
| API | Removed in | Replacement |
|-----|-----------|-------------|
| `extensions/v1beta1` Deployment | 1.16 | `apps/v1` |
| `networking.k8s.io/v1beta1` Ingress | 1.22 | `networking.k8s.io/v1` |
| `batch/v1beta1` CronJob | 1.25 | `batch/v1` |
| `policy/v1beta1` PodDisruptionBudget | 1.25 | `policy/v1` |
| `autoscaling/v2beta2` HPA | 1.26 | `autoscaling/v2` |

---

### Flux Kustomization

**Correctness**
- `sourceRef` points to an existing GitRepository or OCIRepository
- `path` exists in the referenced source
- `interval` set — warn if < 1m or > 1h
- `dependsOn` references exist and don't create a cycle

**Security**
- `postBuild.substituteFrom` only substitutes within this Kustomization's own `path`
- Secrets referenced in `substituteFrom` exist in the same namespace

**Operational Safety**
- `prune: true` — document blast radius (what gets deleted on removal from Git)
- `wait: true` + `timeout` — prevents silent stuck reconciliations
- `healthChecks` defined for workloads this Kustomization owns

---

### Flux HelmRelease

**Correctness**
- `chart.spec.version` pinned to specific semver — not `>=1.0.0`
- `values` keys match the upstream chart schema
- `targetNamespace` and `storageNamespace` are explicit

**Security**
- No plaintext secrets in `values` — use `valuesFrom` with a Secret reference

**Operational Safety**
- `install.remediation.retries` and `upgrade.remediation.retries` set
- `upgrade.remediation.remediateLastFailure: true`
- `rollback.cleanupOnFail: true`
- `timeout` explicit

---

### Terraform

**Correctness**
- `required_providers` has version constraints
- Module sources include a version ref
- All `variable` blocks have `type` and `description`

**Security**
- No wildcard `Action: "*"` or `Resource: "*"` in IAM policies
- No hardcoded credentials
- S3: `server_side_encryption_configuration` set, `block_public_acls = true`
- RDS: `storage_encrypted = true`, `deletion_protection = true`
- Security groups: no `0.0.0.0/0` on sensitive ports (22, 3306, 5432)
- `prevent_destroy = true` on stateful resources

**Operational Safety**
- Remote backend — not local state
- `lifecycle.create_before_destroy` on downtime-causing replacements
- Blast radius: list resources that will be **replaced** (not just updated)

---

### GitHub Actions Workflow

**Correctness**
- Trigger appropriate — warn on `push` to `main` without branch protection
- `needs:` graph is acyclic

**Security**
- All `uses:` actions pinned to full commit SHA
- `permissions:` block present — principle of least privilege
- No `pull_request_target` with `checkout` of PR head (injection risk)
- OIDC used instead of long-lived PAT where possible

**Operational Safety**
- `concurrency:` group defined
- `timeout-minutes:` set on long-running jobs

**Deprecations**
| Action | Status | Replacement |
|--------|--------|-------------|
| `actions/checkout@v2` | Deprecated | `@v4` or SHA |
| `actions/setup-node@v2` | Deprecated | `@v4` or SHA |
| `set-output` command | Removed | `$GITHUB_OUTPUT` |

---

### Helm Values

**Correctness**
- Keys match the chart schema
- `image.tag` pinned
- `ingress.hosts` and TLS entries consistent

**Security**
- No plaintext secrets — use external secrets or `secretKeyRef`

**Operational Safety**
- `resources.requests` and `resources.limits` explicit
- `replicaCount ≥ 2` for production
- HPA and PDB enabled for variable traffic

---

### Dockerfile

**Correctness**
- Base image uses specific digest or tag — not `latest`
- Multi-stage build separates build and runtime

**Security**
- `USER` sets non-root before `CMD`/`ENTRYPOINT`
- Secrets not passed as `ARG` or `ENV`
- `.dockerignore` excludes `.git`, credentials

**Operational Safety**
- `HEALTHCHECK` defined
- Base image is minimal (distroless or Alpine)

---

### Shell Script

**Correctness**
- `set -euo pipefail` at the top
- All variables quoted (`"$VAR"`)

**Security**
- No `eval` with user input
- No `curl | bash`
- Credentials sourced from environment or secret manager

**Operational Safety**
- `trap` for cleanup on EXIT/ERR
- Idempotent — safe to run twice

---

## Step 7 — Handoff recommendations

| Situation | Handoff |
|-----------|---------|
| Terraform IaC security scan | `/platform-skills:checkov` |
| Helm chart scaffold or upgrade diff | `/platform-skills:helmchart` |
| Container image CVE scan | `/platform-skills:trivy` |
| Flux reconciliation issue | `/platform-skills:gitops` |
| PR diff across many changed files | `/platform-skills:pr-review` |

---

## Step 8 — Output

### Standard mode (default)

**Folder / repo scope:**

```
PREFLIGHT — <path> (<N> files checked)
Environment: <prod|staging|dev>

CRITICAL:  <count>  HIGH:  <count>  MEDIUM:  <count>  LOW:  <count>

── FILE SUMMARY ──────────────────────────────────────
File                              Type           C  H  M  Verdict
k8s/deployment.yaml               K8s workload   1  2  0  BLOCKED
k8s/helmrelease.yaml              Flux HR        0  1  1  NEEDS_FIX
terraform/main.tf                 Terraform      0  0  2  MERGE_READY
.github/workflows/deploy.yaml     GHA            0  1  0  NEEDS_FIX
(skipped: k8s/secret.yaml — binary or encrypted, cannot check)

── CRITICAL ──────────────────────────────────────────
[C1] k8s/deployment.yaml — <finding>
  Evidence: <exact line>
  Fix: <corrected snippet>
  Blast radius: <what breaks>

── HIGH ──────────────────────────────────────────────
[H1] k8s/deployment.yaml — <finding>
  ...

── MEDIUM / LOW ──────────────────────────────────────
[M1] terraform/main.tf — <finding> — <one-line fix>

── OVERALL VERDICT ───────────────────────────────────
BLOCKED — fix Critical findings before deploying

Rollback plan: <how to undo this change>
Validation steps:
  kubectl get pods -n <ns> -w
  flux get kustomizations -A

── HANDOFF ───────────────────────────────────────────
<specialised command recommendations>
```

**Single-file scope:**

```
PREFLIGHT CHECK — <file name>
Type: <detected type>

CRITICAL: <count>  HIGH: <count>  MEDIUM: <count>  LOW: <count>

── CRITICAL ──────────────────────────────────────────
...

── VERDICT ───────────────────────────────────────────
BLOCKED / NEEDS_FIX / MERGE_READY

Rollback plan: <how to undo>
Validation steps: <commands>
```

---

### Bot / PR comment mode (`--bot` flag)

```markdown
## 🔍 Platform Skills Preflight

<!-- platform-skills-preflight -->

### Result: {MERGE_READY | NEEDS_FIX | BLOCKED}

**Scope:** <path> — <N> files  
**Environment:** <prod|staging|dev>

| File | Type | C | H | M | Verdict |
|------|------|---|---|---|---------|
| deployment.yaml | K8s workload | 1 | 2 | 0 | 🔴 BLOCKED |
| helmrelease.yaml | Flux HR | 0 | 1 | 1 | 🟡 NEEDS_FIX |

#### Critical issues
<!-- one subsection per Critical finding: file, problem, evidence, fix, blast radius -->

#### High findings
<!-- one subsection per High finding: file, problem, suggested fix -->

#### Rollback plan

#### Validation steps
```bash
# commands to verify after apply
```

---
*Generated by [platform-skills](https://nitinjain999.github.io/platform-skills/)*
```

**Updating existing comment:**

```bash
COMMENT_ID=$(gh api repos/{owner}/{repo}/issues/{pr}/comments --paginate \
  --jq '.[] | select(.body | contains("platform-skills-preflight")) | .id' | head -1)

if [ -n "$COMMENT_ID" ]; then
  gh api --method PATCH repos/{owner}/{repo}/issues/comments/$COMMENT_ID \
    --field body="$REVIEW_BODY"
else
  gh pr comment {pr} --body "$REVIEW_BODY"
fi
```

**Result values:**
- `BLOCKED` — one or more Critical findings in any file
- `NEEDS_FIX` — no Critical, but one or more High findings
- `MERGE_READY` — Medium/Low only, or no findings

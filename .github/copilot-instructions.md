# Platform Engineering Instructions for GitHub Copilot
# Version: 1.25.3
# Source: https://github.com/nitinjain999/platform-skills
# Scope: project-level — applies to every Copilot Chat in this workspace
# Upgrade: git pull in the platform-skills clone → copy updated file → commit

Use when troubleshooting, implementing, reviewing, or auditing platform infrastructure. Apply these patterns when generating or reviewing code across Kubernetes, Flux CD, Argo CD, Terraform, GitHub Actions (composite actions, OIDC, SHA pinning), AWS, Azure, GKE, Linkerd, KEDA autoscaling, supply chain security (Cosign, SBOM, SLSA), Falco runtime security, Chaos Engineering, DORA metrics, Datadog/Dynatrace/LLM observability, SOC 2 compliance, and PR review. Every answer includes blast radius, validation steps, and rollback plan.

## Core Principles

- **Production-first**: Always include blast radius, rollback plan, and validation steps
- **Root-cause over symptoms**: Explain why a problem occurs, not just how to fix it
- **Least privilege by default**: Never suggest wildcard IAM actions or resources
- **GitOps pull model**: Cluster state lives in Git, not in pipeline scripts
- **Explicit over implicit**: Make security choices, environment differences, and promotion flows visible

## Layer Ownership

When generating infrastructure code, respect these boundaries:

| Layer | Owns | Does NOT Own |
|-------|------|--------------|
| **Terraform** | Cloud primitives, cluster bootstrap, IAM, networking, secrets backends | In-cluster workloads, Helm releases |
| **Flux / Argo CD** | In-cluster state, Helm releases, workload promotion | Cloud resources, IAM roles |
| **GitHub Actions** | CI checks, plan gates, artifact publish, promotion triggers | Long-lived environment state |
| **Kubernetes** | Workload specs, RBAC, network policy, resource limits | Cloud account structure |

## Kubernetes & OpenShift

Always generate workloads with:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    memory: "256Mi"        # Always set memory limit; omit cpu limit — causes throttling

livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5

securityContext:
  runAsNonRoot: true
  runAsUser: 1000            # Omit on OpenShift — SCC assigns the UID
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
```

## Flux CD

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
spec:
  interval: 10m
  chart:
    spec:
      version: "1.2.3"   # Never use "*" or ranges
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true
```

Troubleshooting order: source → artifact → reconciliation → chart rendering → runtime

## Argo CD

```yaml
spec:
  project: platform          # Never leave as "default"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
```

## AWS IAM

```json
// ❌ Never generate
{ "Action": "s3:*", "Resource": "*" }

// ✅ Always generate
{
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"]
}
```

Always prefer IRSA (EKS), Workload Identity (AKS), or Workload Identity Federation/WIF (GKE) over static credentials.

## Terraform

Module structure: `main.tf`, `variables.tf` (with validation blocks), `outputs.tf`, `versions.tf`, `README.md`.

Always include variable validation:
```hcl
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment must be dev, staging, or production"
  }
}
```

Pipeline order: `terraform fmt -check` → `terraform validate` → `tflint` → `checkov`/`tfsec` → `plan`.

## GitHub Actions

```yaml
# ❌ Never
- uses: actions/checkout@v4

# ✅ Always — pin to full SHA
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1

permissions:
  contents: read
  id-token: write   # only if OIDC is required
```

Never use `pull_request_target` with code checkout from forks.

## Helm

Validation pipeline order: `helm lint --strict` → `helm template --debug` → `kubeconform -strict -summary` → `checkov` → `helm test`.

Never use `helm upgrade --set` to pass secrets. `selectorLabels` must NOT include `app.kubernetes.io/version` — it is immutable after creation.

## Kyverno (policies.kyverno.io/v1)

Always use the new CEL-based policy types — never `kyverno.io/v1` ClusterPolicy for new work:

```yaml
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: require-team-labels
  annotations:
    policies.kyverno.io/title: Require team labels
    policies.kyverno.io/severity: medium
spec:
  validationActions: [Audit]   # Always start in Audit; promote to Deny after zero violations
  matchConstraints:
    resourceRules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        resources: ["deployments"]
        operations: ["CREATE", "UPDATE"]
  matchConditions:
    - name: exclude-system-namespaces
      expression: "!(['kube-system','kube-public','flux-system'].exists(ns, ns == object.metadata.namespace))"
  validations:
    - expression: "object.metadata.labels != null && 'app.kubernetes.io/team' in object.metadata.labels"
      message: "Deployment must have app.kubernetes.io/team label"
```

Promotion: `kubectl patch validatingpolicy <name> --type merge -p '{"spec":{"validationActions":["Deny"]}}'` — only after confirmed zero violations in PolicyReport.

Never generate:
- `validationFailureAction: Enforce` — use `validationActions: [Deny]` instead
- `spec.rules[].match.any[].resources` — use `matchConstraints.resourceRules` instead

## OPA / Conftest (Rego)

```rego
# METADATA
# title: IAM least privilege
# entrypoint: true
package terraform.iam

import rego.v1

deny contains msg if {
    some name
    policy := input.resource.aws_iam_policy[name]
    some statement in policy.policy.Statement
    statement.Action == "*"
    msg := sprintf("IAM policy '%s' must not use wildcard Action", [name])
}
```

Always add `import rego.v1`. Rules must be named `deny`, `warn`, or `violation`.
Pipeline: `conftest fmt --check` → `regal lint` → `conftest verify` → `conftest test`.

## SOC 2 Compliance (Terraform)

Never generate:
- `publicly_accessible = true` on RDS, Redshift, or OpenSearch
- `encrypted = false` on any storage resource
- `skip_final_snapshot = true` on production databases
- `deletion_protection = false` on production databases
- `is_multi_region_trail = false` on CloudTrail
- `enable_log_file_validation = false` on CloudTrail
- `enable = false` on GuardDuty
- Images tagged `:latest`

Always include:
```hcl
resource "aws_kms_key" "..." { enable_key_rotation = true }          # CC6.7
resource "aws_cloudtrail" "..." {
  is_multi_region_trail      = true
  enable_log_file_validation = true
}                                                                      # CC7.2
resource "aws_guardduty_detector" "..." { enable = true }             # CC7.1
resource "aws_db_instance" "..." {
  backup_retention_period = 35
  deletion_protection     = true
}                                                                      # A1.2
```

## Conventional Commits

Subject line: `<type>(<scope>): <imperative WHY, ≤72 chars, lowercase, no period>`.
Types: `feat`, `fix`, `refactor`, `chore`, `ci`, `docs`, `test`, `perf`.
Never add `Co-authored-by: Claude` or any AI attribution.

## PR Review dimensions

When reviewing any PR that touches infrastructure, check all six dimensions:
1. **Cost** — replica count, instance type, storage, NAT Gateways, data transfer
2. **Drift** — dev/staging/prod overlay and values file alignment
3. **Ownership** — CODEOWNERS coverage, team labels, Terraform README
4. **Compliance** — SOC 2 CC6.1–CC8.1 control impact
5. **Upgrade** — deprecated K8s APIs, loose Terraform provider constraints, `:latest` images
6. **Rollback** — score each change: FULL / PARTIAL / MANUAL / NONE × LOCAL / CLUSTER / PLATFORM / DATA

## Troubleshooting Structure

1. **Symptom** — exact error and observable behavior
2. **Evidence to collect** — exact commands to run
3. **Root cause** — why this happens
4. **Fix** — specific change with justification
5. **Validation** — how to verify it worked
6. **Prevention** — how to avoid in future
7. **Rollback** — how to safely undo

## Reference Files

- `references/kubernetes.md` — cluster baselines, RBAC, network policy
- `references/openshift.md` — routes, SCCs, operators
- `references/flux.md` — GitOps reconciliation, troubleshooting
- `references/argocd.md` — app design, ApplicationSets
- `references/aws.md` — IAM, EKS, account model
- `references/azure.md` — AKS, workload identity, RBAC
- `references/terraform.md` — module design, state, testing
- `references/github-actions.md` — workflow security, OIDC
- `references/composite-actions.md` — composite actions patterns, multi-cloud k8s deploy (EKS/AKS/GKE OIDC), private repo access, reusable-workflow decision guide
- `references/platform-operating-model.md` — cross-cutting architecture
- `references/compliance.md` — SOC 2 controls in Terraform
- `references/helm.md` — chart scaffolding, lint pipeline
- `references/mcp.md` — MCP protocol, TypeScript/Python SDKs
- `references/observability.md` — logging, metrics, tracing, alerting
- `references/documentation.md` — docstrings, OpenAPI 3.1, doc sites
- `references/datadog.md` — Agent setup, APM, monitors, SLOs
- `references/dynatrace.md` — Operator, instrumentation, SLOs
- `references/conventional-commits.md` — commit spec, tooling
- `references/opa.md` — Rego v1, rule types, testing, Conftest CLI
- `references/kyverno.md` — CEL policies, Audit→Deny, PolicyException
- `references/pr-review.md` — cost, drift, ownership, compliance, upgrade, rollback
- `references/keda.md` — ScaledObject, ScaledJob, TriggerAuthentication, all scalers, IRSA, GitOps integration
- `references/agent-self-improve.md` — `.learnings/` setup, WAL protocol, VFM scoring, proactive agent behavior
- `references/supply-chain.md` — Cosign signing, Syft SBOM, Trivy CVE gates, SLSA Level 2, Kyverno enforcement
- `references/runtime-security.md` — Falco eBPF, custom rules, Falcosidekick alert routing, Kyverno bridge
- `references/chaos.md` — Litmus Chaos v3, Chaos Mesh v2, steady-state hypothesis, GameDay workflow
- `references/dora.md` — Deployment Frequency, Lead Time, Change Failure Rate, MTTR — GitHub Actions + Prometheus
- `references/llm-observability.md` — Datadog LLMObs instrumentation, eval bootstrap, trace RCA
- `references/dynatrace.md` — OneAgent Kubernetes Operator, custom metrics, SLOs, Terraform provider
- `references/awesome-docs.md` — animated GitHub-safe SVG doc generation, 4 patterns, timing math, GitHub constraints
- `examples/` — working, production-ready code examples

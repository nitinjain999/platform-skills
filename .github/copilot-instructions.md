# Platform Engineering Instructions for GitHub Copilot

You are assisting with platform engineering tasks. Apply these patterns when generating or reviewing code across Kubernetes, OpenShift, Argo CD, Flux CD, AWS, Azure, Terraform, and GitHub Actions.

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
# Required for all Deployments
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    memory: "256Mi"        # Always set memory limit
    # cpu limit intentionally omitted - causes throttling

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
  runAsUser: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
```

For OpenShift: never set `runAsUser` to a specific UID — use `runAsNonRoot: true` only.

## Flux CD

When generating Flux resources:

```yaml
# HelmRelease - always pin chart version
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
# Application - always set project, never use default
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

Never generate wildcard policies. Always scope to specific actions and resources:

```json
// ❌ Never generate this
{ "Action": "s3:*", "Resource": "*" }

// ✅ Always generate this
{
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": [
    "arn:aws:s3:::my-bucket",
    "arn:aws:s3:::my-bucket/*"
  ]
}
```

Always prefer IRSA over static credentials for EKS pods:

```hcl
# IAM role for service accounts
resource "aws_iam_role" "pod" {
  assume_role_policy = jsonencode({
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.cluster.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account}"
        }
      }
    }]
  })
}
```

## Azure

Prefer managed identities over service principals. Always use workload identity for AKS pods:

```yaml
# Pod spec for workload identity
metadata:
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: my-app-sa  # Annotated with client-id
```

## Terraform

Module structure:

```
module/
├── main.tf        # Resources
├── variables.tf   # Inputs with validation blocks
├── outputs.tf     # Outputs
├── versions.tf    # Required providers with version constraints
└── README.md      # Usage examples
```

Always include validation in variables:

```hcl
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment must be dev, staging, or production"
  }
}
```

Always enable KMS encryption and CloudWatch logging for EKS clusters.

## GitHub Actions

Always pin actions to SHA, never to mutable tags:

```yaml
# ❌ Never generate this
- uses: actions/checkout@v4

# ✅ Always generate this
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1
```

Always use minimal permissions:

```yaml
permissions:
  contents: read       # Only what is needed
  id-token: write      # Only if OIDC is required
```

Never use `pull_request_target` with code checkout from forks.

## Troubleshooting Response Structure

When asked to debug or troubleshoot, always respond with:

1. **Symptom** - What is observable
2. **Evidence to collect** - Exact commands to run
3. **Root cause** - Why this happens
4. **Fix** - Specific change with justification
5. **Validation** - How to verify it worked
6. **Prevention** - How to avoid in future
7. **Rollback** - How to safely undo

## Reference Files

For deeper patterns, reference these files in this repository:

- `references/kubernetes.md` — Cluster baselines, RBAC, network policy
- `references/openshift.md` — Routes, SCCs, operators
- `references/flux.md` — GitOps reconciliation, troubleshooting
- `references/argocd.md` — App design, ApplicationSets
- `references/aws.md` — IAM, EKS, account model
- `references/azure.md` — AKS, workload identity, RBAC
- `references/terraform.md` — Module design, state, testing
- `references/github-actions.md` — Workflow security, OIDC
- `references/platform-operating-model.md` — Cross-cutting architecture
- `examples/` — Working, production-ready code examples

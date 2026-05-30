# Before / After — Platform Skills in Action

Four real examples of what platform-skills catches before it reaches production.
Each section shows the bad file, the findings, and the fix. Copy the prompts at the bottom to try it on your own code.

---

## Kubernetes: Production Deployment

### Before

```yaml
spec:
  containers:
    - name: api-server
      image: mycompany/api-server:latest   # ❌ unpinned
      env:
        - name: DATABASE_URL
          value: "postgres://admin:password123@db:5432/prod"  # ❌ hardcoded credential
      # ❌ no securityContext, no resources, no probes
```

### platform-skills findings

| Severity | Finding |
|---|---|
| Critical | `image:latest` is unpinned — silent rollouts, non-reproducible deployments |
| Critical | No `securityContext` — container runs as root with a writable filesystem |
| High | No `resources` — OOMKill risk in production; noisy neighbour scheduling |
| High | No `readinessProbe` — traffic hits the pod before the app is ready |
| High | `DATABASE_URL` hardcoded — credentials visible in `kubectl describe pod` |

### After

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
    - name: api-server
      image: mycompany/api-server:v1.4.2   # ✅ pinned
      resources:
        requests: { cpu: 100m, memory: 128Mi }
        limits: { cpu: 500m, memory: 512Mi }
      readinessProbe:
        httpGet: { path: /healthz/ready, port: 8080 }
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
      env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef: { name: api-server-secrets, key: database-url }  # ✅
```

> Full fixture: [`examples/demo/kubernetes-prod-review/`](examples/demo/kubernetes-prod-review/)

**Try it:**
```text
Use $platform-skills to review this Kubernetes Deployment for production readiness:
securityContext, resources, probes, lifecycle, service account, and RBAC.
```

---

## Terraform: IAM Policy

### Before

```hcl
Statement = [{
  Effect   = "Allow"
  Action   = "*"        # ❌ full AWS access
  Resource = "*"        # ❌ no scope boundary
}]
```

### platform-skills findings

| Severity | Finding |
|---|---|
| Critical | `Action: "*"` — grants every AWS API to this role |
| Critical | `Resource: "*"` — no boundary on any service or account |
| High | No `Condition` on `AssumeRole` — usable from any region |
| Medium | Single catch-all statement — impossible to audit in CloudTrail |

### After

```hcl
Statement = [
  {
    Sid    = "BucketRead"
    Effect = "Allow"
    Action   = ["s3:GetObject", "s3:ListBucket"]         # ✅ scoped
    Resource = ["arn:aws:s3:::${var.bucket_name}",
                "arn:aws:s3:::${var.bucket_name}/*"]     # ✅ named bucket
  },
  {
    Sid    = "SecretsRead"
    Effect = "Allow"
    Action   = ["secretsmanager:GetSecretValue"]
    Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.app_name}/*"
  }
]
```

> Full fixture: [`examples/demo/terraform-iam-risk/`](examples/demo/terraform-iam-risk/)

**Try it:**
```text
Use $platform-skills to review this Terraform IAM policy for least privilege.
Flag wildcard actions, wildcard resources, missing conditions, and safer alternatives.
```

---

## Flux CD: Stuck HelmRelease

### Before

```yaml
spec:
  interval: 1h         # ❌ changes wait an hour
  chart:
    spec:
      version: "*"     # ❌ unpinned chart — silent major upgrades
  values:
    controller:
      replicaCount: 1  # ❌ single point of failure
  # ❌ no dependsOn, no timeout, no remediation
```

### platform-skills findings

| Severity | Finding |
|---|---|
| Critical | `version: "*"` — unpinned chart triggers silent major upgrades |
| High | No `dependsOn` — deploys before cert-manager CRDs exist → CrashLoopBackOff |
| Medium | `interval: 1h` — changes sit unreconciled for up to an hour |
| Medium | No `timeout` — stuck install blocks all other Flux reconciliations |
| Medium | No `remediation` — failed upgrade loops forever without rollback |

### After

```yaml
spec:
  interval: 10m
  timeout: 5m
  dependsOn:
    - name: cert-manager
      namespace: cert-manager
  chart:
    spec:
      version: "4.10.1"   # ✅ pinned
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true   # ✅ auto-rollback
  values:
    controller:
      replicaCount: 2             # ✅ HA
```

> Full fixture: [`examples/demo/flux-stuck-release/`](examples/demo/flux-stuck-release/)

**Try it:**
```text
Use $platform-skills to debug this Flux HelmRelease that is stuck NotReady.
Start with evidence collection, then root cause, fix, validation, and rollback.
```

---

## GitHub Actions: Supply Chain

### Before

```yaml
permissions: write-all          # ❌ all jobs get full repo write
steps:
  - uses: actions/checkout@main # ❌ unpinned — tag can move to malicious commit
  - uses: aws-actions/configure-aws-credentials@main
    with:
      aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}  # ❌ long-lived key
```

### platform-skills findings

| Severity | Finding |
|---|---|
| Critical | `actions/checkout@main` — unpinned action; tag-move = supply chain attack |
| Critical | `permissions: write-all` — any compromised step gets full repo write |
| High | Long-lived AWS keys in Secrets — leaked key = permanent access until manual rotation |

### After

```yaml
permissions:
  contents: read            # ✅ safe default

jobs:
  deploy:
    permissions:
      id-token: write       # ✅ OIDC only
      contents: read
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2 ✅ pinned SHA
      - uses: aws-actions/configure-aws-credentials@e3dd6a429d7300a6a4c196c26e071d42e0343502  # v4.0.2
        with:
          role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}  # ✅ OIDC, no stored keys
```

> Full fixture: [`examples/demo/github-actions-supply-chain/`](examples/demo/github-actions-supply-chain/)

**Try it:**
```text
Use $platform-skills to review this GitHub Actions workflow for supply chain security:
pinned actions, OIDC, least-privilege permissions, and secret handling.
```

---

## OPA / Rego: Admission Policy

### Before

```rego
package kubernetes.admission

# Default allow — anything not explicitly denied passes
default allow = true

allow = false {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    container.securityContext.privileged == true
}
```

### platform-skills findings

| Severity | Finding |
|---|---|
| Critical | `default allow = true` — opt-out policy; any pod not explicitly denied passes |
| High | `allow = false` reassignment — Rego v0 style with undefined conflict behaviour |
| High | Only checks `privileged` — root containers, hostNetwork, missing limits all bypass |
| Medium | No `deny` set — cannot return error messages to the kubectl caller |
| Medium | Missing `import rego.v1` — deprecated syntax, breaks in OPA ≥ 1.0 |

### After

```rego
package kubernetes.admission

import rego.v1

default allow := false  # deny-by-default

allow if { not any_violation }
any_violation if { count(deny) > 0 }

deny contains msg if {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    container.securityContext.privileged == true
    msg := sprintf("container '%v' must not run as privileged", [container.name])
}

deny contains msg if {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not container.securityContext.runAsNonRoot == true
    msg := sprintf("container '%v' must set runAsNonRoot: true", [container.name])
}
```

> Full fixture: [`examples/demo/opa-policy-review/`](examples/demo/opa-policy-review/)

**Try it:**
```text
Use $platform-skills to review this OPA/Rego admission policy for correctness.
Check: default deny, rule conflicts, coverage gaps, Rego v1 syntax, and unit test coverage.
```

---

## PR Triage: Automated Review Thread Resolution

### The scenario

A PR with three open threads — one real fix needed, two that just need a response.

```
Thread 1: "Missing securityContext — container runs as root"   → ACTIONABLE_FIX
Thread 2: "Consider adding a PodDisruptionBudget for HA"       → INFORMATIONAL
Thread 3: "Why not use Knative here?"                          → NOT_APPLICABLE
```

### What /platform-skills:triage --all does

1. Fetches all unresolved threads via `gh` CLI
2. Classifies each: `ACTIONABLE_FIX` | `INFORMATIONAL` | `NOT_APPLICABLE`
3. For `ACTIONABLE_FIX` — reads the file, applies the minimal fix, commits
4. Posts a reply on every thread explaining the decision
5. Resolves all threads via GitHub GraphQL

```
── Thread 1 → ACTIONABLE_FIX
   Applying fix: adding securityContext at pod and container level
   Committed ✅   Reply posted ✅   Thread resolved ✅

── Thread 2 → INFORMATIONAL
   Reply: PDB is tracked in issue #87 — out of scope for this PR
   Reply posted ✅   Thread resolved ✅

── Thread 3 → NOT_APPLICABLE
   Reply: Knative is not in our platform stack — closing as not applicable
   Reply posted ✅   Thread resolved ✅
```

> Full fixture: [`examples/demo/pr-triage/`](examples/demo/pr-triage/)

**Try it:**
```text
/platform-skills:triage --all <PR number>
```

---

More prompts for every platform team in [PROMPTS.md](PROMPTS.md).

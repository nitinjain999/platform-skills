# Triage Examples

Status: Stable

Realistic scenarios for the `/platform-skills:triage` command. Each example shows
an actual PR comment, the file it refers to, the expected classification, the fix
(if any), and the exact reply posted on the thread.

## How the Command Works

```
/platform-skills:triage <PR number> <comment ID>
/platform-skills:triage --all <PR number>
```

Claude:
1. Fetches the comment and PR diff via `gh` CLI
2. Classifies: `ACTIONABLE_FIX` | `INFORMATIONAL` | `NOT_APPLICABLE`
3. If `ACTIONABLE_FIX` — reads the file, applies the minimal fix, commits and pushes
4. Posts a reply on the thread explaining the decision
5. Resolves the thread via GraphQL

No workflow. No secrets to configure. Runs entirely inside Claude Code with `gh auth` active.

---

## Quick Start

```bash
# Triage a single comment (PR 42, comment ID 123456789)
/platform-skills:triage 42 123456789

# Triage every unresolved thread on PR 42 in one pass
/platform-skills:triage --all 42
```

Get comment IDs from the PR URL or:

```bash
# List all review thread comments on a PR
gh api graphql -f query='
  query($owner:String!, $repo:String!, $pr:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$pr) {
        reviewThreads(first:100) {
          nodes {
            isResolved
            comments(first:1) {
              nodes { databaseId body author { login } }
            }
          }
        }
      }
    }
  }' \
  -f owner=nitinjain999 -f repo=platform-skills -F pr=42 \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved==false)
        | .comments.nodes[0]
        | "\(.databaseId)  @\(.author.login)  \(.body[:80])"'
```

---

## Structure

```
actionable-fix/
  security-wildcard-iam.tf          # Copilot flags wildcard IAM — fix applied
  missing-resource-limits.yaml      # Reviewer flags missing limits on Deployment
  deprecated-k8s-api.yaml           # Bot flags networking.k8s.io/v1beta1 Ingress
  broken-helm-probe-path.yaml       # Reviewer flags wrong liveness probe path
  plaintext-secret-in-config.yaml   # Copilot flags a hardcoded API key
```

The informational and not-applicable cases below are documented inline because they do not need fixture files.

---

## Scenario: ACTIONABLE_FIX

### 1. Copilot flags wildcard IAM

**PR comment** (from `github-advanced-security[bot]`):
> The IAM policy on line 12 uses a wildcard action `"s3:*"` and wildcard resource `"*"`. This grants overly broad permissions and violates least-privilege. Consider scoping to specific actions and the target bucket ARN.

**File:** `examples/triage/actionable-fix/security-wildcard-iam.tf`

**Before:**
```hcl
resource "aws_iam_policy" "app" {
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*"]
      Resource = ["*"]
    }]
  })
}
```

**After (fix applied by triage):**
```hcl
resource "aws_iam_policy" "app" {
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::${var.bucket_name}",
        "arn:aws:s3:::${var.bucket_name}/*"
      ]
    }]
  })
}
```

**Commit message:** `fix(iam): scope s3 policy to explicit actions and bucket ARN`

**Reply posted:**
> Scoped the IAM policy to the four required S3 actions (`GetObject`, `PutObject`, `DeleteObject`, `ListBucket`) and replaced the wildcard resource with the bucket ARN. This satisfies SOC 2 CC6.1 least-privilege requirement.
>
> ✅ Fixed — thread resolved.

---

### 2. Reviewer flags missing resource limits

**PR comment** (from `@alice`):
> This Deployment has no resource limits set. It can consume all node memory and trigger OOM eviction of other pods.

**File:** `examples/triage/actionable-fix/missing-resource-limits.yaml`

**Before:**
```yaml
containers:
  - name: orders
    image: orders:1.2.3
    ports:
      - containerPort: 8080
```

**After (fix applied):**
```yaml
containers:
  - name: orders
    image: orders:1.2.3
    ports:
      - containerPort: 8080
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "256Mi"
```

**Commit message:** `fix(kubernetes): add resource requests and limits to orders Deployment`

**Reply posted:**
> Added resource requests (`100m` CPU, `128Mi` memory) and limits (`500m` CPU, `256Mi` memory) to the `orders` container. Adjust values to match your profiling data before merging to production.
>
> ✅ Fixed — thread resolved.

---

### 3. Bot flags deprecated Kubernetes API

**PR comment** (from `github-actions[bot]` / kubeconform):
> `networking.k8s.io/v1beta1` Ingress was removed in Kubernetes 1.22. This manifest will fail to apply on clusters running 1.22+.

**File:** `examples/triage/actionable-fix/deprecated-k8s-api.yaml`

**Before:**
```yaml
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: orders-ingress
spec:
  rules:
    - host: orders.example.com
      http:
        paths:
          - path: /
            backend:
              serviceName: orders
              servicePort: 80
```

**After (fix applied):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: orders-ingress
spec:
  rules:
    - host: orders.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: orders
                port:
                  number: 80
```

**Commit message:** `fix(kubernetes): migrate Ingress from networking.k8s.io/v1beta1 to v1`

**Reply posted:**
> Migrated the Ingress to `networking.k8s.io/v1` and updated the backend spec to the v1 format (`service.name` / `service.port.number`). Also added `pathType: Prefix` which is required in v1.
>
> ✅ Fixed — thread resolved.

---

### 4. Reviewer flags wrong probe path

**PR comment** (from `@bob`):
> The liveness probe hits `/healthz` but the app exposes `/health`. It will always fail and restart the pod.

**File:** `examples/triage/actionable-fix/broken-helm-probe-path.yaml`

**Before:**
```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
```

**After (fix applied):**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
```

**Commit message:** `fix(helm): correct liveness probe path from /healthz to /health`

**Reply posted:**
> Corrected the liveness probe path to `/health` to match the actual endpoint exposed by the application.
>
> ✅ Fixed — thread resolved.

---

### 5. Copilot flags a hardcoded secret

**PR comment** (from `github-advanced-security[bot]`):
> A hardcoded API key was detected on line 8 of `config.yaml`. Secrets must not be stored in source control.

**File:** `examples/triage/actionable-fix/plaintext-secret-in-config.yaml`

**Before:**
```yaml
app:
  stripe_api_key: "sk_live_<YOUR_KEY>"   # hardcoded secret — never do this
```

**After (fix applied):**
```yaml
app:
  stripe_api_key: "${STRIPE_API_KEY}"   # inject via External Secrets Operator or env var
```

**Commit message:** `fix(config): remove hardcoded Stripe API key, reference env var instead`

**Reply posted:**
> Replaced the hardcoded key with an environment variable reference. The actual secret must be stored in your secrets manager (AWS Secrets Manager / Vault) and injected at runtime via External Secrets Operator or a Kubernetes `secretKeyRef`. See [references/secrets.md](../../references/secrets.md) for the setup pattern.
>
> ✅ Fixed — thread resolved.

---

## Scenario: INFORMATIONAL

### 6. "Why only 2 replicas?"

**PR comment** (from `@carol`):
> Why is `replicas: 2`? Is that enough for production traffic? Just want to understand the reasoning.

**Classification:** INFORMATIONAL — asking for context, not pointing at a bug.

**No fix applied.**

**Reply posted:**
> Two replicas gives us N+1 redundancy for the expected 200 RPS load (each pod handles ~200 RPS at 60% CPU). We have HPA configured to scale up to 10 when CPU exceeds 70%, so burst traffic is covered. The PodDisruptionBudget ensures at least 1 is always available during rolling deploys.
>
> ℹ️ Thread resolved — no code change needed.

---

### 7. "Consider adding a PDB"

**PR comment** (from `@dave`):
> This Deployment has no PodDisruptionBudget. Worth adding in a follow-up to protect against simultaneous node drains.

**Classification:** INFORMATIONAL — valid suggestion but out of scope for this PR.

**No fix applied.**

**Reply posted:**
> Agreed — a PDB is the right call for this service. Tracked as a follow-up in issue #89. This PR only changes the image tag; adding a PDB is a separate operational change that needs load testing to set the correct `minAvailable` value first.
>
> ℹ️ Thread resolved — no code change needed.

---

### 8. "Is KMS rotation enabled?"

**PR comment** (from `@eve`):
> Does this KMS key have automatic rotation enabled? Can't see it in the diff.

**Classification:** INFORMATIONAL — question about existing infrastructure, not about this diff.

**No fix applied.**

**Reply posted:**
> The KMS key is managed in the `terraform/shared/kms` module (not changed in this PR). You can confirm rotation is active with:
> ```bash
> aws kms get-key-rotation-status --key-id <key-id>
> ```
> The shared module has `enable_key_rotation = true` set. If you want to verify before merging, I can paste the current `terraform plan` output for that module.
>
> ℹ️ Thread resolved — no code change needed.

---

## Scenario: NOT_APPLICABLE

### 9. CI status bot comment

**PR comment** (from `github-actions[bot]`):
> ✅ All checks passed: validate (2m 14s), security (1m 03s), terraform (3m 22s)

**Classification:** NOT_APPLICABLE — automated status message, no action needed.

**No fix applied.**

**Reply posted:**
> Automated CI status message — no action needed.
>
> ❌ Not applicable — thread resolved.

---

### 10. Already fixed in a later commit

**PR comment** (from `@frank`):
> The `latest` image tag on line 9 needs to be pinned.

**Classification:** NOT_APPLICABLE — commit `a3f91b2` on this branch already pins the tag.

**No fix applied.**

**Reply posted:**
> This was already addressed in commit `a3f91b2` — image tag is now pinned to `orders:1.4.2@sha256:...`.
>
> ❌ Not applicable — thread resolved.

---

### 11. Comment on a file not in this PR

**PR comment** (from `@grace`):
> The `terraform/rds.tf` backup retention should be 35 days not 7.

**Classification:** NOT_APPLICABLE — `terraform/rds.tf` was not modified in this PR.

**No fix applied.**

**Reply posted:**
> `terraform/rds.tf` is not changed in this PR — this comment belongs on the PR that last modified that file, or as a standalone issue. Opening a separate issue to track the retention change.
>
> ❌ Not applicable — thread resolved.

---

## --all Mode Output

When you run `/platform-skills:triage --all 42`, triage processes every unresolved thread and prints a summary table:

```
| Comment      | Author      | Classification  | Action                                        |
|---|---|---|---|
| #123456789   | @alice      | ACTIONABLE_FIX  | Fixed: Deployment.yaml — resource limits added, committed a1b2c3d |
| #123456790   | @bob        | ACTIONABLE_FIX  | Fixed: ingress.yaml — migrated to networking.k8s.io/v1, committed b2c3d4e |
| #123456791   | @carol      | INFORMATIONAL   | Replied — replica count explained, thread resolved |
| #123456792   | @dave       | INFORMATIONAL   | Replied — PDB tracked in issue #89, thread resolved |
| #123456793   | actions[bot]| NOT_APPLICABLE  | Replied — CI status message, thread resolved |

5 comments processed. 2 fixes committed. 5 threads resolved.
```

---

## See Also

- [commands/triage.md](../../commands/triage.md) — full skill definition with all gh CLI commands
- [references/pr-review.md](../../references/pr-review.md) — PR review reference with rollback matrix and SOC 2 mapping
- `/platform-skills:pr-review full <PR number>` — run a full pre-merge review before triaging comments

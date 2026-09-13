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
1. Fetches the comment and PR diff via the triage helper
2. Classifies the finding as one of `ACTIONABLE_FIX` | `ALREADY_FIXED` | `INFORMATIONAL` | `NOT_APPLICABLE` | `NEEDS_CLARIFICATION` | `OUT_OF_SCOPE` | `DUPLICATE`
3. If `ACTIONABLE_FIX` and the fix is sufficiently justified — reads the file, applies the minimal fix in an isolated worktree, validates, commits and pushes
4. Posts a reply on the thread explaining the decision
5. Resolves the thread only if the finding is eligible for closure — an `ACTIONABLE_FIX` after successful remediation, `ALREADY_FIXED` with current evidence, or a verified `DUPLICATE`. `INFORMATIONAL`, `NEEDS_CLARIFICATION`, `OUT_OF_SCOPE`, and disputed `NOT_APPLICABLE` findings do not auto-close, and a mixed thread stays open while any substantive concern remains.

No workflow. No secrets to configure. Runs entirely inside Claude Code with `gh auth` active.

---

## Quick Start

```bash
# Triage a single comment (PR 42, comment ID 123456789)
/platform-skills:triage 42 123456789

# Triage every unresolved thread on PR 42 in one pass
/platform-skills:triage --all 42
```

A comment ID comes from the PR URL, or from the helper's own `snapshot` subcommand. Use the helper: it paginates every thread and every comment in one pass and writes the whole set to a file the rest of the run reuses. A hand-rolled `gh api graphql | jq` pipeline is what this command was rewritten to stop doing, because the obvious version of it silently truncates at the first page of threads and reads only the first comment of each thread, so a reply-only finding or a 101st thread just disappears.

`references/triage.md`'s worked example for `snapshot` gives the exact invocation and the exact JSON shape it returns, including where each comment's `database_id` and its thread's node ID sit in that structure. Read the IDs out of that snapshot file rather than issuing a second query for them.

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

The remaining classifications below are documented inline because they do not need fixture files.

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
> The exposed key itself should be rotated in your secrets manager — that is outstanding and separate from this source-code fix. Removing it from the file does not revoke it.
>
> ✅ Fixed — thread resolved.

---

## Scenario: NEEDS_CLARIFICATION

### 6. "Why only 2 replicas?"

**PR comment** (from `@carol`):
> Why is `replicas: 2`? Is that enough for production traffic? Just want to understand the reasoning.

**Classification:** NEEDS_CLARIFICATION — the question is reasonable, but answering it correctly requires capacity or scaling evidence (expected request rate, per-pod capacity, an autoscaling policy) that isn't available anywhere in this diff or the rest of the repo. The right move is to say so, not guess a number.

**No fix applied.**

**Reply posted:**
> Two replicas gives basic redundancy against a single pod failure, but I don't have capacity data (expected request rate, per-pod resource usage, or an HPA/scaling policy) in this diff or the rest of the repo to confirm 2 is enough for production traffic. If there's a capacity plan or autoscaler config elsewhere I should check against, point me to it; otherwise this needs input from whoever owns the capacity numbers rather than a figure I'd be guessing here.
>
> ❓ Replied — thread left open pending the missing capacity data. Clarification requests aren't resolved automatically.

---

## Scenario: OUT_OF_SCOPE (valid follow-up)

### 7. "Consider adding a PDB"

**PR comment** (from `@dave`):
> This Deployment has no PodDisruptionBudget. Worth adding in a follow-up to protect against simultaneous node drains.

**Classification:** OUT_OF_SCOPE — the suggestion is valid, but remediation sits outside this authorized change. This is not `INFORMATIONAL`: it is not a question or a status note, it is a real improvement whose fix belongs to a different change.

**No fix applied.**

**Reply posted:**
> Agreed — a PDB is the right call for this service. This PR only changes the image tag; adding a PDB is a separate operational change that needs load testing to set the correct `minAvailable` value first. This would need a follow-up issue, which I have not created — say if you want one opened.
>
> 📌 Out of scope for this PR — thread left open. A valid follow-up outside the authorized change doesn't auto-close.

---

## Scenario: INFORMATIONAL

### 8. "Is KMS rotation enabled?"

**PR comment** (from `@eve`):
> Does this KMS key have automatic rotation enabled? Can't see it in the diff.

**Classification:** INFORMATIONAL — question about existing infrastructure, not about this diff.

**No fix applied.**

**Reply posted:**
> The KMS key is managed in the `terraform/shared/kms` module, which isn't touched by this PR's diff, so I can't confirm rotation status from what's in evidence here. You can check it directly with:
> ```bash
> aws kms get-key-rotation-status --key-id <key-id>
> ```
> or by reading `enable_key_rotation` in that module's current state. Happy to paste the `terraform plan` output for that module if that's easier than running the command yourself.
>
> ℹ️ Replied — thread left open. This is a question about existing infrastructure, not a defect in this diff, and isn't something to auto-close.

---

## Scenario: Quiet Skip (no classification needed)

### 9. CI status bot comment

**PR comment** (from `github-actions[bot]`):
> ✅ All checks passed: validate (2m 14s), security (1m 03s), terraform (3m 22s)

**Classification:** none needed — pure status notification with no diagnostic content (no failing check, no stack trace, no assertion). Not every bot comment is worth a classification pass.

**No fix applied. No reply posted. No thread mutation.**

This is different from a CI *failure* comment, which does carry a diagnostic and gets investigated before being classified — a changed caller can break an unchanged callee, so a stack trace or named failing check is never skipped quietly.

---

## Scenario: ALREADY_FIXED

### 10. Already fixed in a later commit

**PR comment** (from `@frank`):
> The `latest` image tag on line 9 needs to be pinned.

**Classification:** ALREADY_FIXED — the concern was valid when raised, but commit `a3f91b2` on this branch already pins the tag, and current-head evidence confirms it. This is not `NOT_APPLICABLE`: the finding's premise was true, it just got fixed by later work already on this head.

**No fix applied — already addressed.**

**Reply posted:**
> This was already addressed in commit `a3f91b2` — image tag is now pinned to `orders:1.4.2@sha256:...`.
>
> ✅ Already fixed — thread resolved.

---

## Scenario: OUT_OF_SCOPE (file not in this PR)

### 11. Comment on a file not in this PR

**PR comment** (from `@grace`):
> The `terraform/rds.tf` backup retention should be 35 days not 7.

**Classification:** OUT_OF_SCOPE — `terraform/rds.tf` may well need a longer retention window, but it was not modified in this PR, so remediation is outside this authorized change. This is not `NOT_APPLICABLE`: nothing here disproves the finding's premise, it's just not this PR's diff to fix.

**No fix applied.**

**Reply posted:**
> `terraform/rds.tf` is not changed in this PR — this comment belongs on the PR that last modified that file, or as a standalone issue. I have not opened one; say if you want that tracked separately.
>
> 📌 Out of scope for this PR — thread left open. A potentially valid concern outside the authorized change doesn't auto-close.

---

## --all Mode Output

When you run `/platform-skills:triage --all 42`, triage processes every unresolved thread captured in the snapshot and prints a summary table with classification, execution, and discussion state kept separate — resolution is not an unconditional outcome of processing a comment:

```
| Comment      | Author      | Classification  | Execution           | Discussion                              |
|---|---|---|---|---|
| #123456789   | @alice      | ACTIONABLE_FIX     | Published a1b2c3d   | Replied, resolved                       |
| #123456790   | @bob        | ACTIONABLE_FIX     | Published b2c3d4e   | Replied, resolved                       |
| #123456791   | @carol      | NEEDS_CLARIFICATION | N/A                 | Replied, open (not eligible for auto-close) |
| #123456792   | @dave       | OUT_OF_SCOPE       | N/A                  | Replied, open (not eligible for auto-close) |
| #123456793   | actions[bot]| (none — pure status, no diagnostic) | N/A | Skipped — no reply, no mutation |

5 comments processed. 2 fixes committed and published, threads resolved. 1 clarification reply posted, thread left open pending missing capacity data. 1 out-of-scope reply posted, thread left open for the reviewer to decide on a follow-up. 1 pure CI status message skipped with no reply or mutation.
```

---

## See Also

- [commands/triage.md](../../commands/triage.md) — the command router: invocation forms, phase order, hard gates, classification table, report format
- [references/triage.md](../../references/triage.md) — evidence rules, resolution eligibility, the three-layer state model, failure recovery, and the `triage_helper.py` contract flag by flag
- [references/pr-review.md](../../references/pr-review.md) — PR review reference with rollback matrix and SOC 2 mapping
- `/platform-skills:pr-review full <PR number>` — run a full pre-merge review before triaging comments

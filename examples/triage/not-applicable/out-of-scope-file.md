# Not Applicable: comment on a file not changed in this PR

## Comment

**Author:** `@grace` (human reviewer)
**PR:** Adds a new S3 bucket for audit logs

> The RDS backup retention in `terraform/rds.tf` should be 35 days not 7
> to meet SOC 2 A1.2. Can you fix that here too?

---

## Classification: NOT_APPLICABLE

**Reason:** `terraform/rds.tf` is not in the diff for this PR. The comment is valid as
a standalone finding but does not belong on this PR — it should be tracked as a
separate issue or raised on the PR that last modified `terraform/rds.tf`.

---

## How triage detects this

```bash
# Check if the referenced file is in the PR diff
gh pr diff <pr_number> -- terraform/rds.tf
# (empty output — file not changed in this PR)
```

---

## Fix: none

---

## Reply posted on thread

> `terraform/rds.tf` is not modified in this PR so I can't fix it here without
> introducing unrelated scope creep.
>
> Opening a dedicated issue to track the retention change:
> ```bash
> gh issue create \
>   --title "fix(rds): increase backup_retention_period to 35 days (SOC 2 A1.2)" \
>   --body "RDS instance in terraform/rds.tf has backup_retention_period=7. SOC 2 A1.2 requires 35 days. Raised from PR #XX review."
> ```
>
> ❌ Not applicable — thread resolved.

---

## Note on scope creep

Applying fixes to files outside the PR diff is risky:
- It changes the blast radius of the PR unexpectedly
- It may fail CI checks that only cover changed files
- It makes rollback harder (one PR now owns multiple concerns)

Triage never applies fixes to files not in the PR diff. It opens an issue instead.

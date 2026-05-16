# Informational: "Is KMS rotation enabled?"

## Comment

**Author:** `@eve` (security reviewer)
**PR:** Adds a new RDS instance that references an existing KMS key

> Does this KMS key have automatic rotation enabled?
> I can see the key ID in the diff but the rotation setting isn't visible here.

---

## Classification: INFORMATIONAL

**Reason:** The KMS key is managed in a separate Terraform module not modified by this PR.
The reviewer needs reassurance, not a code change.

---

## Fix: none

---

## Reply posted on thread

> The KMS key is managed in `terraform/shared/kms/main.tf` (not changed in this PR).
> It has `enable_key_rotation = true` set, which means AWS rotates the key material
> annually automatically.
>
> You can verify the live state with:
> ```bash
> aws kms get-key-rotation-status \
>   --key-id $(terraform output -raw kms_key_id) \
>   --region eu-central-1
> # Expected: {"KeyRotationEnabled": true}
> ```
>
> If you'd like the Checkov evidence for the audit trail:
> ```bash
> checkov -d terraform/shared/kms --check CKV_AWS_7 --compact
> ```
>
> ℹ️ Thread resolved — no code change needed.

---

## When a human would triage this manually

1. Find the KMS key in the codebase — `grep -r "enable_key_rotation" terraform/`
2. Confirm it's set to `true`
3. Provide the AWS CLI command to verify live state
4. Resolve — no code change needed in this PR

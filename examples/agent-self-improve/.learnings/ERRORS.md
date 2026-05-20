# Error Log

Mistakes made, wrong assumptions, and root causes.
Captured automatically via PostToolUse hook or logged manually.

Format: `ERR-YYYYMMDD-NNN`
Lifecycle: `pending → resolved → promoted`

---

### ERR-20260520-001
**Status**: example
**Context**: Applying a Terraform plan that replaced an RDS instance
**Content**: Assumed that changing `db_subnet_group_name` was a non-destructive update. It is a replacement trigger. The plan showed `forces replacement` but the flag was missed during review.
**Action**: Resolved — added a `lifecycle { prevent_destroy = true }` block. Promoted to `references/terraform.md`: "Always scan plan output for `forces replacement` before applying to stateful resources."

---

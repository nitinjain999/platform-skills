# Task: Assess a risky IAM change

A pull request changes the Terraform IAM policy in `iam/deploy-role.tf`. The diff is in `proposed.diff`.

A discovery pass produced this summary:

> The policy in `iam/deploy-role.tf` grants `s3:GetObject` and `s3:PutObject` on the artifacts bucket. Scoped to one bucket ARN. Looks least-privilege.

Decide whether to approve this change.

# Demo: Terraform IAM Risk

> Status: Stable

A Terraform IAM policy that gives an application AdministratorAccess in disguise. Platform-skills catches it before the plan is applied.

## What's wrong with bad.tf

| Finding | Severity | Risk |
|---|---|---|
| `Action: "*"` — full AWS access | Critical | Any compromised instance = full account takeover |
| `Resource: "*"` — all resources | Critical | No scope boundary on any service |
| No `Condition` on assume-role | High | Role can be assumed from any region |
| Single catch-all policy | Medium | Impossible to audit what the app actually needs |

## What changed in fixed.tf

- Actions scoped to exactly what the app does: `s3:GetObject`, `s3:ListBucket`, `s3:PutObject`, `s3:DeleteObject`, `secretsmanager:GetSecretValue`
- Resources scoped to named bucket and app-prefixed secrets — no wildcard
- Regional `Condition` on assume-role — blocks cross-region assume
- Separate policy statements with `Sid` labels — auditable in CloudTrail

## Blast radius of bad.tf

- Compromised EC2 instance → attacker has `iam:CreateUser`, `iam:AttachUserPolicy`, `ec2:RunInstances` → lateral movement across the account
- Misconfigured app → accidentally deletes S3 buckets, terminates instances, modifies security groups

## Validation

`bad.tf` and `fixed.tf` intentionally define the same resources so they cannot be validated together as one module. Copy `fixed.tf` to a clean directory to validate it:

```bash
mkdir /tmp/tf-demo && cp examples/demo/terraform-iam-risk/fixed.tf examples/demo/terraform-iam-risk/versions.tf /tmp/tf-demo/
cd /tmp/tf-demo
terraform init && terraform validate
terraform plan -var="app_name=myapp" -var="bucket_name=my-bucket" -var="aws_region=us-east-1"
```

## Try it yourself

```text
Use $platform-skills to review this Terraform IAM policy for least privilege.
Flag wildcard actions, wildcard resources, missing conditions, and safer alternatives.
```

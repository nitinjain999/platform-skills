Status: Stable

# AWS Examples

Production-ready IAM patterns for EKS workloads and GitHub Actions OIDC authentication — no static credentials.

## Examples

| Example | Type | Description |
|---------|------|-------------|
| [iam/irsa-dynamodb.json](iam/irsa-dynamodb.json) | IAM JSON | IRSA trust policy + DynamoDB scoped permissions |
| [iam/s3-least-privilege.json](iam/s3-least-privilege.json) | IAM JSON | Least-privilege S3 read policy |

## Quick Start

```bash
# Create the IAM policy from the JSON document
aws iam create-policy \
  --policy-name my-app-s3-read \
  --policy-document file://iam/s3-least-privilege.json

# Attach to an IRSA role
aws iam attach-role-policy \
  --role-name my-app-irsa-role \
  --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/my-app-s3-read
```

## Key Patterns

### IRSA — IAM Roles for Service Accounts

Pods on EKS authenticate to AWS using projected service account tokens — no access keys needed:

```hcl
# Trust policy pins to specific namespace + service account
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
```

```yaml
# Pod spec — EKS injects the token automatically
spec:
  serviceAccountName: my-app-sa  # Annotated with role ARN
```

### Least-privilege IAM

```hcl
# ✅ Scoped actions and resources
resource "aws_iam_policy" "app" {
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::my-bucket",
        "arn:aws:s3:::my-bucket/*"
      ]
    }]
  })
}
# ❌ Never: Action = "*" or Resource = "*"
```

### GitHub Actions OIDC (no static credentials)

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::123456789012:role/github-actions-terraform
      aws-region: eu-central-1
```

## Checklist

- [ ] No static IAM access keys — IRSA for EKS pods, OIDC for GitHub Actions
- [ ] IAM policies use specific actions and scoped ARNs (no wildcards)
- [ ] IRSA trust pins to specific namespace and service account
- [ ] GitHub Actions OIDC trust pins to specific repo and ref
- [ ] All resources tagged via provider `default_tags`

## See Also

- [references/aws.md](../../references/aws.md) — account model, EKS, IAM, tagging, cost management
- [references/compliance.md](../../references/compliance.md) — SOC 2 CC6.1/CC6.2 IAM controls
- `/platform-skills:review` — production-readiness review of Terraform IAM resources

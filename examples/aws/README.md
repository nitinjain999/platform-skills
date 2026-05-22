Status: Stable

# AWS Examples

Production-ready AWS platform patterns — CloudFront, WAF, Lambda@Edge, Firewall Manager, and IAM.

## Examples

| Directory | Description |
|---|---|
| [cloudfront/](cloudfront/) | CloudFront distribution with S3 + ALB origins, OAC, security headers, CloudFront Functions, Lambda@Edge |
| [waf/](waf/) | WAF WebACL (CLOUDFRONT scope, us-east-1) with managed rules, rate limiting, geo blocking, logging |
| [firewall-manager/](firewall-manager/) | Firewall Manager WAF policy for multi-account enforcement via AWS Organizations |
| [iam/](iam/) | IAM least-privilege patterns: IRSA, OIDC federation, no static credentials |

## Quick Start

### Single-account: CloudFront + WAF

```hcl
# Deploy WAF first (CLOUDFRONT scope requires us-east-1)
module "waf" {
  source = "./waf"
  name   = "my-app"
  providers = { aws.us_east_1 = aws.us_east_1 }
}

# Deploy CloudFront, pass WAF ARN in
module "cloudfront" {
  source          = "./cloudfront"
  name            = "my-app"
  waf_web_acl_arn = module.waf.web_acl_arn
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
```

### Multi-account: Firewall Manager

```hcl
# Run from the FMS administrator (security) account
module "fms" {
  source              = "./firewall-manager"
  security_account_id = "123456789012"
  production_ou_id    = "ou-xxxx-yyyyyyyy"
  remediation_enabled = false  # audit mode first
}
```

### IAM (existing patterns)

```bash
aws iam create-policy \
  --policy-name my-app-s3-read \
  --policy-document file://iam/s3-least-privilege.json
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

## Key patterns

- **WAF before CloudFront** — deploy WAF module first, pass `web_acl_arn` output to CloudFront `waf_web_acl_arn`
- **Provider aliases** — both CloudFront and WAF modules require `aws.us_east_1` alias
- **Lambda@Edge** — set `enable_lambda_edge = true`; deployed to us-east-1 automatically, uses numbered version ARN
- **CloudFront Functions** — set `enable_cloudfront_function = true`; ~6× cheaper than Lambda@Edge for URL rewrites
- **FMS audit mode** — set `remediation_enabled = false` to review compliance dashboard before enforcing

## See Also

- [references/aws-cloudfront.md](../../references/aws-cloudfront.md) — CloudFront deep-dive: OAC, cache policies, Lambda@Edge, multi-account
- [references/aws-waf.md](../../references/aws-waf.md) — WAF deep-dive: managed rules, rate limiting, FMS, Shield Advanced
- [references/aws.md](../../references/aws.md) — account model, EKS, IAM, tagging
- `/platform-skills:aws` — structured guidance for CloudFront, WAF, Lambda@Edge, and multi-account patterns

# AWS Reference

## Contents

- Foundation scope
- Account and identity model
- Tagging resources
- IAM patterns
- EKS platform patterns
- Terraform and CI guidance

## Foundation scope

For AWS platform work, start from:

- Organization and account boundaries
- IAM and federation model
- Networking baseline
- Central logging, audit, and security services

Prefer multi-account design over a single shared account for serious environments.

## Account and identity model

- Separate production and non-production accounts.
- Use IAM Identity Center or equivalent SSO for humans.
- Use GitHub Actions OIDC for CI federation into AWS roles.
- Use IRSA or workload identity equivalents for pods that need AWS APIs.

## Tagging resources

Tags are the foundation of cost allocation, ownership tracking, and policy enforcement in AWS. The specific tag keys an organization uses are a local decision — the important thing is that the strategy is consistent, enforced, and covers all resource types.

### Apply a baseline at the provider level

Use `default_tags` in the AWS Terraform provider so every resource inherits the baseline automatically. Individual resources extend it with additional tags — they do not replace the defaults.

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.default_tags
  }
}
```

Pass the baseline tag map in as a variable so modules stay opinionated about the mechanism but not the keys:

```hcl
variable "default_tags" {
  description = "Baseline tags applied to all resources via provider default_tags."
  type        = map(string)
}
```

Resources that need extra tags merge on top:

```hcl
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn

  tags = {
    component = "eks-control-plane"
  }
}
```

The `component` tag is additive. The baseline from `default_tags` is already there.

### Enforce tags at the organization level

Convention alone does not prevent untagged resources. Use AWS Organizations tag policies or SCPs to require tags before resources can be created.

Tag policies (part of AWS Organizations) let you define which keys are required and what values are acceptable, enforced per resource type:

```json
{
  "tags": {
    "your-required-key": {
      "tag_key": {
        "@@assign": "your-required-key"
      },
      "enforced_for": {
        "@@assign": [
          "ec2:instance",
          "ec2:volume",
          "rds:db",
          "eks:cluster",
          "s3:bucket"
        ]
      }
    }
  }
}
```

This runs outside Terraform and covers resources created via console, CLI, or any other method.

### Propagation gaps to be aware of

Not all AWS services pass tags through automatically:

- **Auto Scaling Groups → EC2 instances**: Tags do not propagate unless `propagate_at_launch = true` is set on each tag:

```hcl
resource "aws_autoscaling_group" "this" {
  tag {
    key                 = "your-tag-key"
    value               = var.tag_value
    propagate_at_launch = true
  }
}
```

- **EKS managed node groups → EC2 instances**: Tags on the node group do propagate, but tags added after initial creation may not apply to already-running nodes — a rolling update is required.
- **EBS volumes from snapshots**: Volumes do not inherit snapshot tags. Tag them explicitly at creation time.
- **Lambda → CloudWatch log groups**: Tags on the function do not propagate to its log group. Tag the log group separately or apply a resource policy.

### Detect untagged resources

Use the AWS Config managed rule `required-tags` to continuously flag non-compliant resources:

```hcl
resource "aws_config_config_rule" "required_tags" {
  name = "required-tags"

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  input_parameters = jsonencode({
    tag1Key = "your-first-required-key"
    tag2Key = "your-second-required-key"
  })
}
```

Pair this with an SNS notification or a Slack alert so untagged resources are visible immediately rather than discovered at billing time.

### Cost allocation tags

Tags must be activated in the AWS Billing console before they appear in Cost Explorer. This is a manual step per account — Terraform cannot do it.

After introducing any new required tag key:
1. Go to **Billing → Cost allocation tags**.
2. Find the key under **User-defined cost allocation tags**.
3. Activate it.
4. Allow up to 24 hours for the tag to show in cost reports.

## IAM patterns

- Never use wildcard actions (`*`) or wildcard resources (`*`) in production policies.
- Scope every policy to the minimum actions and the exact ARN or ARN prefix required.
- Use IRSA (IAM Roles for Service Accounts) for any pod-level AWS access.
- Use OIDC federation for CI/CD — never store long-lived IAM access keys in secrets.

```hcl
# ❌ Overly permissive
{
  "Effect": "Allow",
  "Action": "s3:*",
  "Resource": "*"
}

# ✅ Least privilege
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject"
  ],
  "Resource": [
    "arn:aws:s3:::my-bucket",
    "arn:aws:s3:::my-bucket/*"
  ]
}
```

## EKS platform patterns

- Provision cluster foundations, node groups, networking, and IAM with Terraform.
- Install cluster add-ons such as ingress, cert-manager, external-dns, and observability with Flux or Argo CD.
- Keep shared controllers in dedicated namespaces with explicit ownership and upgrade paths.
- Tag the EKS cluster with `kubernetes.io/cluster/<cluster-name>: owned` for auto-discovery by load balancer and auto-scaler controllers.

## Terraform and CI guidance

- Standardize provider configuration and `default_tags` across all modules.
- Limit role permissions used by CI to the environment and action required.
- Review `plan` output and security checks before apply.
- Surface account, region, and workspace context clearly in workflows to avoid applying to the wrong target.
- Fail CI if any planned resource is missing required tags — validate against `terraform plan -out=plan.json` using OPA, Conftest, or a custom script.

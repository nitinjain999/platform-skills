# terraform-soc2-iam.tf
#
# SOC 2 IAM patterns: least-privilege role (CC6.1), OIDC for CI/CD (CC6.2),
# and SCP enforcing MFA and denying privilege escalation (CC6.1 / CC6.2).
#
# Prerequisites:
#   - aws provider >= 5.0
#   - AWS Organizations if using SCP resources
#
# Validation:
#   checkov -d . --config-file ../checkov-config.yaml
#   aws iam simulate-principal-policy \
#     --policy-source-arn <role-arn> \
#     --action-names s3:GetObject \
#     --resource-arns arn:aws:s3:::my-bucket/object

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name the application reads from"
  type        = string
}

variable "oidc_provider" {
  description = "EKS OIDC provider hostname (without https://)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the application service account"
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes service account name"
  type        = string
}

variable "gh_org_repo" {
  description = "GitHub org/repo for OIDC trust (e.g. my-org/platform-infra)"
  type        = string
}

locals {
  common_tags = {
    ManagedBy  = "terraform"
    Compliance = "soc2"
  }
}

# ─── CC6.1: Application role — least privilege ────────────────────────────────

resource "aws_iam_role" "app" {
  name        = "app-role"
  description = "Application role — S3 read-only for ${var.bucket_name} (SOC 2 CC6.1)"

  # IRSA trust policy — no static keys, identity bound to specific service account
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${var.account_id}:oidc-provider/${var.oidc_provider}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.common_tags
}

# Managed policy: scoped actions and explicit resource ARN
resource "aws_iam_policy" "app_s3_read" {
  name        = "app-s3-read"
  description = "Read-only access to ${var.bucket_name} (SOC 2 CC6.1)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Read"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}/*"
      },
      {
        Sid    = "S3List"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.bucket_name}"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "app_s3_read" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app_s3_read.arn
}

# ─── CC6.2: GitHub Actions OIDC — no stored credentials in CI ─────────────────

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub Actions OIDC thumbprints — update when GitHub rotates their cert
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = local.common_tags
}

resource "aws_iam_role" "github_actions_plan" {
  name        = "github-actions-plan"
  description = "Read-only role for Terraform plan in CI (SOC 2 CC6.2)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Allow all branches for plan (read-only)
          "token.actions.githubusercontent.com:sub" = "repo:${var.gh_org_repo}:*"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role" "github_actions_apply" {
  name        = "github-actions-apply"
  description = "Deploy role for Terraform apply in CI — main branch only (SOC 2 CC6.2, CC8.1)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # Apply only from main branch — enforces CC8.1 (change management)
          "token.actions.githubusercontent.com:sub" = "repo:${var.gh_org_repo}:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = local.common_tags
}

# ─── CC6.1 / CC6.2: SCPs (requires AWS Organizations) ────────────────────────

resource "aws_organizations_policy" "require_mfa" {
  name        = "require-mfa-console"
  type        = "SERVICE_CONTROL_POLICY"
  description = "Deny console actions unless MFA is present (SOC 2 CC6.2)"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyWithoutMFA"
      Effect = "Deny"
      NotAction = [
        "iam:CreateVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:GetUser",
        "iam:ListMFADevices",
        "iam:ListVirtualMFADevices",
        "sts:GetSessionToken"
      ]
      Resource = "*"
      Condition = {
        BoolIfExists = {
          "aws:MultiFactorAuthPresent" = "false"
        }
      }
    }]
  })
}

resource "aws_organizations_policy" "deny_privilege_escalation" {
  name        = "deny-iam-privilege-escalation"
  type        = "SERVICE_CONTROL_POLICY"
  description = "Prevent IAM privilege escalation by non-platform roles (SOC 2 CC6.1)"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyPrivilegeEscalation"
      Effect = "Deny"
      Action = [
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy",
        "iam:PutUserPolicy",
        "iam:CreatePolicyVersion",
        "iam:SetDefaultPolicyVersion",
        "iam:PassRole"
      ]
      Resource = "*"
      Condition = {
        ArnNotLike = {
          "aws:PrincipalARN" = [
            "arn:aws:iam::*:role/platform-admin",
            "arn:aws:iam::*:role/OrganizationAccountAccessRole"
          ]
        }
      }
    }]
  })
}

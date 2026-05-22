terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# ─── Providers ────────────────────────────────────────────────────────────────
#
# Run this module from the FMS administrator account.
# FMS CloudFront policies must be created in us-east-1.

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = var.default_tags
  }
}

provider "aws" {
  region = "us-east-1" # FMS admin account designation is global but uses us-east-1 API

  default_tags {
    tags = var.default_tags
  }
}

# ─── Variables ────────────────────────────────────────────────────────────────

variable "security_account_id" {
  type        = string
  description = "AWS account ID of the designated FMS administrator (security account)."
}

variable "production_ou_id" {
  type        = string
  description = "AWS Organizations OU ID to enforce WAF policy on (e.g. ou-xxxx-yyyyyyyy)."
}

variable "excluded_account_ids" {
  type        = list(string)
  description = "Account IDs to exclude from the FMS WAF policy (e.g. sandbox accounts)."
  default     = []
}

variable "remediation_enabled" {
  type        = bool
  description = "Auto-create and update WebACLs on non-compliant resources. Set false for audit mode."
  default     = false # start in audit mode — enable after reviewing compliance dashboard
}

variable "default_tags" {
  type        = map(string)
  description = "Tags applied to all resources via provider default_tags."
  default     = {}
}

# ─── FMS Administrator Account ────────────────────────────────────────────────
#
# Designates the security account as the FMS administrator.
# Prerequisites:
#   - AWS Organizations enabled with all features active
#   - This Terraform runs in the management account or an existing FMS admin
#   - Member accounts must be in the same Organization

resource "aws_fms_admin_account" "this" {
  account_id = var.security_account_id
}

# ─── FMS WAF Policy — CloudFront Distributions ────────────────────────────────
#
# Enforces a baseline WAF WebACL on all CloudFront distributions in the
# production OU. New accounts joining the OU are automatically included.
#
# Rule group ownership:
#   FIRST (priority 5–11)  — security team locks via FMS preProcessRuleGroups
#   MIDDLE (priority 20+)  — app teams may add local rules
#   LAST                   — postProcessRuleGroups (empty here, extend as needed)

resource "aws_fms_policy" "cloudfront_waf" {
  provider = aws.us_east_1

  name                  = "cloudfront-waf-baseline"
  description           = "Baseline WAF policy for all CloudFront distributions in production OU"
  resource_type         = "AWS::CloudFront::Distribution"
  remediation_enabled   = var.remediation_enabled
  exclude_resource_tags = false

  # Target the production OU — includes all current and future member accounts
  include_map {
    orgunit = [var.production_ou_id]
  }

  # Exclude specific accounts (sandbox, dev tooling)
  dynamic "exclude_map" {
    for_each = length(var.excluded_account_ids) > 0 ? [1] : []
    content {
      account = var.excluded_account_ids
    }
  }

  security_service_policy_data {
    type = "WAFV2"

    managed_service_data = jsonencode({
      type          = "WAFV2"
      defaultAction = { type = "ALLOW" }

      # FIRST rule groups — security team owns, cannot be removed by app teams
      preProcessRuleGroups = [
        {
          ruleGroupType = "ManagedRuleGroup"
          managedRuleGroupIdentifier = {
            vendorName           = "AWS"
            managedRuleGroupName = "AWSManagedRulesAmazonIpReputationList"
          }
          overrideAction = { type = "NONE" }
          priority       = 5
          visibilityConfig = {
            sampledRequestsEnabled   = true
            cloudWatchMetricsEnabled = true
            metricName               = "FMS-IpReputationList"
          }
        },
        {
          ruleGroupType = "ManagedRuleGroup"
          managedRuleGroupIdentifier = {
            vendorName           = "AWS"
            managedRuleGroupName = "AWSManagedRulesCommonRuleSet"
          }
          overrideAction = { type = "NONE" }
          priority       = 10
          visibilityConfig = {
            sampledRequestsEnabled   = true
            cloudWatchMetricsEnabled = true
            metricName               = "FMS-CommonRuleSet"
          }
        },
        {
          ruleGroupType = "ManagedRuleGroup"
          managedRuleGroupIdentifier = {
            vendorName           = "AWS"
            managedRuleGroupName = "AWSManagedRulesKnownBadInputsRuleGroup"
          }
          overrideAction = { type = "NONE" }
          priority       = 11
          visibilityConfig = {
            sampledRequestsEnabled   = true
            cloudWatchMetricsEnabled = true
            metricName               = "FMS-KnownBadInputs"
          }
        }
      ]

      # App teams may add rules in the MIDDLE (priority 20–79)
      # postProcessRuleGroups lock the LAST position (priority 80+)
      postProcessRuleGroups = []

      # Allow app teams to add their own rules to WebACLs — do not override local rules
      overrideCustomerWebACLAssociation = false

      # Central logging — route all member account WAF logs to security account
      # Requires a Firehose in the security account with cross-account permissions
      # loggingConfiguration = {
      #   logDestinationConfigs = [aws_kinesis_firehose_delivery_stream.waf_central.arn]
      #   redactedFields = [
      #     { type = "SINGLE_HEADER", name = "authorization" },
      #     { type = "SINGLE_HEADER", name = "cookie" }
      #   ]
      # }
    })
  }

  depends_on = [aws_fms_admin_account.this]
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "fms_policy_id" {
  description = "ID of the Firewall Manager WAF policy."
  value       = aws_fms_policy.cloudfront_waf.id
}

output "fms_policy_arn" {
  description = "ARN of the Firewall Manager WAF policy."
  value       = aws_fms_policy.cloudfront_waf.arn
}

output "remediation_enabled" {
  description = "Whether auto-remediation is active. False = audit mode."
  value       = var.remediation_enabled
}

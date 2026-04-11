# terraform-soc2-detection.tf
#
# SOC 2 CC7.1 — detection and monitoring: GuardDuty (threat detection),
# CloudWatch metric filters + alarms for CIS Benchmark 3.x controls,
# and Security Hub with AWS Foundational and CIS standards.
#
# Prerequisites:
#   - aws provider >= 5.0
#   - CloudTrail must be enabled and shipping to a CloudWatch Logs group
#     (see terraform-soc2-logging.tf)
#   - aws_sns_topic.security_alerts must exist (see terraform-soc2-incident-response.tf)
#
# Validation:
#   checkov -d . --config-file ../checkov-config.yaml
#   aws guardduty list-detectors
#   aws cloudwatch describe-alarms --state-value ALARM
#   aws securityhub get-findings --filters '{"ComplianceStatus":[{"Value":"FAILED","Comparison":"EQUALS"}]}'

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "cloudtrail_log_group_name" {
  description = "CloudWatch Logs group name where CloudTrail ships events"
  type        = string
}

variable "security_alert_topic_arn" {
  description = "SNS topic ARN for security alerts"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

locals {
  common_tags = {
    ManagedBy  = "terraform"
    Compliance = "soc2"
  }

  # CIS Benchmark 3.x — metric filter patterns and alarm descriptions
  # Each entry: filter pattern → CloudWatch metric → alarm description
  cis_alarms = {
    "unauthorized-api-calls" = {
      pattern     = "{ ($.errorCode = \"*UnauthorizedAccess*\") || ($.errorCode = \"AccessDenied*\") }"
      description = "CIS 3.1 — Unauthorized API calls detected"
    }
    "console-signin-without-mfa" = {
      pattern     = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") }"
      description = "CIS 3.2 — AWS Console sign-in without MFA"
    }
    "root-account-usage" = {
      pattern     = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
      description = "CIS 3.3 — Root account usage"
    }
    "iam-policy-changes" = {
      pattern     = "{ ($.eventName = DeleteGroupPolicy) || ($.eventName = DeleteRolePolicy) || ($.eventName = DeleteUserPolicy) || ($.eventName = PutGroupPolicy) || ($.eventName = PutRolePolicy) || ($.eventName = PutUserPolicy) || ($.eventName = CreatePolicy) || ($.eventName = DeletePolicy) || ($.eventName = CreatePolicyVersion) || ($.eventName = DeletePolicyVersion) || ($.eventName = SetDefaultPolicyVersion) }"
      description = "CIS 3.4 — IAM policy changes"
    }
    "cloudtrail-config-changes" = {
      pattern     = "{ ($.eventName = CreateTrail) || ($.eventName = UpdateTrail) || ($.eventName = DeleteTrail) || ($.eventName = StartLogging) || ($.eventName = StopLogging) }"
      description = "CIS 3.5 — CloudTrail configuration changes"
    }
    "console-auth-failures" = {
      pattern     = "{ ($.eventName = ConsoleLogin) && ($.errorMessage = \"Failed authentication\") }"
      description = "CIS 3.6 — Console authentication failures (brute force indicator)"
    }
    "kms-key-deletion" = {
      pattern     = "{ ($.eventSource = kms.amazonaws.com) && (($.eventName = DisableKey) || ($.eventName = ScheduleKeyDeletion)) }"
      description = "CIS 3.7 — KMS key deletion or disabling"
    }
    "s3-bucket-policy-changes" = {
      pattern     = "{ ($.eventSource = s3.amazonaws.com) && (($.eventName = PutBucketAcl) || ($.eventName = PutBucketPolicy) || ($.eventName = PutBucketCors) || ($.eventName = DeleteBucketPolicy)) }"
      description = "CIS 3.8 — S3 bucket policy changes"
    }
    "config-service-changes" = {
      pattern     = "{ ($.eventSource = config.amazonaws.com) && (($.eventName = StopConfigurationRecorder) || ($.eventName = DeleteDeliveryChannel) || ($.eventName = PutDeliveryChannel) || ($.eventName = PutConfigurationRecorder)) }"
      description = "CIS 3.9 — AWS Config changes"
    }
    "security-group-changes" = {
      pattern     = "{ ($.eventName = AuthorizeSecurityGroupIngress) || ($.eventName = AuthorizeSecurityGroupEgress) || ($.eventName = RevokeSecurityGroupIngress) || ($.eventName = RevokeSecurityGroupEgress) || ($.eventName = CreateSecurityGroup) || ($.eventName = DeleteSecurityGroup) }"
      description = "CIS 3.10 — Security group changes"
    }
    "nacl-changes" = {
      pattern     = "{ ($.eventName = CreateNetworkAcl) || ($.eventName = CreateNetworkAclEntry) || ($.eventName = DeleteNetworkAcl) || ($.eventName = DeleteNetworkAclEntry) || ($.eventName = ReplaceNetworkAclEntry) || ($.eventName = ReplaceNetworkAclAssociation) }"
      description = "CIS 3.11 — Network ACL changes"
    }
    "network-gateway-changes" = {
      pattern     = "{ ($.eventName = CreateCustomerGateway) || ($.eventName = DeleteCustomerGateway) || ($.eventName = AttachInternetGateway) || ($.eventName = CreateInternetGateway) || ($.eventName = DeleteInternetGateway) || ($.eventName = DetachInternetGateway) }"
      description = "CIS 3.12 — Network gateway changes"
    }
    "route-table-changes" = {
      pattern     = "{ ($.eventName = CreateRoute) || ($.eventName = CreateRouteTable) || ($.eventName = ReplaceRoute) || ($.eventName = ReplaceRouteTableAssociation) || ($.eventName = DeleteRouteTable) || ($.eventName = DeleteRoute) || ($.eventName = DisassociateRouteTable) }"
      description = "CIS 3.13 — Route table changes"
    }
    "vpc-changes" = {
      pattern     = "{ ($.eventName = CreateVpc) || ($.eventName = DeleteVpc) || ($.eventName = ModifyVpcAttribute) || ($.eventName = AcceptVpcPeeringConnection) || ($.eventName = CreateVpcPeeringConnection) || ($.eventName = DeleteVpcPeeringConnection) || ($.eventName = RejectVpcPeeringConnection) }"
      description = "CIS 3.14 — VPC changes"
    }
  }
}

# ─── GuardDuty ────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    # Detect S3 data access anomalies (exfiltration, unusual access patterns)
    s3_logs {
      enable = true
    }

    # Detect suspicious EKS API server calls
    kubernetes {
      audit_logs {
        enable = true
      }
    }

    # Scan EBS volumes of EC2 instances with GuardDuty findings for malware
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = local.common_tags
}

# Route HIGH and CRITICAL GuardDuty findings to SNS (CC7.3)
resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "guardduty-high-severity"
  description = "GuardDuty findings severity >= 7 (HIGH/CRITICAL) → SNS (SOC 2 CC7.1)"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_high.name
  target_id = "GuardDutyHighToSNS"
  arn       = var.security_alert_topic_arn
}

# ─── CloudWatch metric filters + alarms (CIS Benchmark 3.x) ──────────────────

resource "aws_cloudwatch_log_metric_filter" "cis" {
  for_each = local.cis_alarms

  name           = each.key
  log_group_name = var.cloudtrail_log_group_name
  pattern        = each.value.pattern

  metric_transformation {
    name      = each.key
    namespace = "SOC2/CISBenchmark"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "cis" {
  for_each = local.cis_alarms

  alarm_name          = "cis-${each.key}"
  alarm_description   = each.value.description
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = each.key
  namespace           = "SOC2/CISBenchmark"
  period              = 300   # 5-minute evaluation window
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.security_alert_topic_arn]
  ok_actions    = []

  tags = local.common_tags
}

# ─── Security Hub ─────────────────────────────────────────────────────────────

resource "aws_securityhub_account" "main" {
  # Disable default standards — enable only what maps to SOC 2 scope
  enable_default_standards = false
  auto_enable_controls     = true
}

# AWS Foundational Security Best Practices — broad AWS-native controls
resource "aws_securityhub_standards_subscription" "aws_foundational" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

# CIS AWS Foundations Benchmark v1.4.0 — maps directly to CC6.x and CC7.x
resource "aws_securityhub_standards_subscription" "cis" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.region}::standards/cis-aws-foundations-benchmark/v/1.4.0"
}

# Route CRITICAL Security Hub findings to SNS
resource "aws_cloudwatch_event_rule" "securityhub_critical" {
  name        = "securityhub-critical-findings"
  description = "Security Hub CRITICAL findings → SNS (SOC 2 CC7.1)"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["CRITICAL"]
        }
        Compliance = {
          Status = ["FAILED"]
        }
        RecordState = ["ACTIVE"]
      }
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "securityhub_sns" {
  rule      = aws_cloudwatch_event_rule.securityhub_critical.name
  target_id = "SecurityHubCriticalToSNS"
  arn       = var.security_alert_topic_arn
}

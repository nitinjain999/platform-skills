# examples/compliance/incident-response/main.tf
#
# SOC 2 CC7.3 — incident response: encrypted SNS topic for security alerts,
# subscriptions (email + PagerDuty), GuardDuty and Config delivery channel
# wired to the topic, and an EventBridge dead-letter queue for missed events.
#
# Prerequisites:
#   - aws provider >= 5.0
#   - KMS key for SNS encryption
#   - guardduty_detector and config_delivery_channel are in separate modules
#     (../detection and ../logging) and consume
#     the SNS topic ARN output from this file
#
# Validation:
#   checkov -d . --config-file ../checkov-config.yaml
#   aws sns list-subscriptions-by-topic --topic-arn <arn>
#   aws events list-rules --query 'Rules[*].{Name:Name,State:State}'

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "security_alert_email" {
  description = "Email address for security alert notifications (creates a confirmed subscription)"
  type        = string
}

variable "pagerduty_integration_url" {
  description = "PagerDuty Events API v2 HTTPS endpoint for SNS integration"
  type        = string
  sensitive   = true
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
}

# ─── KMS key for SNS encryption (CC7.3 + CC6.7) ──────────────────────────────

resource "aws_kms_key" "sns" {
  description             = "SNS security alerts encryption key (SOC 2 CC7.3)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  # Allow SNS, EventBridge, and Config to use this key
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM key management"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow SNS to use this key"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = "*"
      },
      {
        Sid    = "Allow EventBridge to use this key"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = "*"
      },
      {
        Sid    = "Allow Config to use this key"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, { Service = "sns" })
}

resource "aws_kms_alias" "sns" {
  name          = "alias/sns-security-alerts"
  target_key_id = aws_kms_key.sns.key_id
}

data "aws_caller_identity" "current" {}

# ─── SNS topic — security alerts ──────────────────────────────────────────────

resource "aws_sns_topic" "security_alerts" {
  name              = "security-alerts"
  display_name      = "Platform Security Alerts"
  kms_master_key_id = aws_kms_key.sns.arn # CC7.3: encrypt topic messages

  tags = local.common_tags
}

# Topic policy: allow GuardDuty, Security Hub, Config, and EventBridge to publish
resource "aws_sns_topic_policy" "security_alerts" {
  arn = aws_sns_topic.security_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowOwnerAccount"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "sns:*"
        Resource = aws_sns_topic.security_alerts.arn
      },
      {
        Sid    = "AllowAWSServices"
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com",
            "config.amazonaws.com",
            "guardduty.amazonaws.com",
            "securityhub.amazonaws.com",
            "inspector2.amazonaws.com"
          ]
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.security_alerts.arn
      }
    ]
  })
}

# ─── Subscriptions ────────────────────────────────────────────────────────────

# Email — creates an immutable audit trail visible to external auditors
# Note: requires manual confirmation after apply
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}

# PagerDuty — routes alerts to on-call rotation
resource "aws_sns_topic_subscription" "pagerduty" {
  topic_arn              = aws_sns_topic.security_alerts.arn
  protocol               = "https"
  endpoint               = var.pagerduty_integration_url
  endpoint_auto_confirms = true
}

# ─── Dead-letter queue — catch missed EventBridge deliveries ──────────────────

resource "aws_sqs_queue" "security_alerts_dlq" {
  name                      = "security-alerts-dlq"
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id         = aws_kms_key.sns.arn

  tags = local.common_tags
}

# ─── Outputs — consumed by detection and logging modules ──────────────────────

output "security_alerts_topic_arn" {
  description = "SNS topic ARN for security alerts — pass to detection and logging modules"
  value       = aws_sns_topic.security_alerts.arn
}

output "security_alerts_kms_key_arn" {
  description = "KMS key ARN used to encrypt the security alerts SNS topic"
  value       = aws_kms_key.sns.arn
}

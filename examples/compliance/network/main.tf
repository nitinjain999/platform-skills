# terraform-soc2-network.tf
#
# SOC 2 network security controls: WAF (CC6.6), VPC flow logs (CC6.6 / CC7.2),
# and security group hardening.
#
# Prerequisites:
#   - aws provider >= 5.0
#   - aws_lb.main and aws_vpc.main must exist
#
# Validation:
#   checkov -d . --config-file ../checkov-config.yaml
#   aws wafv2 list-web-acls --scope REGIONAL
#   aws ec2 describe-flow-logs --filter "Name=resource-id,Values=<vpc-id>"

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "vpc_id" {
  description = "VPC ID to protect"
  type        = string
}

variable "alb_arn" {
  description = "ARN of the public-facing Application Load Balancer to associate WAF with"
  type        = string
}

variable "flow_log_bucket_arn" {
  description = "S3 bucket ARN for VPC flow log delivery"
  type        = string
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach application ports (e.g. VPN CIDR or trusted ranges)"
  type        = list(string)
}

locals {
  common_tags = {
    ManagedBy  = "terraform"
    Compliance = "soc2"
  }
}

# ─── WAF Web ACL ──────────────────────────────────────────────────────────────

resource "aws_wafv2_web_acl" "main" {
  name        = "production-waf"
  scope       = "REGIONAL"   # Use "CLOUDFRONT" for CloudFront distributions
  description = "SOC 2 CC6.6 — application-layer network protection"

  default_action {
    allow {}
  }

  # Rate limiting — block IPs sending more than 1000 requests per 5 minutes
  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  # AWS managed rule: common web exploits (SQLi, XSS, path traversal)
  rule {
    name     = "aws-managed-common"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedCommon"
      sampled_requests_enabled   = true
    }
  }

  # AWS managed rule: known bad inputs (Log4j, Spring4Shell, etc.)
  rule {
    name     = "aws-managed-known-bad-inputs"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedKnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "ProductionWAF"
    sampled_requests_enabled   = true
  }

  tags = local.common_tags
}

# Associate WAF with ALB — all traffic passes through WAF before reaching the app
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# WAF logging — required for CC7.2 (audit logging) and CKV2_AWS_31
resource "aws_cloudwatch_log_group" "waf" {
  # WAF log group name must start with "aws-waf-logs-"
  name              = "aws-waf-logs-production"
  retention_in_days = 90

  tags = local.common_tags
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.main.arn

  # Redact authorization headers from logs (do not store credentials)
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
}

# ─── VPC Flow Logs ────────────────────────────────────────────────────────────

resource "aws_flow_log" "main" {
  vpc_id               = var.vpc_id
  traffic_type         = "ALL"   # Log ACCEPT and REJECT — auditors need both
  log_destination_type = "s3"
  log_destination      = "${var.flow_log_bucket_arn}/vpc-flow-logs/"

  # Extended format includes action and log-status for richer analysis
  log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status}"

  tags = merge(local.common_tags, { Name = "vpc-flow-log-${var.vpc_id}" })
}

# ─── Security Group hardening ─────────────────────────────────────────────────

# Application security group — only allow traffic from ALB, not from the internet
resource "aws_security_group" "app" {
  name        = "app-sg"
  description = "Application tier — ingress from ALB only (SOC 2 CC6.6)"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "app-sg" })
}

resource "aws_security_group_rule" "app_ingress_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id   # ALB SG only — not 0.0.0.0/0
  security_group_id        = aws_security_group.app.id
  description              = "App port from ALB only"
}

resource "aws_security_group_rule" "app_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app.id
  description       = "Allow all egress"
}

# ALB security group — 443 open to internet
resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "ALB — HTTPS from internet only (SOC 2 CC6.6)"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "alb-sg" })
}

resource "aws_security_group_rule" "alb_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
}

resource "aws_security_group_rule" "alb_egress" {
  type                     = "egress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.alb.id
  description              = "Forward to app tier"
}

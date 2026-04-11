# examples/compliance/logging/main.tf
#
# SOC 2 audit logging foundation: CloudTrail (CC7.2), AWS Config (CC7.1),
# and VPC flow logs (CC6.6 / CC7.2).
#
# Prerequisites:
#   - aws provider >= 5.0
#   - KMS key for CloudTrail encryption (var.cloudtrail_kms_key_arn)
#   - S3 bucket for log storage (created below)
#
# Validation:
#   checkov -d . --config-file ../checkov-config.yaml
#   aws cloudtrail get-trail-status --name compliance-trail

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "cloudtrail_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt CloudTrail logs"
  type        = string
}

variable "account_id" {
  description = "AWS account ID (used in bucket policies)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_id" {
  description = "VPC ID to enable flow logs on"
  type        = string
}

locals {
  common_tags = {
    ManagedBy  = "terraform"
    Compliance = "soc2"
  }
}

# ─── S3: CloudTrail log bucket ────────────────────────────────────────────────

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket              = "cloudtrail-logs-${var.account_id}-${var.region}"
  force_destroy       = false # Protect audit logs from accidental deletion
  object_lock_enabled = true  # Required for object lock configuration below

  tags = merge(local.common_tags, { Name = "cloudtrail-logs" })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.cloudtrail_kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket                  = aws_s3_bucket.cloudtrail_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Object lock: COMPLIANCE mode prevents deletion for 1 year (PCI Req 10.7, SOC 2 CC7.2)
resource "aws_s3_bucket_object_lock_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 365
    }
  }
}

# Lifecycle: move to cheaper storage after 90 days, delete after 7 years
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    id     = "compliance-retention"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    expiration {
      days = 2555 # 7 years
    }
  }
}

# Bucket policy: allow CloudTrail to write, deny all other puts
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${var.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.cloudtrail_logs.arn,
          "${aws_s3_bucket.cloudtrail_logs.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ─── CloudTrail ───────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/compliance"
  retention_in_days = 90 # Short CloudWatch retention; long-term in S3
  kms_key_id        = var.cloudtrail_kms_key_arn

  tags = local.common_tags
}

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "cloudtrail-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "cloudtrail.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name = "cloudtrail-cloudwatch-policy"
  role = aws_iam_role.cloudtrail_cloudwatch.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "compliance" {
  name                          = "compliance-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true # Required: covers all regions (CC7.2)
  enable_log_file_validation    = true # Tamper detection (CC7.2)
  kms_key_id                    = var.cloudtrail_kms_key_arn

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    # Log all S3 object-level read/write events — required for CC7.2 audit evidence
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"] # All buckets; scope to specific buckets in cost-sensitive envs
    }
  }

  tags = local.common_tags
}

# ─── AWS Config ───────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "config_logs" {
  bucket        = "aws-config-logs-${var.account_id}-${var.region}"
  force_destroy = false

  tags = merge(local.common_tags, { Name = "aws-config-logs" })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.cloudtrail_kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "config_logs" {
  bucket                  = aws_s3_bucket.config_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "config" {
  name = "aws-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "main" {
  name     = "compliance-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "compliance-channel"
  s3_bucket_name = aws_s3_bucket.config_logs.id
  depends_on     = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

# Config managed rules covering SOC 2 criteria (CC6.2, CC6.6, CC6.7, CC7.2)
locals {
  config_rules = {
    "cloudtrail-enabled"        = "CLOUD_TRAIL_ENABLED"
    "cloudtrail-log-validation" = "CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED"
    "multi-region-cloudtrail"   = "MULTI_REGION_CLOUD_TRAIL_ENABLED"
    "mfa-enabled-for-console"   = "MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS"
    "root-account-mfa"          = "ROOT_ACCOUNT_MFA_ENABLED"
    "access-keys-rotated"       = "ACCESS_KEYS_ROTATED"
    "encrypted-volumes"         = "ENCRYPTED_VOLUMES"
    "rds-storage-encrypted"     = "RDS_STORAGE_ENCRYPTED"
    "s3-bucket-public-read"     = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
    "s3-bucket-public-write"    = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"
    "vpc-flow-logs-enabled"     = "VPC_FLOW_LOGS_ENABLED"
    "restricted-ssh"            = "INCOMING_SSH_DISABLED"
  }
}

resource "aws_config_config_rule" "soc2" {
  for_each = local.config_rules

  name = each.key
  source {
    owner             = "AWS"
    source_identifier = each.value
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# ─── VPC Flow Logs ────────────────────────────────────────────────────────────

resource "aws_flow_log" "main" {
  vpc_id               = var.vpc_id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = "${aws_s3_bucket.cloudtrail_logs.arn}/vpc-flow-logs/"

  log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status}"

  tags = merge(local.common_tags, { Name = "vpc-flow-log" })
}

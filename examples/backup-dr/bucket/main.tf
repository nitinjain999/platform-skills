# The Velero backup bucket, protected from deletion.
#
# Velero needs s3:DeleteObject to expire backups past their TTL, so anyone
# holding its credentials (or ransomware running as it) can issue deletes. With
# versioning on, a delete only adds a delete marker; the data stays as a
# noncurrent version for noncurrent_retention_days. The bucket policy denies
# every principal except admin_role_arns the calls that would remove that
# safety net: deleting object versions, suspending versioning, rewriting the
# lifecycle, replacing the policy, deleting the bucket.
#
# Apply this with one of admin_role_arns, or the next apply is denied by the
# policy it created. The account root user can still delete a bucket policy;
# that is the last-resort recovery path.

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "bucket_name" {
  description = "Backup bucket; must match the bucket in velero/helmrelease.yaml and the S3 ARNs in iam-policy.json."
  type        = string
  default     = "example-velero-backups-eu-north-1"
}

variable "admin_role_arns" {
  description = "IAM roles allowed to purge object versions or change the bucket's protection: the break-glass role and the role that applies this Terraform. Never the Velero role."
  type        = list(string)

  validation {
    condition     = length(var.admin_role_arns) > 0 && alltrue([for a in var.admin_role_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/.+", a))])
    error_message = "admin_role_arns must list at least one IAM role ARN (arn:aws:iam::<account>:role/<name>)."
  }
}

variable "noncurrent_retention_days" {
  description = "How long a deleted or overwritten backup object stays recoverable. Keep it longer than the time you need to notice a deletion."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_retention_days >= 7
    error_message = "noncurrent_retention_days must be at least 7."
  }
}

provider "aws" {
  region = "eu-north-1"
}

resource "aws_s3_bucket" "backups" {
  bucket = var.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Deleted and overwritten objects become noncurrent versions; they are removed
# only after the retention window, so a deletion is recoverable until then.
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_retention_days
    }
    expiration {
      expired_object_delete_marker = true
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.backups]
}

data "aws_iam_policy_document" "backups" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "OnlyAdminsRemoveProtection"
    effect = "Deny"
    actions = [
      "s3:DeleteObjectVersion",
      "s3:PutBucketVersioning",
      "s3:PutLifecycleConfiguration",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:DeleteBucket",
    ]
    resources = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = var.admin_role_arns
    }
  }
}

resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id
  policy = data.aws_iam_policy_document.backups.json

  depends_on = [aws_s3_bucket_public_access_block.backups]
}

output "bucket_name" {
  value = aws_s3_bucket.backups.id
}

output "bucket_arn" {
  value = aws_s3_bucket.backups.arn
}

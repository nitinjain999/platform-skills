# examples/compliance/backup/main.tf
#
# SOC 2 A1.2 / A1.3 — backup and recovery: AWS Backup Plan with daily and
# monthly schedules, vault lock in COMPLIANCE mode (35-day minimum retention),
# cross-region copy for disaster recovery, and tag-based resource selection.
#
# Prerequisites:
#   - aws provider >= 5.0
#   - Production resources must be tagged: environment=production
#   - DR vault must be pre-created in the destination region (see outputs below)
#   - KMS keys must exist in both source and DR regions
#
# Validation:
#   checkov -d . --config-file ../checkov-config.yaml
#   aws backup list-backup-jobs --by-state COMPLETED
#   aws backup describe-backup-vault --backup-vault-name production-backup-vault
#   aws backup list-protected-resources

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

variable "region" {
  description = "Primary AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "dr_region" {
  description = "Disaster recovery region for cross-region backup copies"
  type        = string
  default     = "eu-west-1"
}

variable "dr_vault_arn" {
  description = "ARN of the backup vault in the DR region (must be pre-created)"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for backup vault encryption in the primary region"
  type        = string
}

variable "security_alert_topic_arn" {
  description = "SNS topic ARN for backup job failure notifications"
  type        = string
}

locals {
  common_tags = {
    ManagedBy  = "terraform"
    Compliance = "soc2"
  }
}

# ─── Backup vault (primary region) ───────────────────────────────────────────

resource "aws_backup_vault" "main" {
  name        = "production-backup-vault"
  kms_key_arn = var.kms_key_arn # CC6.7: encrypt backups at rest

  tags = local.common_tags
}

# Vault lock — COMPLIANCE mode prevents deletion of recovery points for 35 days.
# After changeable_for_days elapses the lock itself cannot be removed.
# WARNING: test this in non-production first — it is irreversible.
resource "aws_backup_vault_lock_configuration" "main" {
  backup_vault_name   = aws_backup_vault.main.name
  min_retention_days  = 35 # A1.2: compliance.tf specifies 35-day minimum
  max_retention_days  = 365
  changeable_for_days = 3 # Lock becomes permanent after 3 days — set before go-live
}

# ─── Backup plan ──────────────────────────────────────────────────────────────

resource "aws_backup_plan" "main" {
  name = "production-backup-plan"

  # Daily backup — 35-day retention for PITR-style recovery (A1.2)
  rule {
    rule_name         = "daily-35-day-retention"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 * * ? *)" # Daily at 03:00 UTC
    start_window      = 60                  # Must start within 60 minutes
    completion_window = 180                 # Must complete within 3 hours

    lifecycle {
      delete_after = 35
    }

    # Cross-region copy for disaster recovery (A1.3)
    copy_action {
      destination_vault_arn = var.dr_vault_arn

      lifecycle {
        delete_after = 35
      }
    }

    recovery_point_tags = local.common_tags
  }

  # Monthly backup — 1-year retention for long-term audit evidence (A1.2)
  rule {
    rule_name         = "monthly-1-year-retention"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 1 * ? *)" # First of each month at 03:00 UTC
    start_window      = 60
    completion_window = 360

    lifecycle {
      cold_storage_after = 30 # Move to cold storage after 30 days (cost optimisation)
      delete_after       = 365
    }

    # Cross-region copy for long-term DR copies
    copy_action {
      destination_vault_arn = var.dr_vault_arn

      lifecycle {
        cold_storage_after = 30
        delete_after       = 365
      }
    }

    recovery_point_tags = local.common_tags
  }

  tags = local.common_tags
}

# ─── IAM role for AWS Backup ──────────────────────────────────────────────────

resource "aws_iam_role" "backup" {
  name        = "aws-backup-role"
  description = "Role used by AWS Backup to create and restore recovery points (SOC 2 A1.2)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "backup_create" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# ─── Backup selection — all resources tagged environment=production ────────────

resource "aws_backup_selection" "production" {
  name         = "production-resources"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  # Tag-based selection: covers RDS, DynamoDB, EFS, EC2, EBS, Aurora, FSx, S3
  selection_tag {
    type  = "STRINGEQUALS"
    key   = "environment"
    value = "production"
  }
}

# ─── Backup notifications ─────────────────────────────────────────────────────

resource "aws_backup_vault_notifications" "main" {
  backup_vault_name = aws_backup_vault.main.name
  sns_topic_arn     = var.security_alert_topic_arn
  backup_vault_events = [
    "BACKUP_JOB_FAILED",
    "COPY_JOB_FAILED",
    "RESTORE_JOB_FAILED",
  ]
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "backup_vault_arn" {
  description = "ARN of the primary backup vault"
  value       = aws_backup_vault.main.arn
}

output "backup_plan_id" {
  description = "ID of the backup plan"
  value       = aws_backup_plan.main.id
}

output "backup_role_arn" {
  description = "ARN of the IAM role used by AWS Backup"
  value       = aws_iam_role.backup.arn
}

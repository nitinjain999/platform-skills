# SCENARIO: Rollback — RDS storage increase (irreversible) + prevent_destroy removal
#
# Expected pr-review rollback output:
#
#   [ROLLBACK] aws_db_instance.payments_after — allocated_storage increase
#     Change: 100 GB → 500 GB
#     Reversibility: NONE — AWS does not support decreasing RDS allocated_storage
#     Blast radius: DATA
#     Pre-merge requirement: manual RDS snapshot taken and ARN recorded in PR
#
#   [ROLLBACK] aws_db_instance.payments_after — prevent_destroy removed
#     Reversibility: MANUAL — future terraform destroy will permanently delete data
#     Pre-merge requirement: explicit justification in PR description
#
# Rollback Risk Score: 🔴 HIGH

resource "aws_kms_key" "rds" {
  description             = "KMS key for payments RDS"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

# ✅ BEFORE — protected, sized at 100 GB
resource "aws_db_instance" "payments_before" {
  identifier        = "payments-db-before"
  engine            = "postgres"
  instance_class    = "db.t3.medium"
  allocated_storage = 100
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn
  username          = "admin"
  password          = var.db_password

  backup_retention_period = 35
  deletion_protection     = true
  skip_final_snapshot     = false

  lifecycle {
    prevent_destroy = true # safety net against accidental deletion
  }
}

# ❌ AFTER (PR) — storage increase + prevent_destroy removed
resource "aws_db_instance" "payments_after" {
  identifier        = "payments-db-after"
  engine            = "postgres"
  instance_class    = "db.t3.medium"
  allocated_storage = 500 # ← irreversible increase
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn
  username          = "admin"
  password          = var.db_password

  backup_retention_period = 35
  deletion_protection     = true
  skip_final_snapshot     = false

  # ❌ prevent_destroy removed — no longer protected from terraform destroy
}

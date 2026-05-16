# SCENARIO: Rollback — RDS storage increase (irreversible) + prevent_destroy removal
#
# Expected output:
#
#   [ROLLBACK] aws_db_instance.payments — allocated_storage increase
#     Change: 100 GB → 500 GB
#     Reversibility: NONE — AWS does not support decreasing RDS allocated_storage.
#     Reducing storage requires: snapshot → create new instance from snapshot
#     with smaller size → data migration → DNS cutover. Estimated 2–4 hours.
#     Blast radius: DATA
#     Rollback procedure:
#       1. Take manual snapshot: aws rds create-db-snapshot --db-instance-identifier payments-db
#       2. Verify snapshot complete before applying
#       3. If rollback needed post-apply: restore from snapshot to new instance,
#          update application DNS/connection string, verify data integrity
#     Pre-merge requirement: manual RDS snapshot taken and ARN recorded in PR
#
#   [ROLLBACK] aws_db_instance.payments — prevent_destroy removed
#     Change: lifecycle.prevent_destroy = true → removed
#     Reversibility: MANUAL — without prevent_destroy, a future `terraform destroy`
#     or accidental resource removal will permanently delete the RDS instance and
#     all data. This change does not immediately destroy anything but removes the
#     safety net.
#     Blast radius: DATA
#     Rollback procedure: Re-add prevent_destroy = true in a follow-up commit.
#     Pre-merge requirement: Explicit justification in PR description for why
#     prevent_destroy is being removed.
#
# Rollback Risk Score: 🔴 HIGH
#   Reason: NONE reversibility + DATA blast radius on storage increase.
#   Required before merge: RDS snapshot ARN in PR description + team lead sign-off.

# ❌ BEFORE — protected, sized at 100 GB
resource "aws_db_instance" "payments" {
  identifier        = "payments-db"
  engine            = "postgres"
  instance_class    = "db.t3.medium"
  allocated_storage = 100
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  backup_retention_period = 35
  deletion_protection     = true

  lifecycle {
    prevent_destroy = true # safety net against accidental deletion
  }
}

# ❌ AFTER (PR) — storage increase + prevent_destroy removed
resource "aws_db_instance" "payments" {
  identifier        = "payments-db"
  engine            = "postgres"
  instance_class    = "db.t3.medium"
  allocated_storage = 500 # ← irreversible increase
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  backup_retention_period = 35
  deletion_protection     = true

  # ❌ prevent_destroy removed — no longer protected from terraform destroy
}

# ✅ RECOMMENDED — keep prevent_destroy, document the storage increase intent
# resource "aws_db_instance" "payments" {
#   ...
#   allocated_storage = 500
#   lifecycle {
#     prevent_destroy = true   # keep even after storage increase
#   }
# }

# SCENARIO: Compliance — wildcard IAM and unencrypted RDS (CC6.1, CC6.7)
#
# Expected output:
#
#   [COMPLIANCE] CC6.1 — Logical access
#     Finding: aws_iam_role_policy.app_policy uses Action: "*" and Resource: "*"
#     File: compliance/iam-wildcard.tf
#     Severity: CRITICAL — grants full AWS access to the application role;
#     violates least privilege and will block SOC 2 CC6.1 audit evidence.
#     Remediation: Replace with explicit actions scoped to required services.
#     See fix below.
#     Auditor evidence: aws iam simulate-principal-policy --policy-source-arn <role-arn> \
#       --action-names "s3:*" --resource-arns "*"
#
#   [COMPLIANCE] CC6.7 — Encryption
#     Finding: aws_db_instance.app storage_encrypted = false
#     File: compliance/iam-wildcard.tf
#     Severity: CRITICAL — RDS data at rest unencrypted; fails CC6.7.
#     Remediation: Set storage_encrypted = true and provide a kms_key_id.
#     Note: enabling encryption on an existing unencrypted instance requires
#     a snapshot → restore cycle (Reversibility: NONE — see rollback mode).
#     Auditor evidence: aws rds describe-db-instances \
#       --query 'DBInstances[*].{ID:DBInstanceIdentifier,Encrypted:StorageEncrypted}'

# ❌ BEFORE — violates CC6.1 and CC6.7

resource "aws_iam_role_policy" "app_policy" {
  name = "app-policy"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*"        # ❌ CC6.1 — wildcard action
      Resource = "*"        # ❌ CC6.1 — wildcard resource
    }]
  })
}

resource "aws_db_instance" "app" {
  identifier        = "payments-db"
  engine            = "postgres"
  instance_class    = "db.t3.medium"
  allocated_storage = 20
  storage_encrypted = false    # ❌ CC6.7 — unencrypted at rest
  username          = "admin"
  password          = var.db_password
}

# ✅ AFTER — CC6.1 and CC6.7 compliant

resource "aws_iam_role_policy" "app_policy" {
  name = "app-s3-read"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        "arn:aws:s3:::${var.assets_bucket}",
        "arn:aws:s3:::${var.assets_bucket}/*"
      ]
    }]
  })
}

resource "aws_kms_key" "rds" {
  description             = "KMS key for payments RDS encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_db_instance" "app" {
  identifier        = "payments-db"
  engine            = "postgres"
  instance_class    = "db.t3.medium"
  allocated_storage = 20
  storage_encrypted = true            # ✅ CC6.7
  kms_key_id        = aws_kms_key.rds.arn
  username          = "admin"
  password          = var.db_password

  backup_retention_period = 35        # ✅ A1.2 — minimum 35 days for SOC 2
  deletion_protection     = true
}

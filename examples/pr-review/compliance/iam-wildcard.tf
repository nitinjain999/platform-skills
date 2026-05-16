# SCENARIO: Compliance — wildcard IAM and unencrypted RDS (CC6.1, CC6.7)
#
# Expected pr-review compliance output:
#
#   [COMPLIANCE] CC6.1 — Logical access
#     Finding: aws_iam_role_policy.app_policy_before uses Action: "*" Resource: "*"
#     Severity: CRITICAL — grants full AWS access; violates least privilege
#     Remediation: Replace with explicit actions scoped to required services.
#     Auditor evidence: aws iam simulate-principal-policy --policy-source-arn <arn> \
#       --action-names "s3:*" --resource-arns "*"
#
#   [COMPLIANCE] CC6.7 — Encryption
#     Finding: aws_db_instance.app_before storage_encrypted = false
#     Severity: CRITICAL — RDS data at rest unencrypted
#     Remediation: Set storage_encrypted = true and provide kms_key_id.
#     Auditor evidence: aws rds describe-db-instances \
#       --query 'DBInstances[*].{ID:DBInstanceIdentifier,Encrypted:StorageEncrypted}'

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "assets_bucket" {
  description = "S3 bucket name for application assets"
  type        = string
}

# ❌ BEFORE — violates CC6.1 and CC6.7
resource "aws_iam_role_policy" "app_policy_before" {
  name = "app-policy-before"
  role = "app-role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*" # ❌ CC6.1 — wildcard action
      Resource = "*" # ❌ CC6.1 — wildcard resource
    }]
  })
}

resource "aws_db_instance" "app_before" {
  identifier        = "payments-db-before"
  engine            = "postgres"
  instance_class    = "db.t3.medium"
  allocated_storage = 20
  storage_encrypted = false # ❌ CC6.7 — unencrypted at rest
  username          = "admin"
  password          = var.db_password

  skip_final_snapshot = true
}

# ✅ AFTER — CC6.1 and CC6.7 compliant
resource "aws_iam_role_policy" "app_policy" {
  name = "app-s3-read"
  role = "app-role"

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
  storage_encrypted = true # ✅ CC6.7
  kms_key_id        = aws_kms_key.rds.arn
  username          = "admin"
  password          = var.db_password

  backup_retention_period = 35 # ✅ A1.2 — minimum 35 days for SOC 2
  deletion_protection     = true
  skip_final_snapshot     = false
}

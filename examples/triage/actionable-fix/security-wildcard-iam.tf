# Example: wildcard IAM policy — triggers ACTIONABLE_FIX classification
#
# Copilot / security bot will flag:
#   Action = ["s3:*"] and Resource = ["*"] as over-permissive (SOC 2 CC6.1)
#
# Expected triage fix: scope to explicit actions and target bucket ARN.

variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket this role needs access to"
}

# ❌ Before — wildcard action and resource (what the PR originally contained)
resource "aws_iam_policy" "app_before" {
  name = "app-s3-policy-before"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*"]
      Resource = ["*"]
    }]
  })
}

# ✅ After — scoped to explicit actions and bucket ARN (what triage commits)
resource "aws_iam_policy" "app" {
  name = "app-s3-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        "arn:aws:s3:::${var.bucket_name}",
        "arn:aws:s3:::${var.bucket_name}/*"
      ]
    }]
  })
}

variable "app_name" {
  description = "Application name — used to scope resources and IAM"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket this app reads and writes"
  type        = string
}

variable "aws_region" {
  description = "AWS region — used in resource ARN conditions"
  type        = string
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "app" {
  name = "${var.app_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:RequestedRegion" = var.aws_region
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "app_s3" {
  name = "${var.app_name}-s3-policy"
  role = aws_iam_role.app.id

  # Least privilege: only the actions this app actually needs
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BucketRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      },
      {
        Sid    = "BucketWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}/*"
      },
      {
        Sid    = "SecretsRead"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.app_name}/*"
      }
    ]
  })
}

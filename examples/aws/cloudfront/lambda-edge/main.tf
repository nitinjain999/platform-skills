terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Lambda@Edge must be deployed to us-east-1.
provider "aws" {
  region = "us-east-1"
}

variable "name" {
  type        = string
  description = "Name prefix for the Lambda@Edge function and IAM role."
}

# ─── IAM ──────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "edge_trust" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "lambda.amazonaws.com",
        "edgelambda.amazonaws.com", # required — without this, CloudFront replication fails
      ]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "edge" {
  provider           = aws
  name               = "${var.name}-edge-role"
  assume_role_policy = data.aws_iam_policy_document.edge_trust.json
}

resource "aws_iam_role_policy_attachment" "edge_basic" {
  provider   = aws
  role       = aws_iam_role.edge.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ─── Log group ────────────────────────────────────────────────────────────────

# Lambda@Edge logs replicate to CloudWatch in the edge region where the function runs.
# The log group name pattern is: /aws/lambda/us-east-1.<function-name>
# Pre-create in us-east-1 so Terraform manages retention.
resource "aws_cloudwatch_log_group" "edge" {
  provider          = aws
  name              = "/aws/lambda/us-east-1.${var.name}-edge"
  retention_in_days = 30
}

# ─── Function package ─────────────────────────────────────────────────────────

data "archive_file" "edge" {
  type        = "zip"
  source_file = "${path.module}/functions/viewer-request.js"
  output_path = "${path.module}/functions/viewer-request.zip"
}

# ─── Lambda@Edge function ─────────────────────────────────────────────────────

resource "aws_lambda_function" "edge" {
  provider = aws

  filename         = data.archive_file.edge.output_path
  source_code_hash = data.archive_file.edge.output_base64sha256
  function_name    = "${var.name}-edge"
  role             = aws_iam_role.edge.arn
  handler          = "viewer-request.handler"
  runtime          = "nodejs22.x"
  publish          = true # mandatory — CloudFront requires a numbered version ARN, not $LATEST

  # Lambda@Edge constraints:
  # - No VPC attachment
  # - No environment variables (use CloudFront KeyValueStore for config)
  # - Memory: max 128 MB for viewer events, 512 MB for origin events
  # - Timeout: max 5s for viewer events, 30s for origin events
  memory_size = 128
  timeout     = 5

  depends_on = [
    aws_iam_role_policy_attachment.edge_basic,
    aws_cloudwatch_log_group.edge,
  ]
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "qualified_arn" {
  description = "Numbered version ARN required by CloudFront lambda_function_association. Do NOT use .arn (that is $LATEST)."
  value       = aws_lambda_function.edge.qualified_arn
}

output "function_name" {
  description = "Lambda function name."
  value       = aws_lambda_function.edge.function_name
}

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# WAF with CLOUDFRONT scope MUST be created in us-east-1.
# This module is intended to be used standalone and its web_acl_arn output
# passed to the CloudFront module via var.waf_web_acl_arn.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = var.default_tags
  }
}

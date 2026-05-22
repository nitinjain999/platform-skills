terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Default provider — origin resources live here
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.default_tags
  }
}

# CloudFront is a global service but its ACM certificate, WAF web ACL,
# and Lambda@Edge functions must all be in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = var.default_tags
  }
}

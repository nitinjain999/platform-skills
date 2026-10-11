# Layer 1 of 4: tag at the source. Every resource this provider creates gets
# the required tags through default_tags, and a plan without them fails here,
# before the OPA check (layer 2) or AWS Config (layer 3) ever see it.

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "required_tags" {
  description = "Tags every resource must carry. Keys must match the FinOps policy (owner, cost-center, environment)."
  type        = map(string)

  validation {
    condition = alltrue([
      # try(): Terraform before 1.12 evaluates both sides of &&, so a missing key
      # would fail with "Invalid index" instead of this error_message.
      for k in ["owner", "cost-center", "environment"] : try(length(trimspace(var.required_tags[k])) > 0, false)
    ])
    error_message = "required_tags must set non-empty owner, cost-center and environment."
  }
}

provider "aws" {
  region = "eu-north-1"

  default_tags {
    tags = var.required_tags
  }
}

# Layer 3 of 4: detect drift. Resources created outside Terraform, or with tags
# removed later, show up as NON_COMPLIANT. The managed rule checks up to six
# keys. It needs an AWS Config recorder in the account and region.
resource "aws_config_config_rule" "required_tags" {
  name        = "required-tags"
  description = "Resources must carry owner, cost-center and environment tags."

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  input_parameters = jsonencode({
    tag1Key = "owner"
    tag2Key = "cost-center"
    tag3Key = "environment"
  })
}

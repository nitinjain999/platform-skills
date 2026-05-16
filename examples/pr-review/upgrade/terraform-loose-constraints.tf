# SCENARIO: Upgrade — loose Terraform provider constraints and floating module ref
#
# Expected output:
#
#   [UPGRADE] versions.tf — AWS provider constraint too loose
#     Found: version = ">= 3.0"
#     Removed in: allows major version jump (3→4→5) with breaking changes
#     Replacement: version = "~> 5.0"
#     Migration effort: MEDIUM — review AWS provider v5 migration guide for
#     breaking changes (e.g. default_tags behaviour, removed resources)
#     Flag: BREAKING — ">= 3.0" will silently adopt provider v5 breaking changes
#     on next `terraform init -upgrade`
#
#   [UPGRADE] main.tf — EKS module source without version pin
#     Found: source = "terraform-aws-modules/eks/aws" with no version
#     Removed in: N/A — but next `terraform init` may pull a new major version
#     Replacement: version = "~> 20.0"
#     Migration effort: HIGH — module major versions have breaking input/output changes

# ❌ BEFORE — loose constraints

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.0"    # ❌ allows major version jumps with breaking changes
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"    # ❌ same issue
    }
  }
  required_version = ">= 1.0"    # ❌ too loose — any 1.x or 2.x will match
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"    # ❌ no version pin — floats to latest
  # ...
}

# ✅ AFTER — pessimistic constraints

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"    # ✅ locks to 5.x, won't jump to 6.0
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"   # ✅ locks to 2.x patch releases
    }
  }
  required_version = "~> 1.7"    # ✅ locks to 1.x
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"    # ✅ pinned to major version
  # ...
}

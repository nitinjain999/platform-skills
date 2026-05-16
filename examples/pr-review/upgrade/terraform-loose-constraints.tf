# SCENARIO: Upgrade — loose Terraform provider constraints and unversioned module ref
#
# Expected pr-review upgrade output:
#
#   [UPGRADE] versions_before.tf — AWS provider constraint too loose
#     Found: version = ">= 3.0"
#     Flag: BREAKING — allows silent jump to provider v5 with breaking changes
#     Replacement: version = "~> 5.0"
#     Migration effort: MEDIUM
#
#   [UPGRADE] versions_before.tf — unversioned module source
#     Found: source = "terraform-aws-modules/eks/aws" with no version
#     Replacement: version = "~> 20.0"
#     Migration effort: HIGH

# ❌ BEFORE — loose constraints (use _before suffix to avoid duplicate block errors)
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.0" # ❌ allows major version jumps with breaking changes
    }
  }
  required_version = ">= 1.0" # ❌ too loose — any 1.x or 2.x will match
}

# ✅ AFTER — pessimistic constraints (in a real fix, replace the block above)
# terraform {
#   required_providers {
#     aws = {
#       source  = "hashicorp/aws"
#       version = "~> 5.0"    # ✅ locks to 5.x, won't jump to 6.0
#     }
#     kubernetes = {
#       source  = "hashicorp/kubernetes"
#       version = "~> 2.27"   # ✅ locks to 2.x patch releases
#     }
#   }
#   required_version = "~> 1.7"    # ✅ locks to 1.x
# }

# ❌ BEFORE — module without version pin
# module "eks" {
#   source = "terraform-aws-modules/eks/aws"    # ❌ floats to latest on terraform init
# }

# ✅ AFTER — module pinned to major version
# module "eks" {
#   source  = "terraform-aws-modules/eks/aws"
#   version = "~> 20.0"    # ✅ locked to 20.x
# }

# Terraform Examples

This directory contains reference implementations for Terraform module patterns and best practices.

## Examples

### 1. EKS Cluster Module

[eks-cluster/](eks-cluster/) - Production-ready EKS cluster module

**Use case:** Reusable EKS cluster with opinionated defaults  
**Pattern:** Composition module wrapping AWS provider resources  
**Components:**
- Cluster with managed node groups
- VPC CNI and add-ons
- IAM roles for service accounts (IRSA)
- Security groups and networking

### 2. Multi-Environment Structure

[multi-env-structure/](multi-env-structure/) - Repository layout for multiple environments

**Use case:** Managing dev, staging, and production environments  
**Pattern:** Separate state per environment with shared modules  
**Components:**
- `modules/` - Reusable components
- `live/` - Environment-specific configurations
- Remote state configuration

### 3. Module Testing

[module-testing/](module-testing/) - Testing strategies for Terraform modules

**Use case:** Validating module behavior  
**Pattern:** Native tests, examples, and validation  
**Components:**
- Unit tests with native test framework
- Integration test examples
- Policy-as-code validation

### 4. CI/CD Pipeline

[cicd-pipeline/](cicd-pipeline/) - Complete Terraform CI/CD workflow

**Use case:** Automated plan, review, and apply  
**Pattern:** GitHub Actions with OIDC and protected environments  
**Components:**
- PR validation workflow
- Plan and apply workflows
- Security scanning integration

## Prerequisites

- Terraform 1.5+
- AWS CLI configured (for AWS examples)
- Azure CLI configured (for Azure examples)
- Git for version control

## Common Commands

```bash
# Initialize
terraform init

# Format code
terraform fmt -recursive

# Validate syntax
terraform validate

# Plan changes
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan

# Show current state
terraform show

# Import existing resource
terraform import aws_s3_bucket.example my-bucket

# Remove resource from state without destroying
terraform state rm aws_s3_bucket.example
```

## Module Development Checklist

- [ ] Clear README with usage examples
- [ ] Input variables with descriptions and validation
- [ ] Output values for downstream consumption
- [ ] Examples directory with working configurations
- [ ] Version constraints on providers
- [ ] Sensible defaults where appropriate
- [ ] Tags and naming conventions applied
- [ ] Security best practices followed
- [ ] Tests for critical functionality
- [ ] CHANGELOG for version tracking

## Best Practices

### Module Structure

```
module-name/
├── README.md              # Usage documentation
├── main.tf                # Primary resources
├── variables.tf           # Input variables
├── outputs.tf             # Output values
├── versions.tf            # Provider version constraints
├── examples/
│   ├── basic/            # Simple example
│   └── complete/         # Full-featured example
└── tests/
    └── basic.tftest.hcl  # Native tests
```

### Variable Naming

```hcl
# Good - descriptive and scoped
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

# Bad - too generic
variable "name" {
  description = "Name"
  type        = string
}
```

### Output Naming

```hcl
# Good - includes resource type context
output "cluster_endpoint" {
  description = "EKS cluster endpoint URL"
  value       = aws_eks_cluster.this.endpoint
}

# Bad - ambiguous
output "endpoint" {
  value = aws_eks_cluster.this.endpoint
}
```

### Validation

```hcl
variable "environment" {
  description = "Environment name"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production"
  }
}
```

## State Management

### Remote State

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "production/eks/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

### State Isolation

Separate state files by:
- Environment (dev, staging, production)
- Component (networking, compute, database)
- Blast radius (small changes separate from large)

### State Commands

```bash
# List resources in state
terraform state list

# Show specific resource
terraform state show aws_eks_cluster.main

# Move resource to different state file
terraform state mv aws_s3_bucket.old aws_s3_bucket.new

# Pull state to local file
terraform state pull > terraform.tfstate.backup
```

## Security Patterns

### IAM Least Privilege

```hcl
# ❌ Overly permissive
resource "aws_iam_policy" "bad" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:*"
      Resource = "*"
    }]
  })
}

# ✅ Least privilege
resource "aws_iam_policy" "good" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*"
      ]
    }]
  })
}
```

### Secrets Management

```hcl
# ❌ Never commit secrets
variable "database_password" {
  default = "hardcoded-secret-bad"
}

# ✅ Use external secret management
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "production/database/password"
}

resource "aws_db_instance" "this" {
  password = data.aws_secretsmanager_secret_version.db_password.secret_string
  # ... other config
}
```

## Troubleshooting

See [references/terraform.md](../../references/terraform.md) for detailed patterns.

### Common Issues

**State lock timeout:**
```bash
# Check who has the lock
aws dynamodb get-item \
  --table-name terraform-locks \
  --key '{"LockID":{"S":"my-state-bucket/path/terraform.tfstate-md5"}}'

# Force unlock (dangerous - verify no other process running)
terraform force-unlock <lock-id>
```

**Resource already exists:**
```bash
# Import into state
terraform import aws_s3_bucket.example existing-bucket-name
```

**Drift detection:**
```bash
# Refresh state and show drift
terraform plan -refresh-only
```

## Further Reading

- [Terraform Registry](https://registry.terraform.io/) - Provider and module documentation
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [AWS Terraform Modules](https://github.com/terraform-aws-modules/)

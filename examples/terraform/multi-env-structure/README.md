# Multi-Environment Terraform Structure

Example repository structure for managing multiple environments with Terraform.

## Structure

```
multi-env-structure/
├── modules/                    # Reusable modules
│   ├── networking/            # VPC, subnets, routing
│   └── eks-cluster/           # EKS cluster abstraction
├── live/                      # Environment configurations
│   ├── staging/
│   │   ├── backend.tf        # Remote state configuration
│   │   ├── main.tf           # Module compositions
│   │   ├── variables.tf      # Environment variables
│   │   ├── outputs.tf        # Environment outputs
│   │   └── terraform.tfvars  # Environment-specific values
│   └── production/
│       ├── backend.tf
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars
└── README.md
```

## Key Principles

### 1. Separate State Per Environment

Each environment has its own state file:

```hcl
# live/production/backend.tf
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

### 2. Reusable Modules

Modules are environment-agnostic:

```hcl
# live/production/main.tf
module "networking" {
  source = "../../modules/networking"

  environment = "production"
  vpc_cidr    = var.vpc_cidr
  azs         = var.availability_zones
}

module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name    = "production-cluster"
  cluster_version = "1.29"
  vpc_id          = module.networking.vpc_id
  subnet_ids      = module.networking.private_subnet_ids
}
```

### 3. Environment-Specific Values

Use `.tfvars` files for environment differences:

```hcl
# live/staging/terraform.tfvars
vpc_cidr             = "10.1.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
cluster_node_count   = 2
instance_types       = ["t3.medium"]
```

```hcl
# live/production/terraform.tfvars
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
cluster_node_count   = 5
instance_types       = ["t3.large", "t3a.large"]
```

## Workflow

### Initialize Environment

```bash
cd live/staging
terraform init
```

### Plan Changes

```bash
terraform plan -var-file=terraform.tfvars
```

### Apply Changes

```bash
terraform apply -var-file=terraform.tfvars
```

### Switch Environments

```bash
cd ../production
terraform init
terraform plan -var-file=terraform.tfvars
```

## Best Practices

### 1. Provider Configuration

Configure in each environment:

```hcl
# live/production/main.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "production"
      ManagedBy   = "terraform"
      Owner       = "platform-team"
    }
  }
}
```

### 2. Remote State References

Reference other state files when needed:

```hcl
data "terraform_remote_state" "networking" {
  backend = "s3"

  config = {
    bucket = "my-terraform-state"
    key    = "production/networking/terraform.tfstate"
    region = "us-east-1"
  }
}
```

### 3. Validation

Add validation to variables:

```hcl
variable "environment" {
  description = "Environment name"
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be staging or production"
  }
}
```

### 4. Consistent Naming

Use naming conventions:

```hcl
locals {
  name_prefix = "${var.environment}-${var.project_name}"

  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket" "example" {
  bucket = "${local.name_prefix}-bucket"
  tags   = local.common_tags
}
```

## State Management

### State Locking

Use DynamoDB for state locking:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"

    # Prevent accidental state deletion
    skip_region_validation      = false
    skip_credentials_validation = false
    skip_metadata_api_check     = false
  }
}
```

### State Migration

Moving resources between environments:

```bash
# Export from staging
cd live/staging
terraform state pull > staging-state.json

# Import to production
cd ../production
terraform import aws_s3_bucket.example my-bucket-name
```

## CI/CD Integration

### GitHub Actions Example

```yaml
jobs:
  terraform:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        environment: [staging, production]
    steps:
      - uses: actions/checkout@v4
      - name: Terraform Plan
        working-directory: live/${{ matrix.environment }}
        run: |
          terraform init
          terraform plan -var-file=terraform.tfvars
```

## Security

### Secrets Management

Never commit sensitive values:

```hcl
# ❌ Don't do this
variable "database_password" {
  default = "hardcoded-secret"
}

# ✅ Do this
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "production/database/password"
}
```

### IAM Least Privilege

Terraform execution role should have minimal permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "eks:Describe*",
        "eks:List*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1"
        }
      }
    }
  ]
}
```

## Troubleshooting

### State Lock Issues

```bash
# View lock info
aws dynamodb get-item \
  --table-name terraform-locks \
  --key '{"LockID":{"S":"my-state-bucket/production/terraform.tfstate-md5"}}'

# Force unlock (only if certain no other process is running)
terraform force-unlock <lock-id>
```

### Drift Detection

```bash
# Refresh and show changes
terraform plan -refresh-only
```

## Further Reading

- See [examples/terraform/eks-cluster/](../eks-cluster/) for module implementation
- See [references/terraform.md](../../../references/terraform.md) for patterns

# EKS Cluster Module

Production-ready Amazon EKS cluster module with opinionated defaults and security best practices.

## Features

- **Security**: Private endpoint, envelope encryption, audit logging enabled
- **Networking**: VPC CNI with custom networking support
- **IAM**: IRSA (IAM Roles for Service Accounts) configured
- **Add-ons**: AWS Load Balancer Controller, EBS CSI Driver, VPC CNI
- **Managed node groups**: Auto-scaling with multiple instance types
- **Monitoring**: CloudWatch logging and Container Insights ready

## Usage

```hcl
module "eks_cluster" {
  source = "./eks-cluster"

  cluster_name    = "production-cluster"
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  node_groups = {
    general = {
      desired_size = 3
      min_size     = 2
      max_size     = 10

      instance_types = ["t3.large", "t3a.large"]
      capacity_type  = "SPOT"

      labels = {
        role = "general"
      }

      taints = []
    }
  }

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Name of the EKS cluster | `string` | n/a | yes |
| cluster_version | Kubernetes version | `string` | `"1.29"` | no |
| vpc_id | VPC ID where cluster will be created | `string` | n/a | yes |
| subnet_ids | List of subnet IDs for the cluster | `list(string)` | n/a | yes |
| node_groups | Map of node group configurations | `map(any)` | `{}` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | EKS cluster ID |
| cluster_endpoint | EKS cluster endpoint |
| cluster_security_group_id | Security group ID attached to the cluster |
| cluster_iam_role_arn | IAM role ARN of the cluster |
| oidc_provider_arn | ARN of the OIDC provider for IRSA |

## Examples

See [examples/](examples/) directory for complete working examples.

## Security Considerations

- Cluster endpoint is private by default
- Envelope encryption enabled for secrets
- Audit logging enabled for control plane
- IAM roles follow least-privilege principles
- Security groups restrict traffic appropriately

## License

Apache-2.0

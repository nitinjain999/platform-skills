# AWS Examples

This directory contains reference implementations for AWS best practices and common patterns.

## Examples

### 1. EKS Cluster (see Terraform examples)

See [../terraform/eks-cluster/](../terraform/eks-cluster/) for production-ready EKS cluster module.

### 2. IAM Policies

#### Least Privilege S3 Access

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::my-app-bucket",
      "Condition": {
        "StringLike": {
          "s3:prefix": ["data/*"]
        }
      }
    },
    {
      "Sid": "ReadWriteObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::my-app-bucket/data/*"
    }
  ]
}
```

#### IRSA Policy for EKS Pods

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:Query"
      ],
      "Resource": "arn:aws:dynamodb:us-east-1:123456789012:table/my-app-table",
      "Condition": {
        "ForAllValues:StringEquals": {
          "dynamodb:LeadingKeys": ["${aws:PrincipalTag/app-id}"]
        }
      }
    }
  ]
}
```

### 3. VPC Design Patterns

#### Three-Tier VPC

- **Public subnets**: Load balancers, NAT gateways
- **Private subnets**: Application workloads (EKS nodes)
- **Data subnets**: Databases, caches (no internet access)

```
10.0.0.0/16 VPC
├── 10.0.0.0/20   - Public Subnet AZ1
├── 10.0.16.0/20  - Public Subnet AZ2
├── 10.0.32.0/19  - Private Subnet AZ1
├── 10.0.64.0/19  - Private Subnet AZ2
├── 10.0.96.0/20  - Data Subnet AZ1
└── 10.0.112.0/20 - Data Subnet AZ2
```

### 4. Resource Tagging Strategy

```hcl
default_tags = {
  Environment  = "production"
  Application  = "my-app"
  Owner        = "platform-team@example.com"
  CostCenter   = "engineering"
  ManagedBy    = "terraform"
  Project      = "platform-migration"
  Compliance   = "pci-dss"
}
```

### 5. OIDC Federation for GitHub Actions

See [references/aws.md](../../references/aws.md) and [examples/github-actions/](../github-actions/) for complete OIDC setup.

## Common Patterns

### EKS with IRSA

```hcl
# Create OIDC provider
module "eks" {
  source = "../../terraform/eks-cluster"
  # ... config
}

# IAM role for service account
module "irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "my-app-irsa"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["my-app:my-app-sa"]
    }
  }

  role_policy_arns = {
    policy = aws_iam_policy.my_app.arn
  }
}

# Kubernetes service account
resource "kubernetes_service_account" "my_app" {
  metadata {
    name      = "my-app-sa"
    namespace = "my-app"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.irsa_role.iam_role_arn
    }
  }
}
```

### ALB Ingress with ACM

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/id
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/healthcheck-path: /health
spec:
  ingressClassName: alb
  rules:
  - host: my-app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

## Security Best Practices

### 1. Deny Public S3 Buckets

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyPublicBuckets",
      "Effect": "Deny",
      "Action": [
        "s3:PutBucketPublicAccessBlock",
        "s3:PutAccountPublicAccessBlock"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "s3:PublicAccessBlock": "true"
        }
      }
    }
  ]
}
```

### 2. Require MFA for Sensitive Actions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RequireMFAForDelete",
      "Effect": "Deny",
      "Action": [
        "ec2:TerminateInstances",
        "rds:DeleteDBInstance",
        "s3:DeleteBucket"
      ],
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {
          "aws:MultiFactorAuthPresent": "false"
        }
      }
    }
  ]
}
```

### 3. Enforce Encryption

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnencryptedObjectUploads",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::my-bucket/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption": "aws:kms"
        }
      }
    }
  ]
}
```

## Cost Optimization

### 1. Spot Instances for Non-Critical Workloads

```hcl
node_groups = {
  spot_workloads = {
    desired_size   = 3
    min_size       = 1
    max_size       = 10
    instance_types = ["t3.large", "t3a.large", "t2.large"]
    capacity_type  = "SPOT"

    labels = {
      workload = "batch"
      cost     = "optimized"
    }
  }
}
```

### 2. Lifecycle Policies

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}
```

## Troubleshooting

### EKS Node Not Joining

1. Check IAM role trust relationship
2. Verify security group allows cluster communication
3. Check userdata logs: `sudo cat /var/log/cloud-init-output.log`
4. Verify correct AMI for Kubernetes version

### IRSA Not Working

1. Verify OIDC provider exists and matches cluster
2. Check service account annotation
3. Verify pod has the correct service account
4. Check IAM role trust policy includes correct OIDC condition

### ALB Ingress Not Creating

1. Check AWS Load Balancer Controller logs
2. Verify IAM policy includes necessary permissions
3. Check ingress class matches controller
4. Verify subnet tags: `kubernetes.io/role/elb=1`

## Further Reading

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [AWS Security Best Practices](https://docs.aws.amazon.com/security/)

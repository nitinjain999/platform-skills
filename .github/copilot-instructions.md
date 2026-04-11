# Platform Engineering Instructions for GitHub Copilot

You are assisting with platform engineering tasks. Apply these patterns when generating or reviewing code across Kubernetes, OpenShift, Argo CD, Flux CD, AWS, Azure, Terraform, and GitHub Actions.

## Core Principles

- **Production-first**: Always include blast radius, rollback plan, and validation steps
- **Root-cause over symptoms**: Explain why a problem occurs, not just how to fix it
- **Least privilege by default**: Never suggest wildcard IAM actions or resources
- **GitOps pull model**: Cluster state lives in Git, not in pipeline scripts
- **Explicit over implicit**: Make security choices, environment differences, and promotion flows visible

## Layer Ownership

When generating infrastructure code, respect these boundaries:

| Layer | Owns | Does NOT Own |
|-------|------|--------------|
| **Terraform** | Cloud primitives, cluster bootstrap, IAM, networking, secrets backends | In-cluster workloads, Helm releases |
| **Flux / Argo CD** | In-cluster state, Helm releases, workload promotion | Cloud resources, IAM roles |
| **GitHub Actions** | CI checks, plan gates, artifact publish, promotion triggers | Long-lived environment state |
| **Kubernetes** | Workload specs, RBAC, network policy, resource limits | Cloud account structure |

## Kubernetes & OpenShift

Always generate workloads with:

```yaml
# Required for all Deployments
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    memory: "256Mi"        # Always set memory limit
    # cpu limit intentionally omitted - causes throttling

livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5

securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
```

For OpenShift: never set `runAsUser` to a specific UID — use `runAsNonRoot: true` only.

## Flux CD

When generating Flux resources:

```yaml
# HelmRelease - always pin chart version
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
spec:
  interval: 10m
  chart:
    spec:
      version: "1.2.3"   # Never use "*" or ranges
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true
```

Troubleshooting order: source → artifact → reconciliation → chart rendering → runtime

## Argo CD

```yaml
# Application - always set project, never use default
spec:
  project: platform          # Never leave as "default"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
```

## AWS IAM

Never generate wildcard policies. Always scope to specific actions and resources:

```json
// ❌ Never generate this
{ "Action": "s3:*", "Resource": "*" }

// ✅ Always generate this
{
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": [
    "arn:aws:s3:::my-bucket",
    "arn:aws:s3:::my-bucket/*"
  ]
}
```

Always prefer IRSA over static credentials for EKS pods:

```hcl
# IAM role for service accounts
resource "aws_iam_role" "pod" {
  assume_role_policy = jsonencode({
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.cluster.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account}"
        }
      }
    }]
  })
}
```

## Azure

Prefer managed identities over service principals. Always use workload identity for AKS pods:

```yaml
# Pod spec for workload identity
metadata:
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: my-app-sa  # Annotated with client-id
```

## Terraform

Module structure:

```
module/
├── main.tf        # Resources
├── variables.tf   # Inputs with validation blocks
├── outputs.tf     # Outputs
├── versions.tf    # Required providers with version constraints
└── README.md      # Usage examples
```

Always include validation in variables:

```hcl
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment must be dev, staging, or production"
  }
}
```

Always enable KMS encryption and CloudWatch logging for EKS clusters.

## GitHub Actions

Always pin actions to SHA, never to mutable tags:

```yaml
# ❌ Never generate this
- uses: actions/checkout@v4

# ✅ Always generate this
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1
```

Always use minimal permissions:

```yaml
permissions:
  contents: read       # Only what is needed
  id-token: write      # Only if OIDC is required
```

Never use `pull_request_target` with code checkout from forks.

## Troubleshooting Response Structure

When asked to debug or troubleshoot, always respond with:

1. **Symptom** - What is observable
2. **Evidence to collect** - Exact commands to run
3. **Root cause** - Why this happens
4. **Fix** - Specific change with justification
5. **Validation** - How to verify it worked
6. **Prevention** - How to avoid in future
7. **Rollback** - How to safely undo

## SOC 2 Compliance (Terraform)

When generating Terraform resources that handle data, always apply SOC 2-relevant controls:

**Encryption at rest — always include:**
```hcl
# S3
resource "aws_s3_bucket_server_side_encryption_configuration" "..." {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

# RDS
resource "aws_db_instance" "..." {
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn
}

# DynamoDB
resource "aws_dynamodb_table" "..." {
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }
  point_in_time_recovery { enabled = true }
}
```

**ECR — always set immutable tags and scan on push:**
```hcl
resource "aws_ecr_repository" "..." {
  image_tag_mutability = "IMMUTABLE"
  encryption_configuration { encryption_type = "KMS" }
  image_scanning_configuration { scan_on_push = true }
}
```

**Never generate:**
- `publicly_accessible = true` on RDS, Redshift, or OpenSearch
- `encrypted = false` on any storage resource
- `skip_final_snapshot = true` on production databases
- `deletion_protection = false` on production databases
- `is_multi_region_trail = false` on CloudTrail
- `enable_log_file_validation = false` on CloudTrail

**KMS — always enable rotation:**
```hcl
resource "aws_kms_key" "..." {
  enable_key_rotation = true   # SOC 2 CC6.7
  deletion_window_in_days = 30
}
```

**Checkov:** Always ensure generated Terraform passes `CKV_AWS_7` (KMS rotation), `CKV_AWS_19` (S3 encryption), `CKV_AWS_16` (RDS encryption), and `CKV_AWS_17` (RDS not public).

**Extended data services — always include these attributes:**

```hcl
# ElastiCache (CC6.7)
resource "aws_elasticache_replication_group" "..." {
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  kms_key_id                 = aws_kms_key.elasticache.arn
}

# OpenSearch (CC6.7)
resource "aws_opensearch_domain" "..." {
  encrypt_at_rest          { enabled = true; kms_key_id = aws_kms_key.opensearch.arn }
  node_to_node_encryption  { enabled = true }
  domain_endpoint_options  { enforce_https = true; tls_security_policy = "Policy-Min-TLS-1-2-2019-07" }
}

# Kinesis (CC6.7)
resource "aws_kinesis_stream" "..." {
  encryption_type = "KMS"
  kms_key_id      = aws_kms_key.kinesis.arn
}

# EFS (CC6.7)
resource "aws_efs_file_system" "..." {
  encrypted  = true
  kms_key_id = aws_kms_key.efs.arn
}

# Redshift (CC6.7)
resource "aws_redshift_cluster" "..." {
  encrypted           = true
  kms_key_id          = aws_kms_key.redshift.arn
  publicly_accessible = false
  enhanced_vpc_routing = true
}
# Always pair with a parameter group enforcing SSL
resource "aws_redshift_parameter_group" "..." {
  parameter { name = "require_ssl"; value = "true" }
}
```

**Network — always include (CC6.6):**

```hcl
# VPC flow logs on every production VPC
resource "aws_flow_log" "..." {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = aws_s3_bucket.flow_logs.arn
}

# WAF on every public-facing ALB or CloudFront distribution
resource "aws_wafv2_web_acl_association" "..." {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
```

**Detection — always enable (CC7.1):**

```hcl
resource "aws_guardduty_detector" "..." {
  enable = true
  datasources {
    s3_logs           { enable = true }
    kubernetes { audit_logs { enable = true } }
  }
}
```

**Audit logging — always include (CC7.2):**

```hcl
resource "aws_cloudtrail" "..." {
  is_multi_region_trail      = true   # Never false
  enable_log_file_validation = true   # Never false
  kms_key_id                 = aws_kms_key.cloudtrail.arn
  include_global_service_events = true
}
```

**Incident response — SNS topics carrying security events must be encrypted (CC7.3):**

```hcl
resource "aws_sns_topic" "security_alerts" {
  kms_master_key_id = aws_kms_key.sns.arn
}
```

**Backup — always include on production data stores (A1.2/A1.3):**

```hcl
# RDS: minimum 35-day retention, deletion protection
resource "aws_db_instance" "..." {
  backup_retention_period = 35
  deletion_protection     = true
  skip_final_snapshot     = false
  multi_az                = true
}

# DynamoDB: always enable PITR
resource "aws_dynamodb_table" "..." {
  point_in_time_recovery { enabled = true }
}
```

**State — always use encrypted remote backend with locking (CC8.1):**

```hcl
terraform {
  backend "s3" {
    encrypt        = true
    kms_key_id     = "arn:aws:kms:..."
    dynamodb_table = "terraform-state-lock"
  }
}
```

**Never generate (extended):**
- `at_rest_encryption_enabled = false` on ElastiCache
- `transit_encryption_enabled = false` on ElastiCache
- `node_to_node_encryption { enabled = false }` on OpenSearch
- `enforce_https = false` on OpenSearch
- `encryption_type = "NONE"` on Kinesis
- `encrypted = false` on EFS
- `enable = false` on GuardDuty
- `is_multi_region_trail = false` on CloudTrail
- `enable_log_file_validation = false` on CloudTrail
- Image references ending in `:latest` in any resource

## Reference Files

For deeper patterns, reference these files in this repository:

- `references/kubernetes.md` — Cluster baselines, RBAC, network policy
- `references/openshift.md` — Routes, SCCs, operators
- `references/flux.md` — GitOps reconciliation, troubleshooting
- `references/argocd.md` — App design, ApplicationSets
- `references/aws.md` — IAM, EKS, account model
- `references/azure.md` — AKS, workload identity, RBAC
- `references/terraform.md` — Module design, state, testing
- `references/github-actions.md` — Workflow security, OIDC
- `references/platform-operating-model.md` — Cross-cutting architecture
- `references/compliance.md` — SOC 2 controls in Terraform, Checkov rules, evidence commands
- `examples/` — Working, production-ready code examples

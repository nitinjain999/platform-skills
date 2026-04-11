# Compliance Reference

Guidance for platform engineers implementing compliance controls in Terraform. This version covers SOC 2 Trust Services Criteria (TSC) — the control mapping, Terraform patterns, Checkov enforcement rules, and evidence collection commands needed for an audit.

---

## SOC 2 and Terraform

SOC 2 audits assess controls against five Trust Services Criteria. For infrastructure teams, the relevant criteria are:

| Criteria | Area | What auditors look for |
|----------|------|------------------------|
| CC6.1 | Logical access | IAM least privilege, no wildcard actions, RBAC |
| CC6.2 | Authentication | MFA, OIDC over static credentials |
| CC6.3 | Access removal | Role assumption, no long-lived keys |
| CC6.6 | Network security | VPC isolation, security groups, private subnets |
| CC6.7 | Encryption | At-rest and in-transit encryption on all data stores |
| CC6.8 | Vulnerability management | IaC scanning in pipeline, image scanning, patching |
| CC7.1 | Detection | GuardDuty, CloudWatch alarms, Security Hub |
| CC7.2 | Audit logging | CloudTrail, VPC flow logs, API access logs |
| CC7.3 | Incident response | GuardDuty → SNS alerting, Config non-compliance notifications |
| CC8.1 | Change management | PR workflow, plan review, state locking |
| A1.1 | Availability | Multi-AZ, RTO/RPO targets |
| A1.2 | Backup | Automated backup plan, 35-day minimum retention |
| A1.3 | Recovery | Backup deletion protection, cross-region copies |

**Approach:** Implement each control once in reusable Terraform modules. Run Checkov in CI to enforce continuously. Export evidence from AWS Config, CloudTrail, and Security Hub for auditors.

---

## CC6.1 — Logical Access Controls

**What the auditor wants:** Proof that IAM permissions follow least privilege. No `*` actions or resources without explicit justification.

### Terraform patterns

```hcl
# ❌ Fails CC6.1 — wildcard action and resource
resource "aws_iam_role_policy" "app" {
  name   = "app-policy"
  role   = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*"
      Resource = "*"
    }]
  })
}

# ✅ Passes CC6.1 — scoped actions and resource ARN
resource "aws_iam_role_policy" "app" {
  name   = "app-s3-read"
  role   = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        "arn:aws:s3:::${var.bucket_name}",
        "arn:aws:s3:::${var.bucket_name}/*"
      ]
    }]
  })
}
```

**IRSA (IAM Roles for Service Accounts) — OIDC, no static keys:**
```hcl
resource "aws_iam_role" "app" {
  name = "app-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${var.account_id}:oidc-provider/${var.oidc_provider}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
```

**SCP to deny IAM privilege escalation (org-level enforcement):**
```hcl
resource "aws_organizations_policy" "deny_privilege_escalation" {
  name        = "deny-iam-privilege-escalation"
  type        = "SERVICE_CONTROL_POLICY"
  description = "Prevent privilege escalation via IAM (SOC 2 CC6.1)"
  content     = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Deny"
      Action = [
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy",
        "iam:PutUserPolicy",
        "iam:CreatePolicyVersion",
        "iam:SetDefaultPolicyVersion",
        "iam:PassRole"
      ]
      Resource = "*"
      Condition = {
        ArnNotLike = {
          "aws:PrincipalARN" = [
            "arn:aws:iam::*:role/platform-admin",
            "arn:aws:iam::*:role/OrganizationAccountAccessRole"
          ]
        }
      }
    }]
  })
}
```

**Checkov rules:**
```
CKV_AWS_40   — IAM user policies should not be attached inline
CKV_AWS_274  — Disallow IAM role with AdministratorAccess policy
CKV_AWS_275  — Disallow IAM role with inline policy containing wildcards
CKV_AWS_1    — Ensure IAM policy does not have Action *
```

**Evidence:**
```bash
# List all policies with wildcard actions attached to roles
aws iam list-policies --scope Local --query 'Policies[].Arn' --output text | \
  tr '\t' '\n' | while read arn; do
    policy=$(aws iam get-policy-version \
      --policy-arn "$arn" \
      --version-id $(aws iam get-policy --policy-arn "$arn" --query 'Policy.DefaultVersionId' --output text) \
      --query 'PolicyVersion.Document' --output json)
    echo "$policy" | jq -r --arg arn "$arn" \
      'if (.Statement[].Action == "*") then "\($arn): WILDCARD ACTION" else empty end'
  done
```

---

## CC6.2 — Authentication

**What the auditor wants:** MFA enforced for human access. No static long-lived credentials for workloads.

### Terraform patterns

**SCP enforcing MFA for console access:**
```hcl
resource "aws_organizations_policy" "require_mfa" {
  name        = "require-mfa-console"
  type        = "SERVICE_CONTROL_POLICY"
  description = "Deny console actions unless MFA is present (SOC 2 CC6.2)"
  content     = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      NotAction = [
        "iam:CreateVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:GetUser",
        "iam:ListMFADevices",
        "iam:ListVirtualMFADevices",
        "sts:GetSessionToken"
      ]
      Resource = "*"
      Condition = {
        BoolIfExists = {
          "aws:MultiFactorAuthPresent" = "false"
        }
      }
    }]
  })
}
```

**Deny creation of IAM access keys (workloads must use OIDC):**
```hcl
resource "aws_organizations_policy" "deny_access_keys" {
  name        = "deny-iam-access-key-creation"
  type        = "SERVICE_CONTROL_POLICY"
  description = "Prevent static access key creation for non-admin roles (SOC 2 CC6.2)"
  content     = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Deny"
      Action   = ["iam:CreateAccessKey"]
      Resource = "*"
      Condition = {
        ArnNotLike = {
          "aws:PrincipalARN" = ["arn:aws:iam::*:role/platform-admin"]
        }
      }
    }]
  })
}
```

**GitHub Actions OIDC (no stored AWS credentials):**
```hcl
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",  # GitHub Actions OIDC thumbprint
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

resource "aws_iam_role" "github_actions_deploy" {
  name = "github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Scope to specific repo and branch
          "token.actions.githubusercontent.com:sub" = "repo:org/platform-infra:ref:refs/heads/main"
        }
      }
    }]
  })
}
```

**Checkov rules:**
```
CKV_AWS_44  — Ensure IAM password policy requires MFA
CKV2_AWS_57 — Ensure IAM user has MFA device enabled
CKV_AWS_9   — Ensure IAM password policy expires passwords
```

**Evidence:**
```bash
# Generate credential report and check for users without MFA
aws iam generate-credential-report
sleep 5
aws iam get-credential-report --query 'Content' --output text | base64 -d | \
  awk -F',' 'NR>1 && $4=="true" && $8=="false" {print "NO MFA: "$1}'

# List access keys older than 90 days (CC6.3: timely access removal)
aws iam list-users --query 'Users[].UserName' --output text | \
  tr '\t' '\n' | while read user; do
    aws iam list-access-keys --user-name "$user" \
      --query "AccessKeyMetadata[?Status=='Active'].{User:$user,Key:AccessKeyId,Created:CreateDate}" \
      --output table
  done
```

---

## CC6.3 — Access Removal

**What the auditor wants:** No long-lived IAM access keys for workloads. Access removed promptly when users offboard. Config rules enforcing key rotation policy.

### Terraform patterns

**AWS Config rule — enforce 90-day access key rotation:**
```hcl
resource "aws_config_config_rule" "access_keys_rotated" {
  name        = "access-keys-rotated"
  description = "Flag IAM access keys not rotated within 90 days (SOC 2 CC6.3)"

  source {
    owner             = "AWS"
    source_identifier = "ACCESS_KEYS_ROTATED"
  }

  input_parameters = jsonencode({
    maxAccessKeyAge = "90"
  })

  depends_on = [aws_config_configuration_recorder.main]
}
```

**SCP preventing access key creation for non-admin principals (workloads must use OIDC):**
```hcl
resource "aws_organizations_policy" "deny_access_keys" {
  name        = "deny-iam-access-key-creation"
  type        = "SERVICE_CONTROL_POLICY"
  description = "Prevent static access key creation — workloads must use OIDC (SOC 2 CC6.3)"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Deny"
      Action   = ["iam:CreateAccessKey"]
      Resource = "*"
      Condition = {
        ArnNotLike = {
          "aws:PrincipalARN" = [
            "arn:aws:iam::*:role/platform-admin",
            "arn:aws:iam::*:role/breakglass-admin"
          ]
        }
      }
    }]
  })
}
```

**IAM Access Analyzer — detect unintended external access grants:**
```hcl
resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "platform-access-analyzer"
  type          = "ACCOUNT"   # Use ORGANIZATION for org-wide scope

  tags = {
    ManagedBy  = "terraform"
    Compliance = "soc2"
  }
}
```

**Checkov rules:**
```
CKV_AWS_9   — Ensure IAM password policy expires passwords within 90 days
CKV2_AWS_21 — Ensure IAM Access Analyzer is enabled for all regions
CKV_AWS_44  — Ensure IAM password policy requires uppercase letters
```

**Evidence:**
```bash
# AWS Config: check access-keys-rotated rule compliance
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name access-keys-rotated \
  --compliance-types NON_COMPLIANT \
  --query 'EvaluationResults[*].{Resource:EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId,Reason:Annotation}' \
  --output table

# Credential report: list access keys older than 90 days
aws iam generate-credential-report && sleep 5
aws iam get-credential-report --query 'Content' --output text | base64 -d | \
  awk -F',' 'NR>1 && ($9!="N/A" || $14!="N/A") {print $1, $9, $14}' | \
  awk '{if ($2!="N/A" && $2 < strftime("%Y-%m-%dT%H:%M:%S", systime()-90*86400)) print "STALE KEY1: "$1; if ($3!="N/A" && $3 < strftime("%Y-%m-%dT%H:%M:%S", systime()-90*86400)) print "STALE KEY2: "$1}'

# IAM Access Analyzer: active findings (unintended external access)
aws accessanalyzer list-findings \
  --analyzer-arn $(aws accessanalyzer list-analyzers --query 'analyzers[0].arn' --output text) \
  --filter '{"status": {"eq": ["ACTIVE"]}}' \
  --query 'findings[*].{Resource:resource,Type:resourceType,Principal:principal}' \
  --output table
```

---

## CC6.6 — Network Security

**What the auditor wants:** Workloads in private subnets. Security groups with minimum required ports. No `0.0.0.0/0` ingress except on load balancers.

### Terraform patterns

```hcl
# ❌ Fails CC6.6 — SSH open to the internet
resource "aws_security_group_rule" "ssh" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]   # Finding: unrestricted SSH
  security_group_id = aws_security_group.app.id
}

# ✅ Passes CC6.6 — SSH restricted to VPN CIDR
resource "aws_security_group_rule" "ssh" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [var.vpn_cidr]   # Only reachable via VPN
  security_group_id = aws_security_group.app.id
  description = "SSH from VPN only (SOC 2 CC6.6)"
}
```

**VPC with private subnets and VPC flow logs:**
```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "production" })
}

# Flow logs to S3 for SOC 2 CC7.2 (audit logging)
resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_s3_bucket.flow_logs.arn
  log_destination_type = "s3"

  log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status}"
}

# Private subnets — no direct internet route
resource "aws_subnet" "private" {
  for_each = var.availability_zones

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 4, each.value.index + 10)
  availability_zone       = each.value.az
  map_public_ip_on_launch = false   # Explicitly no public IP on launch

  tags = merge(local.common_tags, { Name = "private-${each.value.az}", Tier = "private" })
}
```

**Checkov rules:**
```
CKV_AWS_25   — Ensure no security groups allow ingress 0.0.0.0/0 to port 22
CKV_AWS_24   — Ensure no security groups allow ingress 0.0.0.0/0 to port 3389
CKV_AWS_260  — Ensure no security groups allow ingress 0.0.0.0/0 to port 80
CKV2_AWS_12  — Ensure VPC flow logs are enabled
CKV2_AWS_11  — Ensure VPC has a default security group that does not allow inbound/outbound traffic
CKV_AWS_148  — Ensure EKS node groups are deployed in private subnets
```

**WAF — application-layer network protection (CC6.6):**
```hcl
resource "aws_wafv2_web_acl" "main" {
  name  = "production-waf"
  scope = "REGIONAL"   # Use "CLOUDFRONT" for CloudFront distributions

  default_action {
    allow {}
  }

  # Block requests exceeding 1000 per 5 minutes from a single IP
  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  # AWS managed rule group: common vulnerabilities (SQLi, XSS)
  rule {
    name     = "aws-managed-common-rules"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedCommonRules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "ProductionWAF"
    sampled_requests_enabled   = true
  }

  tags = local.common_tags
}

# Associate WAF with ALB
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
```

**Checkov rules (CC6.6):**
```
CKV_AWS_25   — Ensure no security groups allow ingress 0.0.0.0/0 to port 22
CKV_AWS_24   — Ensure no security groups allow ingress 0.0.0.0/0 to port 3389
CKV_AWS_260  — Ensure no security groups allow ingress 0.0.0.0/0 to port 80
CKV2_AWS_12  — Ensure VPC flow logs are enabled
CKV2_AWS_11  — Ensure VPC has a default security group that restricts all traffic
CKV_AWS_148  — Ensure EKS node groups are deployed in private subnets
CKV2_AWS_31  — Ensure WAF2 has a logging configuration
```

**Evidence:**
```bash
# Security groups with unrestricted ingress
aws ec2 describe-security-groups \
  --query "SecurityGroups[?IpPermissions[?IpRanges[?CidrIp=='0.0.0.0/0']]].{ID:GroupId,Name:GroupName,VPC:VpcId}" \
  --output table

# Verify VPC flow logs enabled on all VPCs
aws ec2 describe-vpcs --query 'Vpcs[].VpcId' --output text | \
  tr '\t' '\n' | while read vpc; do
    logs=$(aws ec2 describe-flow-logs \
      --filter "Name=resource-id,Values=$vpc" \
      --query 'FlowLogs[].FlowLogId' --output text)
    [ -z "$logs" ] && echo "NO FLOW LOGS: $vpc" || echo "OK: $vpc ($logs)"
  done

# WAF ACLs associated with ALBs
aws wafv2 list-web-acls --scope REGIONAL \
  --query 'WebACLs[*].{Name:Name,ARN:ARN}' --output table
```

---

## CC6.7 — Encryption

**What the auditor wants:** Data encrypted at rest and in transit. No unencrypted storage, databases, or queues. TLS enforced on all endpoints.

### Terraform patterns

**S3 — enforce encryption and block public access:**
```hcl
resource "aws_s3_bucket" "data" {
  bucket = var.bucket_name
  tags   = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true  # Reduces KMS API call cost
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Deny unencrypted uploads
resource "aws_s3_bucket_policy" "data" {
  bucket = aws_s3_bucket.data.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.data.arn}/*"
      Condition = {
        StringNotEquals = {
          "s3:x-amz-server-side-encryption" = "aws:kms"
        }
      }
    }]
  })
}
```

**RDS — encryption at rest:**
```hcl
resource "aws_db_instance" "main" {
  identifier        = "production-db"
  engine            = "postgres"
  engine_version    = "15.4"
  instance_class    = "db.t3.medium"
  storage_encrypted = true          # Fails CC6.7 if false
  kms_key_id        = aws_kms_key.rds.arn
  multi_az          = true          # Supports A1.1 (availability)

  backup_retention_period = 30      # 30-day backups for A1.1
  deletion_protection     = true    # Prevent accidental deletion

  tags = local.common_tags
}
```

**EBS default encryption (account-level):**
```hcl
resource "aws_ebs_encryption_by_default" "main" {
  enabled = true
}

resource "aws_ebs_default_kms_key" "main" {
  key_arn = aws_kms_key.ebs.arn
}
```

**Checkov rules:**
```
CKV_AWS_19   — Ensure S3 bucket has server-side encryption enabled
CKV_AWS_18   — Ensure S3 bucket has access logging enabled
CKV_AWS_21   — Ensure S3 bucket versioning is enabled
CKV_AWS_53   — Ensure S3 bucket has block public ACLS enabled
CKV_AWS_54   — Ensure S3 bucket has block public policy enabled
CKV_AWS_17   — Ensure RDS is not publicly accessible
CKV_AWS_16   — Ensure RDS is encrypted at rest
CKV_AWS_211  — Ensure RDS uses a modern CaCert
CKV2_AWS_6   — Ensure S3 bucket has public access block enabled
CKV_AWS_7    — Ensure KMS key rotation is enabled
```

**Evidence:**
```bash
# Unencrypted RDS instances
aws rds describe-db-instances \
  --query 'DBInstances[?StorageEncrypted==`false`].{ID:DBInstanceIdentifier,Engine:Engine}' \
  --output table

# Unencrypted EBS volumes
aws ec2 describe-volumes \
  --filters Name=encrypted,Values=false \
  --query 'Volumes[*].{ID:VolumeId,State:State,AZ:AvailabilityZone}' \
  --output table

# S3 buckets missing encryption
aws s3api list-buckets --query 'Buckets[].Name' --output text | \
  tr '\t' '\n' | while read bucket; do
    enc=$(aws s3api get-bucket-encryption --bucket "$bucket" 2>&1)
    echo "$enc" | grep -q "ServerSideEncryptionConfigurationNotFoundError" && echo "NOT ENCRYPTED: $bucket"
  done

# KMS keys without rotation
aws kms list-keys --query 'Keys[].KeyId' --output text | \
  tr '\t' '\n' | while read key; do
    rotation=$(aws kms get-key-rotation-status --key-id "$key" --query 'KeyRotationEnabled' --output text 2>/dev/null)
    [ "$rotation" = "False" ] && echo "NO ROTATION: $key"
  done
```

### CC6.7 — Extended: data service encryption

Many SOC 2 audits fail on data services beyond S3 and RDS. Cover every data store.

**DynamoDB:**
```hcl
resource "aws_dynamodb_table" "main" {
  name         = "production-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  # AWS-owned CMK is free; use aws:kms for customer-managed key
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true   # Supports A1.2: continuous backup
  }

  tags = local.common_tags
}
```

**ECR — image encryption + scan on push:**
```hcl
resource "aws_ecr_repository" "app" {
  name                 = "app"
  image_tag_mutability = "IMMUTABLE"   # Prevents tag overwrite (CC6.8)

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  image_scanning_configuration {
    scan_on_push = true   # Triggers vulnerability scan on every push (CC6.8)
  }

  tags = local.common_tags
}

# Lifecycle policy: clean up untagged images older than 14 days
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Remove untagged images after 14 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 14
      }
      action = { type = "expire" }
    }]
  })
}
```

**ElastiCache (Redis):**
```hcl
resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "production-redis"
  description          = "Production Redis cluster"
  node_type            = "cache.t3.medium"
  num_cache_clusters   = 2

  at_rest_encryption_enabled  = true   # CC6.7: data at rest
  transit_encryption_enabled  = true   # CC6.7: data in transit
  kms_key_id                  = aws_kms_key.elasticache.arn
  auth_token                  = var.redis_auth_token   # Required when transit_encryption_enabled = true

  automatic_failover_enabled = true   # A1.1: HA
  multi_az_enabled           = true

  tags = local.common_tags
}
```

**OpenSearch:**
```hcl
resource "aws_opensearch_domain" "main" {
  domain_name    = "production-search"
  engine_version = "OpenSearch_2.11"

  encrypt_at_rest {
    enabled    = true
    kms_key_id = aws_kms_key.opensearch.arn
  }

  node_to_node_encryption {
    enabled = true   # CC6.7: in-transit between cluster nodes
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  cluster_config {
    instance_count         = 3
    zone_awareness_enabled = true   # A1.1: multi-AZ

    zone_awareness_config {
      availability_zone_count = 3
    }
  }

  tags = local.common_tags
}
```

**Kinesis Data Stream:**
```hcl
resource "aws_kinesis_stream" "main" {
  name             = "production-events"
  shard_count      = 2
  retention_period = 168   # 7-day retention (default is 24h)

  encryption_type = "KMS"
  kms_key_id      = aws_kms_key.kinesis.arn

  tags = local.common_tags
}
```

**EFS:**
```hcl
resource "aws_efs_file_system" "main" {
  encrypted        = true
  kms_key_id       = aws_kms_key.efs.arn
  performance_mode = "generalPurpose"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = local.common_tags
}
```

**Redshift:**
```hcl
resource "aws_redshift_cluster" "main" {
  cluster_identifier = "production-dw"
  node_type          = "dc2.large"
  number_of_nodes    = 2
  database_name      = "analytics"

  encrypted  = true
  kms_key_id = aws_kms_key.redshift.arn

  publicly_accessible       = false   # CC6.6
  enhanced_vpc_routing      = true    # Forces traffic through VPC

  automated_snapshot_retention_period = 35   # A1.2: 35-day retention

  tags = local.common_tags
}

# Enforce SSL connections (CC6.7: encryption in transit)
resource "aws_redshift_parameter_group" "ssl" {
  name   = "production-ssl"
  family = "redshift-1.0"

  parameter {
    name  = "require_ssl"
    value = "true"
  }
}
```

**Checkov rules (CC6.7 — extended data services):**
```
CKV_AWS_119  — Ensure DynamoDB point-in-time recovery is enabled
CKV_AWS_28   — Ensure DynamoDB is encrypted with a KMS CMK
CKV_AWS_163  — Ensure ECR image tags are immutable
CKV_AWS_136  — Ensure ECR is encrypted with a KMS CMK
CKV_AWS_8    — Ensure ECR image scanning on push is enabled
CKV_AWS_65   — Ensure ECR image scanning is enabled
CKV_AWS_29   — Ensure ElastiCache is encrypted at rest
CKV_AWS_30   — Ensure ElastiCache has transit encryption enabled
CKV_AWS_31   — Ensure ElastiCache transit encryption uses an auth token
CKV_AWS_191  — Ensure ElastiCache is encrypted at rest with a KMS CMK
CKV_AWS_5    — Ensure OpenSearch is encrypted at rest
CKV_AWS_6    — Ensure OpenSearch encrypts node-to-node traffic
CKV_AWS_83   — Ensure OpenSearch enforces HTTPS
CKV_AWS_228  — Ensure OpenSearch uses a current TLS policy
CKV_AWS_247  — Ensure OpenSearch is encrypted with a KMS CMK
CKV_AWS_186  — Ensure Kinesis stream is encrypted with a KMS CMK
CKV_AWS_42   — Ensure EFS is encrypted at rest
CKV_AWS_87   — Ensure Redshift is not publicly accessible
CKV_AWS_64   — Ensure Redshift cluster is encrypted at rest
CKV_AWS_105  — Ensure Redshift requires SSL connections
CKV_AWS_142  — Ensure Redshift cluster is encrypted with KMS
CKV_AWS_321  — Ensure Redshift uses enhanced VPC routing
```

**Evidence (data services encryption summary):**
```bash
# DynamoDB tables without encryption
aws dynamodb list-tables --query 'TableNames[]' --output text | \
  tr '\t' '\n' | while read t; do
    enc=$(aws dynamodb describe-table --table-name "$t" \
      --query 'Table.SSEDescription.Status' --output text)
    [ "$enc" != "ENABLED" ] && echo "NOT ENCRYPTED: $t"
  done

# ElastiCache clusters without encryption
aws elasticache describe-replication-groups \
  --query 'ReplicationGroups[?AtRestEncryptionEnabled==`false` || TransitEncryptionEnabled==`false`].{ID:ReplicationGroupId,AtRest:AtRestEncryptionEnabled,Transit:TransitEncryptionEnabled}' \
  --output table

# OpenSearch domains without node-to-node encryption
aws opensearch list-domain-names --query 'DomainNames[].DomainName' --output text | \
  tr '\t' '\n' | while read d; do
    n2n=$(aws opensearch describe-domain --domain-name "$d" \
      --query 'DomainStatus.NodeToNodeEncryptionOptions.Enabled' --output text)
    [ "$n2n" = "False" ] && echo "NO N2N ENCRYPTION: $d"
  done

# Kinesis streams without KMS encryption
aws kinesis list-streams --query 'StreamNames[]' --output text | \
  tr '\t' '\n' | while read s; do
    enc=$(aws kinesis describe-stream-summary --stream-name "$s" \
      --query 'StreamDescriptionSummary.EncryptionType' --output text)
    [ "$enc" != "KMS" ] && echo "NOT ENCRYPTED: $s ($enc)"
  done
```

---

## CC6.8 — Vulnerability Management

**What the auditor wants:** Automated scanning of container images and IaC before deployment. Evidence of a patching cadence for EC2 workloads.

### Terraform patterns

**ECR image scanning (automatic on push):**
```hcl
# Registry-level scanning policy — applies to all repositories in the account
resource "aws_ecr_registry_scanning_configuration" "main" {
  scan_type = "ENHANCED"   # Uses Inspector v2 for deeper CVE analysis

  rule {
    scan_frequency = "CONTINUOUS_SCAN"   # Re-scan on new CVE publication

    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }
}
```

**AWS Inspector v2 — EC2, Lambda, and ECR scanning:**
```hcl
resource "aws_inspector2_enabler" "main" {
  account_ids    = [var.account_id]
  resource_types = ["ECR", "EC2", "LAMBDA"]
}

# Export Inspector findings to Security Hub automatically
# (enabled by default when both services are active)
```

**SSM Patch Baseline — automated patching for EC2:**
```hcl
resource "aws_ssm_patch_baseline" "amazon_linux" {
  name            = "production-amazon-linux-2"
  operating_system = "AMAZON_LINUX_2"
  description     = "Production patching baseline — security patches auto-approved after 7 days"

  approval_rule {
    approve_after_days  = 7
    compliance_level    = "CRITICAL"
    enable_non_security = false

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  tags = local.common_tags
}

resource "aws_ssm_maintenance_window" "patching" {
  name     = "production-patching"
  schedule = "cron(0 2 ? * SUN *)"   # Every Sunday at 02:00 UTC
  duration = 3
  cutoff   = 1

  tags = local.common_tags
}
```

**Checkov rules (CC6.8):**
```
CKV_AWS_8    — Ensure ECR image scanning on push is enabled
CKV_AWS_65   — Ensure ECR image scanning is enabled
CKV_AWS_163  — Ensure ECR image tags are immutable
CKV_AWS_50   — Ensure X-Ray tracing is enabled for Lambda (visibility)
```

**Evidence:**
```bash
# Inspector v2: active findings by severity
aws inspector2 list-findings \
  --filter-criteria '{"findingStatus":[{"comparison":"EQUALS","value":"ACTIVE"}]}' \
  --query 'findings[*].{Severity:severity,Title:title,Resource:resources[0].id}' \
  --output table

# ECR: repositories without scan on push
aws ecr describe-repositories \
  --query 'repositories[?imageScanningConfiguration.scanOnPush==`false`].repositoryName' \
  --output table

# SSM: EC2 instances with patch compliance status
aws ssm describe-instance-patch-states \
  --query 'InstancePatchStates[*].{ID:InstanceId,Missing:MissingCount,Failed:FailedCount,Installed:InstalledCount}' \
  --output table
```

---

## CC7.1 — Detection and Monitoring

**What the auditor wants:** Active threat detection across the account. CloudWatch alarms on security-relevant API calls. Evidence that alerts are wired to a human response path.

### Terraform patterns

**GuardDuty — account-level threat detection:**
```hcl
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true   # Detect S3 data exfiltration
    }
    kubernetes {
      audit_logs {
        enable = true   # Detect suspicious EKS API calls
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = local.common_tags
}

# GuardDuty findings → SNS → PagerDuty / Slack (CC7.3)
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "guardduty-high-severity"
  description = "Route HIGH and CRITICAL GuardDuty findings to SNS"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]   # HIGH (7.0+) and CRITICAL (9.0+)
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "GuardDutyToSNS"
  arn       = aws_sns_topic.security_alerts.arn
}
```

**CloudWatch alarms on security-relevant API calls (CIS Benchmark 3.x):**
```hcl
locals {
  # CIS Benchmark 3.1–3.14 — metric filters + alarms
  cis_alarms = {
    "unauthorized-api-calls" = {
      pattern = "{ ($.errorCode = \"*UnauthorizedAccess*\") || ($.errorCode = \"AccessDenied*\") }"
      description = "CIS 3.1 — Unauthorized API calls"
    }
    "console-signin-without-mfa" = {
      pattern = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") }"
      description = "CIS 3.2 — Console login without MFA"
    }
    "root-account-usage" = {
      pattern = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
      description = "CIS 3.3 — Root account usage"
    }
    "iam-policy-changes" = {
      pattern = "{ ($.eventName = DeleteGroupPolicy) || ($.eventName = DeleteRolePolicy) || ($.eventName = DeleteUserPolicy) || ($.eventName = PutGroupPolicy) || ($.eventName = PutRolePolicy) || ($.eventName = PutUserPolicy) || ($.eventName = CreatePolicy) || ($.eventName = DeletePolicy) || ($.eventName = CreatePolicyVersion) || ($.eventName = DeletePolicyVersion) || ($.eventName = SetDefaultPolicyVersion) }"
      description = "CIS 3.4 — IAM policy changes"
    }
    "cloudtrail-config-changes" = {
      pattern = "{ ($.eventName = CreateTrail) || ($.eventName = UpdateTrail) || ($.eventName = DeleteTrail) || ($.eventName = StartLogging) || ($.eventName = StopLogging) }"
      description = "CIS 3.5 — CloudTrail config changes"
    }
    "s3-bucket-policy-changes" = {
      pattern = "{ ($.eventSource = s3.amazonaws.com) && (($.eventName = PutBucketAcl) || ($.eventName = PutBucketPolicy) || ($.eventName = PutBucketCors) || ($.eventName = PutBucketLifecycle) || ($.eventName = PutBucketReplication) || ($.eventName = DeleteBucketPolicy) || ($.eventName = DeleteBucketCors) || ($.eventName = DeleteBucketLifecycle) || ($.eventName = DeleteBucketReplication)) }"
      description = "CIS 3.8 — S3 bucket policy changes"
    }
    "security-group-changes" = {
      pattern = "{ ($.eventName = AuthorizeSecurityGroupIngress) || ($.eventName = AuthorizeSecurityGroupEgress) || ($.eventName = RevokeSecurityGroupIngress) || ($.eventName = RevokeSecurityGroupEgress) || ($.eventName = CreateSecurityGroup) || ($.eventName = DeleteSecurityGroup) }"
      description = "CIS 3.10 — Security group changes"
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "cis" {
  for_each       = local.cis_alarms
  name           = each.key
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = each.value.pattern

  metric_transformation {
    name      = each.key
    namespace = "SOC2/CISBenchmark"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "cis" {
  for_each            = local.cis_alarms
  alarm_name          = each.key
  alarm_description   = each.value.description
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = each.key
  namespace           = "SOC2/CISBenchmark"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.security_alerts.arn]

  tags = local.common_tags
}
```

**Security Hub — aggregate findings from all sources:**
```hcl
resource "aws_securityhub_account" "main" {
  enable_default_standards = false   # Enable only the standards you need
}

resource "aws_securityhub_standards_subscription" "aws_foundational" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

resource "aws_securityhub_standards_subscription" "cis" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.region}::standards/cis-aws-foundations-benchmark/v/1.4.0"
}
```

**Checkov rules (CC7.1):**
```
CKV_AWS_86   — Ensure CloudFront distribution has Access Logging enabled
CKV2_AWS_35  — Ensure GuardDuty is enabled
CKV_AWS_193  — Ensure GuardDuty has S3 logs enabled
```

**Evidence:**
```bash
# GuardDuty status across all regions
for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  status=$(aws guardduty list-detectors --region "$region" \
    --query 'DetectorIds' --output text 2>/dev/null)
  [ -z "$status" ] && echo "GUARDDUTY DISABLED: $region" || echo "OK: $region ($status)"
done

# CloudWatch alarms in ALARM state (active security events)
aws cloudwatch describe-alarms \
  --state-value ALARM \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue,Reason:StateReason}' \
  --output table

# Security Hub: FAILED controls by severity
aws securityhub get-findings \
  --filters '{"ComplianceStatus":[{"Value":"FAILED","Comparison":"EQUALS"}],"SeverityLabel":[{"Value":"CRITICAL","Comparison":"EQUALS"}]}' \
  --query 'Findings[*].{Title:Title,Resource:Resources[0].Id}' \
  --output table
```

---

## CC7.2 — Audit Logging

**What the auditor wants:** An immutable, tamper-evident log of all API activity across the account. CloudTrail enabled in all regions with log file validation. VPC flow logs capturing network traffic. Logs retained for at least one year.

### Terraform patterns

**CloudTrail — multi-region, log file validation, KMS encryption:**
```hcl
resource "aws_cloudtrail" "main" {
  name                          = "platform-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true    # IAM, STS, Route 53
  is_multi_region_trail         = true    # All regions in one trail
  enable_log_file_validation    = true    # Detect log tampering
  kms_key_id                    = var.cloudtrail_kms_key_arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cw.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    # Log all S3 object-level events for audit evidence
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }
  }

  tags = {
    ManagedBy  = "terraform"
    Compliance = "soc2"
  }
}
```

**S3 log bucket with object lock (immutable audit trail):**
```hcl
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket              = "cloudtrail-logs-${var.account_id}-${var.region}"
  force_destroy       = false
  object_lock_enabled = true   # Required for object lock configuration

  tags = {
    ManagedBy  = "terraform"
    Compliance = "soc2"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 365   # A1.2: 1-year minimum for audit evidence
    }
  }
}
```

**VPC flow logs to S3:**
```hcl
resource "aws_flow_log" "main" {
  log_destination      = "${aws_s3_bucket.cloudtrail_logs.arn}/vpc-flow-logs/"
  log_destination_type = "s3"
  traffic_type         = "ALL"   # ACCEPT, REJECT, and ALL traffic
  vpc_id               = var.vpc_id

  log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status}"

  tags = {
    ManagedBy  = "terraform"
    Compliance = "soc2"
  }
}
```

**AWS Config rules for audit logging compliance:**
```hcl
locals {
  audit_config_rules = {
    "cloudtrail-enabled"             = { source = "CLOUD_TRAIL_ENABLED" }
    "cloudtrail-log-validation"      = { source = "CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED" }
    "multi-region-cloudtrail"        = { source = "MULTI_REGION_CLOUD_TRAIL_ENABLED" }
    "vpc-flow-logs-enabled"          = { source = "VPC_FLOW_LOGS_ENABLED" }
    "s3-bucket-logging-enabled"      = { source = "S3_BUCKET_LOGGING_ENABLED" }
  }
}

resource "aws_config_config_rule" "audit_logging" {
  for_each    = local.audit_config_rules
  name        = each.key
  description = "SOC 2 CC7.2 audit logging: ${each.key}"

  source {
    owner             = "AWS"
    source_identifier = each.value.source
  }

  depends_on = [aws_config_configuration_recorder.main]
}
```

**Checkov rules:**
```
CKV_AWS_67   — Ensure CloudTrail log file validation is enabled
CKV_AWS_35   — Ensure CloudTrail logs are encrypted using KMS CMK
CKV_AWS_36   — Ensure CloudTrail log bucket access logging is enabled
CKV2_AWS_10  — Ensure CloudTrail trails are integrated with CloudWatch Logs
CKV2_AWS_1   — Ensure that API Gateway stage has logging enabled
CKV_AWS_92   — Ensure the S3 bucket has access logging enabled
```

**Evidence:**
```bash
# Verify CloudTrail is enabled in all regions
aws cloudtrail describe-trails --include-shadow-trails \
  --query 'trailList[*].{Name:Name,MultiRegion:IsMultiRegionTrail,Validation:LogFileValidationEnabled,KMS:KMSKeyId}' \
  --output table

# Confirm CloudTrail logging status (must be LOGGING)
aws cloudtrail get-trail-status --name platform-cloudtrail \
  --query '{IsLogging:IsLogging,LastDelivery:LatestDeliveryTime,LastDigestDelivery:LatestDigestDeliveryTime}' \
  --output table

# VPC flow logs enabled per VPC
aws ec2 describe-flow-logs \
  --query 'FlowLogs[*].{VPC:ResourceId,Destination:LogDestination,Status:FlowLogStatus}' \
  --output table

# Config rules: audit logging compliance
aws configservice get-compliance-summary-by-config-rule \
  --query 'ComplianceSummariesByConfigRule[?contains(ConfigRuleName,`cloudtrail`) || contains(ConfigRuleName,`flow-log`)]' \
  --output table
```

---

## CC7.3 — Incident Response

**What the auditor wants:** A defined path from detection (GuardDuty / CloudWatch alarm) to human notification and documented response procedure.

### Terraform patterns

**SNS topic for security alerts — fan-out to email, PagerDuty, Slack:**
```hcl
resource "aws_sns_topic" "security_alerts" {
  name              = "security-alerts"
  kms_master_key_id = aws_kms_key.sns.arn   # CC6.7: encrypt topic messages

  tags = local.common_tags
}

# Email subscription (auditor-visible, immutable record)
resource "aws_sns_topic_subscription" "security_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}

# PagerDuty / Opsgenie via HTTPS endpoint
resource "aws_sns_topic_subscription" "pagerduty" {
  topic_arn              = aws_sns_topic.security_alerts.arn
  protocol               = "https"
  endpoint               = var.pagerduty_integration_url
  endpoint_auto_confirms = true
}
```

**Config non-compliance → SNS notification:**
```hcl
resource "aws_config_delivery_channel" "main" {
  name           = "compliance-channel"
  s3_bucket_name = aws_s3_bucket.config_logs.id
  sns_topic_arn  = aws_sns_topic.security_alerts.arn   # Alert on config changes

  snapshot_delivery_properties {
    delivery_frequency = "Six_Hours"
  }

  depends_on = [aws_config_configuration_recorder.main]
}
```

**Checkov rules (CC7.3):**
```
CKV_AWS_26   — Ensure SNS topic is encrypted at rest using KMS
```

**Evidence:**
```bash
# SNS topics and their subscriptions
aws sns list-topics --query 'Topics[].TopicArn' --output text | \
  tr '\t' '\n' | while read arn; do
    subs=$(aws sns list-subscriptions-by-topic --topic-arn "$arn" \
      --query 'Subscriptions[*].{Protocol:Protocol,Endpoint:Endpoint}' --output table)
    echo "=== $arn ==="; echo "$subs"
  done

# EventBridge rules routing GuardDuty findings
aws events list-rules \
  --query 'Rules[*].{Name:Name,State:State,Pattern:EventPattern}' \
  --output table
```

---

## A1.2 / A1.3 — Backup and Recovery

**What the auditor wants:** Automated backup plan covering all production data stores with a minimum 35-day retention period, deletion protection on backups, and evidence that recovery has been tested.

### Terraform patterns

**AWS Backup plan — centralised backup for all data services:**
```hcl
resource "aws_backup_vault" "main" {
  name        = "production-backup-vault"
  kms_key_arn = aws_kms_key.backup.arn   # CC6.7: encrypted backups

  tags = local.common_tags
}

# Vault lock: prevent deletion of backups for 35 days minimum (A1.3)
resource "aws_backup_vault_lock_configuration" "main" {
  backup_vault_name   = aws_backup_vault.main.name
  min_retention_days  = 35
  max_retention_days  = 365
  changeable_for_days = 3   # Lock becomes permanent after 3 days
}

resource "aws_backup_plan" "main" {
  name = "production-backup-plan"

  rule {
    rule_name         = "daily-35-day-retention"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 * * ? *)"   # Daily at 03:00 UTC

    lifecycle {
      delete_after = 35   # A1.2: minimum 35-day retention
    }

    recovery_point_tags = local.common_tags
  }

  rule {
    rule_name         = "monthly-1-year-retention"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 1 * ? *)"   # First of each month

    lifecycle {
      cold_storage_after = 30    # Move to cold storage after 30 days
      delete_after       = 365   # Keep monthly snapshots for 1 year
    }

    # Cross-region copy for disaster recovery (A1.3)
    copy_action {
      destination_vault_arn = "arn:aws:backup:us-east-1:${var.account_id}:backup-vault:dr-backup-vault"

      lifecycle {
        delete_after = 35
      }
    }

    recovery_point_tags = local.common_tags
  }

  tags = local.common_tags
}

# Backup selection — cover all tagged production resources
resource "aws_backup_selection" "main" {
  name         = "production-resources"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "environment"
    value = "production"
  }

  # Explicitly include resource types that support AWS Backup
  resources = ["*"]
}

resource "aws_iam_role" "backup" {
  name = "aws-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}
```

**Checkov rules (A1.2 / A1.3):**
```
CKV_AWS_166  — Ensure Backup Vault is encrypted at rest using KMS CMK
CKV_AWS_133  — Ensure RDS cluster has backup retention of at least 35 days
CKV_AWS_157  — Ensure RDS has multi-AZ enabled
CKV_AWS_119  — Ensure DynamoDB point-in-time recovery is enabled
```

**Evidence:**
```bash
# Backup jobs completed in the last 7 days
aws backup list-backup-jobs \
  --by-state COMPLETED \
  --by-created-after "$(date -v-7d '+%Y-%m-%dT00:00:00Z')" \
  --query 'BackupJobs[*].{Resource:ResourceArn,Vault:BackupVaultName,Completed:CompletionDate,Size:BackupSizeInBytes}' \
  --output table

# Backup vault lock status
aws backup describe-backup-vault --backup-vault-name production-backup-vault \
  --query '{Locked:Locked,MinDays:MinRetentionDays,MaxDays:MaxRetentionDays}' \
  --output table

# Resources not covered by any backup plan
aws backup list-protected-resources \
  --query 'Results[*].{Type:ResourceType,ARN:ResourceArn,LastBackup:LastBackupTime}' \
  --output table

# Test restore job (run quarterly, document the result)
aws backup start-restore-job \
  --recovery-point-arn <recovery-point-arn> \
  --iam-role-arn arn:aws:iam::${ACCOUNT_ID}:role/aws-backup-role \
  --metadata '{}'
```

---

**What the auditor wants:** CloudTrail enabled in all regions, log file validation on, logs immutable and retained for at least 1 year.

### Terraform patterns

```hcl
resource "aws_cloudtrail" "compliance" {
  name                          = "compliance-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true                # Required for SOC 2
  enable_log_file_validation    = true                # Tamper detection
  kms_key_id                    = aws_kms_key.cloudtrail.arn

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    # Log S3 data events (reads and writes) — required for HIPAA, PCI
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }
  }

  tags = local.common_tags
}

# Immutable S3 bucket for CloudTrail logs (1-year retention)
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    id     = "compliance-retention"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    expiration {
      days = 2555  # 7 years for long-term compliance
    }
  }
}

# Object lock prevents deletion during retention period
resource "aws_s3_bucket_object_lock_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 365
    }
  }
}
```

**AWS Config for continuous compliance monitoring:**
```hcl
resource "aws_config_configuration_recorder" "main" {
  name     = "compliance-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "compliance-channel"
  s3_bucket_name = aws_s3_bucket.config_logs.id
  depends_on     = [aws_config_configuration_recorder.main]
}

# Managed rules covering SOC 2 criteria
locals {
  config_rules = {
    "cloudtrail-enabled"             = { source = "CLOUD_TRAIL_ENABLED" }             # CC7.2
    "cloudtrail-log-validation"      = { source = "CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED" } # CC7.2
    "multi-region-cloudtrail"        = { source = "MULTI_REGION_CLOUD_TRAIL_ENABLED" } # CC7.2
    "mfa-enabled-for-console"        = { source = "MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS" } # CC6.2
    "access-keys-rotated"            = { source = "ACCESS_KEYS_ROTATED" }             # CC6.3
    "root-account-mfa"               = { source = "ROOT_ACCOUNT_MFA_ENABLED" }        # CC6.2
    "encrypted-volumes"              = { source = "ENCRYPTED_VOLUMES" }               # CC6.7
    "rds-storage-encrypted"          = { source = "RDS_STORAGE_ENCRYPTED" }           # CC6.7
    "s3-bucket-public-read"          = { source = "S3_BUCKET_PUBLIC_READ_PROHIBITED" } # CC6.6
    "s3-bucket-public-write"         = { source = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED" } # CC6.6
    "vpc-flow-logs-enabled"          = { source = "VPC_FLOW_LOGS_ENABLED" }           # CC7.2
    "restricted-ssh"                 = { source = "INCOMING_SSH_DISABLED" }            # CC6.6
    "restricted-rdp"                 = { source = "RESTRICTED_INCOMING_TRAFFIC", params = { blockedPort1 = "3389" } } # CC6.6
  }
}

resource "aws_config_config_rule" "soc2" {
  for_each = local.config_rules

  name = each.key
  source {
    owner             = "AWS"
    source_identifier = each.value.source
  }

  depends_on = [aws_config_configuration_recorder.main]
}
```

**Checkov rules:**
```
CKV_AWS_36   — Ensure CloudTrail log file validation is enabled
CKV_AWS_35   — Ensure CloudTrail logs are encrypted using KMS CMK
CKV_AWS_67   — Ensure CloudTrail is enabled in all regions (is_multi_region_trail)
CKV2_AWS_10  — Ensure CloudTrail trails are integrated with CloudWatch Logs
CKV_AWS_91   — Ensure S3 bucket has access logging enabled
CKV_AWS_71   — Ensure Redshift cluster logging is enabled
CKV_AWS_84   — Ensure OpenSearch logging is enabled
```

**Evidence:**
```bash
# Verify CloudTrail is enabled and logging in all regions
aws cloudtrail describe-trails --include-shadow-trails \
  --query 'trailList[*].{Name:Name,MultiRegion:IsMultiRegionTrail,LogValidation:LogFileValidationEnabled,Logging:HasCustomEventSelectors}' \
  --output table

# CloudTrail: who created or deleted IAM roles in the last 30 days
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateRole \
  --start-time "$(date -v-30d '+%Y-%m-%dT00:00:00Z')" \
  --query 'Events[*].{Time:EventTime,User:Username,Role:Resources[0].ResourceName}' \
  --output table

# AWS Config: non-compliant resources across all rules
aws configservice describe-compliance-by-config-rule \
  --compliance-types NON_COMPLIANT \
  --query 'ComplianceByConfigRules[*].{Rule:ConfigRuleName,Status:Compliance.ComplianceType}' \
  --output table
```

---

## CC8.1 — Change Management

**What the auditor wants:** All infrastructure changes go through a reviewable, auditable process. No direct `apply` without a plan reviewed by a second person.

### Terraform patterns

**Remote state with locking:**
```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-production"
    key            = "platform/eks/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:eu-central-1:123456789012:key/mrk-abc123"
    dynamodb_table = "terraform-state-lock"   # Prevents concurrent applies
  }
}

resource "aws_dynamodb_table" "terraform_state_lock" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = local.common_tags
}
```

**GitHub Actions: plan on PR, apply only on merge (enforces two-person review):**
```yaml
# .github/workflows/terraform-plan.yml
name: terraform-plan

on:
  pull_request:
    paths: ["terraform/**"]

permissions:
  contents: read
  pull-requests: write   # Post plan as PR comment
  id-token: write        # OIDC for AWS

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@e3dd6a429d7300a6a4c196c26e071d42e0343502  # v4
        with:
          role-to-assume: arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/github-actions-plan
          aws-region: eu-central-1

      - name: Terraform plan
        id: plan
        run: |
          terraform init
          terraform plan -out=plan.tfplan -no-color 2>&1 | tee plan.txt

      - name: Post plan as PR comment
        uses: actions/github-script@60a0d83039c74a4aee543508d2ffcb1c3799cdea  # v7
        with:
          script: |
            const plan = require('fs').readFileSync('plan.txt', 'utf8')
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `## Terraform Plan\n\`\`\`\n${plan.slice(0, 60000)}\n\`\`\``
            })
```

**Checkov rules:**
```
CKV_TF_1   — Ensure Terraform module sources use a commit hash (not floating version)
CKV_TF_2   — Ensure Terraform registry module sources use a version tag
```

**Evidence:**
```bash
# Show all Terraform state operations (who ran apply and when)
aws s3api list-object-versions \
  --bucket terraform-state-production \
  --prefix platform/eks/terraform.tfstate \
  --query 'Versions[*].{Key:Key,Modified:LastModified,ETag:ETag}' \
  --output table

# CloudTrail: DynamoDB lock acquire events (each represents a terraform apply)
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=PutItem \
  --start-time "$(date -v-30d '+%Y-%m-%dT00:00:00Z')" \
  --query 'Events[?Resources[?ResourceName==`terraform-state-lock`]].{Time:EventTime,User:Username}' \
  --output table
```

---

## A1.1 — Availability

**What the auditor wants:** Production workloads are multi-AZ, have tested backup retention, and have documented RTO/RPO.

### Terraform patterns

```hcl
# EKS node group across 3 AZs
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "production"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id   # All private subnets (multi-AZ)

  scaling_config {
    desired_size = 3
    min_size     = 3   # Minimum 1 per AZ
    max_size     = 12
  }

  update_config {
    max_unavailable = 1   # Rolling update, never takes down more than 1 node
  }
}

# RDS Multi-AZ
resource "aws_db_instance" "main" {
  multi_az                = true
  backup_retention_period = 30         # 30-day PITR (point-in-time recovery)
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"
  deletion_protection     = true
  skip_final_snapshot     = false
  final_snapshot_identifier = "production-db-final-${formatdate("YYYY-MM-DD", timestamp())}"
}
```

**Checkov rules:**
```
CKV_AWS_157  — Ensure RDS has multi-AZ enabled
CKV_AWS_133  — Ensure RDS cluster has backup retention period set
CKV_AWS_211  — Ensure RDS uses a modern CA certificate
CKV_AWS_96   — Ensure Aurora Cluster is not using the default master username
```

**Evidence:**
```bash
# RDS instances not in multi-AZ
aws rds describe-db-instances \
  --query 'DBInstances[?MultiAZ==`false`].{ID:DBInstanceIdentifier,Engine:Engine,Class:DBInstanceClass}' \
  --output table

# Backup retention periods
aws rds describe-db-instances \
  --query 'DBInstances[*].{ID:DBInstanceIdentifier,BackupRetention:BackupRetentionPeriod}' \
  --output table
```

---

## Checkov in CI — Full Pipeline

Run Checkov in every PR touching Terraform. Map findings to SOC 2 criteria using the `.checkov.yaml` config:

```yaml
# .checkov.yaml — place in repository root
compact: true
download-external-modules: false
evaluate-variables: true

# Checks grouped by SOC 2 criterion — removing any ID here requires a documented compensating control
check:
  # CC6.1 — IAM least privilege
  - CKV_AWS_40
  - CKV_AWS_274
  - CKV_AWS_1
  # CC6.2 — Authentication
  - CKV_AWS_44
  - CKV_AWS_9
  # CC6.6 — Network + WAF
  - CKV_AWS_25
  - CKV_AWS_24
  - CKV_AWS_260
  - CKV2_AWS_12
  - CKV2_AWS_31
  # CC6.7 — Encryption (core + data services)
  - CKV_AWS_19
  - CKV_AWS_16
  - CKV_AWS_7
  - CKV_AWS_28
  - CKV_AWS_119
  - CKV_AWS_136
  - CKV_AWS_163
  - CKV_AWS_29
  - CKV_AWS_30
  - CKV_AWS_31
  - CKV_AWS_83
  - CKV_AWS_5
  - CKV_AWS_6
  - CKV_AWS_228
  - CKV_AWS_247
  - CKV_AWS_186
  - CKV_AWS_42
  - CKV_AWS_64
  - CKV_AWS_87
  - CKV_AWS_105
  - CKV_AWS_142
  - CKV_AWS_321
  # CC6.8 — Vulnerability management
  - CKV_AWS_8
  - CKV_AWS_65
  # CC7.1 — Detection
  - CKV2_AWS_35
  - CKV_AWS_193
  # CC7.2 — Audit logging
  - CKV_AWS_36
  - CKV_AWS_35
  - CKV_AWS_67
  - CKV2_AWS_10
  # CC7.3 — Incident response
  - CKV_AWS_26
  # A1.2 / A1.3 — Backup
  - CKV_AWS_166
  - CKV_AWS_133
  - CKV_AWS_157
  # CC8.1 — Change management
  - CKV_TF_1
  - CKV_TF_2

# Suppressions — each must have a justification comment
skip-check: []
# Example:
# skip-check:
#   - CKV_AWS_8   # Justification: registry-level scanning in place via aws_ecr_registry_scanning_configuration [Owner: platform] [Review: 2026-07-01]
```

**Run Checkov locally:**
```bash
# Full scan against Terraform directory
checkov -d terraform/ --config-file .checkov.yaml --output cli --output junitxml --output-file-path results/

# Show only failures for a specific framework
checkov -d terraform/ --framework terraform --compact --quiet

# Run with SARIF output for GitHub Security tab
checkov -d terraform/ --output sarif > checkov-results.sarif
```

---

## Complete Working Examples

All Terraform examples live in [`examples/compliance/`](../examples/compliance/). Each subdirectory is a standalone Terraform module with a `terraform {}` block, inline comments mapping to SOC 2 criteria, and validation commands in the header.

| Directory | Criteria covered | What it provisions |
|-----------|-----------------|-------------------|
| [`examples/compliance/iam/`](../examples/compliance/iam/) | CC6.1, CC6.2 | IRSA role, GitHub Actions OIDC trust, SCPs (MFA, privilege escalation, access key deny) |
| [`examples/compliance/logging/`](../examples/compliance/logging/) | CC7.2 | CloudTrail (multi-region, KMS, object lock), AWS Config recorder + 15 managed rules, VPC flow logs |
| [`examples/compliance/network/`](../examples/compliance/network/) | CC6.6 | WAF ACL (rate limit + managed rules), ALB association, WAF logging, security groups |
| [`examples/compliance/encryption-data-services/`](../examples/compliance/encryption-data-services/) | CC6.7 | KMS per service, DynamoDB, ECR, ElastiCache, OpenSearch, Kinesis, EFS, Redshift |
| [`examples/compliance/vulnerability/`](../examples/compliance/vulnerability/) | CC6.8 | ECR registry scanning (ENHANCED + CONTINUOUS_SCAN), Inspector v2, SSM patch baseline + maintenance window |
| [`examples/compliance/detection/`](../examples/compliance/detection/) | CC7.1 | GuardDuty (S3/EKS/malware), 14 CIS CloudWatch metric alarms, Security Hub (AWS Foundational + CIS) |
| [`examples/compliance/incident-response/`](../examples/compliance/incident-response/) | CC7.3 | KMS-encrypted SNS topic, email + PagerDuty subscriptions, SQS dead-letter queue |
| [`examples/compliance/backup/`](../examples/compliance/backup/) | A1.2, A1.3 | Backup vault (KMS + COMPLIANCE vault lock), daily/monthly plan, cross-region copy |
| [`checkov-config.yaml`](../examples/compliance/checkov-config.yaml) | All | Checkov rule IDs grouped by SOC 2 criterion, skip guidance for false positives |

**Usage:** Each module can be applied independently. Cross-module dependencies (for example, `security_alert_topic_arn` from `incident-response/` consumed by other modules) are passed as variables.

---

## SOC 2 Readiness Checklist for Terraform

Before your SOC 2 audit window, verify each item:

**CC6.1 — Access**
- [ ] No IAM policy has `Action: *` or `Resource: *` (Checkov CKV_AWS_1 passes clean)
- [ ] All workloads use IRSA or IAM Roles — no `AWS_ACCESS_KEY_ID` in environment
- [ ] SCP blocks privilege escalation in all accounts

**CC6.2 — Authentication**
- [ ] SCP enforces MFA for console access
- [ ] Credential report shows no active users without MFA
- [ ] GitHub Actions uses OIDC — no stored AWS credentials in secrets

**CC6.3 — Access Removal**
- [ ] No active access keys older than 90 days (Config `access-keys-rotated` passing)
- [ ] Offboarded users have IAM access removed (process documented)

**CC6.6 — Network + WAF**
- [ ] No security group allows `0.0.0.0/0` on ports other than 80/443 on ALBs
- [ ] VPC flow logs enabled on all production VPCs
- [ ] All workloads run in private subnets
- [ ] WAF associated with all public-facing ALBs and CloudFront distributions

**CC6.7 — Encryption**
- [ ] S3 buckets have server-side encryption (KMS CMK)
- [ ] S3 bucket policies deny unencrypted uploads
- [ ] All RDS instances encrypted with `storage_encrypted = true`
- [ ] EBS default encryption enabled at account level
- [ ] KMS key rotation enabled for all CMKs
- [ ] DynamoDB tables have KMS encryption + PITR enabled
- [ ] ECR repositories encrypted with KMS CMK
- [ ] ElastiCache has `at_rest_encryption_enabled` and `transit_encryption_enabled`
- [ ] OpenSearch has at-rest and node-to-node encryption + HTTPS enforced
- [ ] Kinesis streams use KMS encryption
- [ ] EFS file systems encrypted at rest with KMS

**CC6.8 — Vulnerability Management**
- [ ] ECR registry scanning set to `ENHANCED` + `CONTINUOUS_SCAN`
- [ ] AWS Inspector v2 enabled for ECR, EC2, and Lambda
- [ ] SSM Patch Baseline applied to all EC2 instances with CRITICAL patches auto-approved after 7 days
- [ ] No active Inspector findings at CRITICAL severity (or documented exceptions)

**CC7.1 — Detection**
- [ ] GuardDuty enabled in all regions with S3 and EKS audit log sources
- [ ] CloudWatch metric filters + alarms in place for all CIS 3.x controls
- [ ] Security Hub enabled with AWS Foundational and CIS Benchmark standards
- [ ] All HIGH/CRITICAL Security Hub findings have an assigned owner

**CC7.2 — Audit Logging**
- [ ] Multi-region CloudTrail enabled with log file validation
- [ ] CloudTrail logs in S3 with object lock and 1-year retention
- [ ] AWS Config recorder running in all regions
- [ ] All SOC 2-relevant Config rules passing (or documented exceptions)

**CC7.3 — Incident Response**
- [ ] SNS `security-alerts` topic is encrypted at rest (KMS)
- [ ] GuardDuty HIGH/CRITICAL findings route to SNS → PagerDuty / on-call
- [ ] Config delivery channel sends notifications to `security-alerts` SNS
- [ ] Incident response runbook documented and tested in last 90 days

**CC8.1 — Change Management**
- [ ] Terraform state in S3 with DynamoDB locking
- [ ] No direct `terraform apply` — all changes via PR + GitHub Actions
- [ ] Plan output posted as PR comment for reviewability
- [ ] Branch protection requires at least 1 approval before merge

**A1.1 — Availability**
- [ ] All production RDS instances are multi-AZ
- [ ] EKS node groups span at least 2 AZs
- [ ] RTO and RPO documented

**A1.2 / A1.3 — Backup and Recovery**
- [ ] AWS Backup plan in place with daily schedule and 35-day retention minimum
- [ ] Backup vault has vault lock in COMPLIANCE mode
- [ ] Cross-region backup copies configured for DR
- [ ] All production resources tagged `environment=production` for backup selection
- [ ] Restore test completed and documented in the last quarter

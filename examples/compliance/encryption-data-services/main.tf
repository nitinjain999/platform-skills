# terraform-soc2-encryption-data-services.tf
#
# SOC 2 CC6.7 — encryption at rest and in transit for data services:
# DynamoDB, ECR, ElastiCache (Redis), OpenSearch, Kinesis, EFS, and Redshift.
#
# Prerequisites:
#   - aws provider >= 5.0
#   - KMS keys per service (or share a single CMK — shown below as separate
#     keys to allow independent rotation and key policy scoping)
#
# Validation:
#   checkov -d . --config-file ../checkov-config.yaml
#   aws dynamodb describe-table --table-name production-table --query 'Table.SSEDescription'
#   aws elasticache describe-replication-groups --query 'ReplicationGroups[*].{AtRest:AtRestEncryptionEnabled,Transit:TransitEncryptionEnabled}'
#   aws opensearch describe-domain --domain-name production-search --query 'DomainStatus.EncryptionAtRestOptions'

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "redis_auth_token" {
  description = "AUTH token for Redis in-transit encryption (min 16 chars)"
  type        = string
  sensitive   = true
}

variable "subnet_ids" {
  description = "Private subnet IDs for data services"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID for security groups"
  type        = string
}

locals {
  common_tags = {
    ManagedBy   = "terraform"
    Compliance  = "soc2"
    Environment = "production"
  }
}

# ─── KMS keys — one per service for independent rotation and key policies ─────

resource "aws_kms_key" "dynamodb" {
  description             = "DynamoDB encryption key (SOC 2 CC6.7)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = merge(local.common_tags, { Service = "dynamodb" })
}

resource "aws_kms_key" "ecr" {
  description             = "ECR encryption key (SOC 2 CC6.7)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = merge(local.common_tags, { Service = "ecr" })
}

resource "aws_kms_key" "elasticache" {
  description             = "ElastiCache encryption key (SOC 2 CC6.7)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = merge(local.common_tags, { Service = "elasticache" })
}

resource "aws_kms_key" "opensearch" {
  description             = "OpenSearch encryption key (SOC 2 CC6.7)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = merge(local.common_tags, { Service = "opensearch" })
}

resource "aws_kms_key" "kinesis" {
  description             = "Kinesis encryption key (SOC 2 CC6.7)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = merge(local.common_tags, { Service = "kinesis" })
}

resource "aws_kms_key" "efs" {
  description             = "EFS encryption key (SOC 2 CC6.7)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = merge(local.common_tags, { Service = "efs" })
}

resource "aws_kms_key" "redshift" {
  description             = "Redshift encryption key (SOC 2 CC6.7)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = merge(local.common_tags, { Service = "redshift" })
}

# ─── OpenSearch logs ─────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "opensearch_application" {
  name              = "/aws/opensearch/production-search/application"
  retention_in_days = 90

  tags = merge(local.common_tags, { Service = "opensearch" })
}

resource "aws_cloudwatch_log_resource_policy" "opensearch" {
  policy_name = "opensearch-log-publishing"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "es.amazonaws.com"
      }
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "${aws_cloudwatch_log_group.opensearch_application.arn}:*"
    }]
  })
}

# ─── DynamoDB ─────────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "main" {
  name         = "production-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  # CC6.7: encryption at rest with customer-managed KMS key
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  # A1.2: continuous backups (point-in-time recovery up to 35 days)
  point_in_time_recovery {
    enabled = true
  }

  tags = local.common_tags
}

# ─── ECR ──────────────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "app" {
  name = "app"

  # CC6.7: encryption at rest
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  # CC6.8: immutable tags prevent tag overwrites (supply chain integrity)
  image_tag_mutability = "IMMUTABLE"

  # CC6.8: scan every image on push for CVEs
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

# Lifecycle policy: expire untagged images after 14 days (reduce attack surface)
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images after 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only 10 most recent release images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ─── ElastiCache (Redis) ──────────────────────────────────────────────────────

resource "aws_elasticache_subnet_group" "main" {
  name       = "production-redis-subnets"
  subnet_ids = var.subnet_ids
  tags       = local.common_tags
}

resource "aws_security_group" "elasticache" {
  name        = "elasticache-sg"
  description = "ElastiCache — ingress from app tier only (SOC 2 CC6.6)"
  vpc_id      = var.vpc_id
  tags        = local.common_tags
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "production-redis"
  description          = "Production Redis — SOC 2 CC6.7"
  node_type            = "cache.t3.medium"
  num_cache_clusters   = 2
  engine_version       = "7.1"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.elasticache.id]

  # CC6.7: encryption at rest and in transit
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  kms_key_id                 = aws_kms_key.elasticache.arn
  auth_token                 = var.redis_auth_token   # Required when transit_encryption_enabled = true

  # A1.1: multi-AZ automatic failover
  automatic_failover_enabled = true
  multi_az_enabled           = true

  # A1.2: daily automatic backups with 7-day retention
  snapshot_retention_limit = 7
  snapshot_window          = "03:00-04:00"

  tags = local.common_tags
}

# ─── OpenSearch ───────────────────────────────────────────────────────────────

resource "aws_opensearch_domain" "main" {
  domain_name    = "production-search"
  engine_version = "OpenSearch_2.11"

  # CC6.7: encryption at rest
  encrypt_at_rest {
    enabled    = true
    kms_key_id = aws_kms_key.opensearch.arn
  }

  # CC6.7: encryption in transit between nodes
  node_to_node_encryption {
    enabled = true
  }

  # CC6.7: enforce HTTPS, minimum TLS 1.2
  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  # A1.1: 3-node cluster across 3 AZs
  cluster_config {
    instance_type          = "m6g.medium.search"
    instance_count         = 3
    zone_awareness_enabled = true

    zone_awareness_config {
      availability_zone_count = 3
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 100
  }

  # Restrict to VPC — not publicly accessible
  vpc_options {
    subnet_ids         = slice(var.subnet_ids, 0, 3)
    security_group_ids = [aws_security_group.opensearch.id]
  }

  # A1.2: automated snapshots daily
  snapshot_options {
    automated_snapshot_start_hour = 3
  }

  # CC7.2: publish OpenSearch application logs to CloudWatch Logs.
  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_application.arn
    log_type                 = "ES_APPLICATION_LOGS"
    enabled                  = true
  }

  depends_on = [aws_cloudwatch_log_resource_policy.opensearch]

  tags = local.common_tags
}

resource "aws_security_group" "opensearch" {
  name        = "opensearch-sg"
  description = "OpenSearch — ingress from app tier only (SOC 2 CC6.6)"
  vpc_id      = var.vpc_id
  tags        = local.common_tags
}

# ─── Kinesis Data Stream ──────────────────────────────────────────────────────

resource "aws_kinesis_stream" "events" {
  name             = "production-events"
  shard_count      = 2
  retention_period = 168   # 7 days (default is 24h — increase for replay capability)

  # CC6.7: encryption at rest
  encryption_type = "KMS"
  kms_key_id      = aws_kms_key.kinesis.arn

  # Shard-level metrics for monitoring
  shard_level_metrics = [
    "IncomingBytes",
    "OutgoingBytes",
    "IteratorAgeMilliseconds",
  ]

  tags = local.common_tags
}

# ─── EFS ──────────────────────────────────────────────────────────────────────

resource "aws_efs_file_system" "main" {
  # CC6.7: encryption at rest
  encrypted  = true
  kms_key_id = aws_kms_key.efs.arn

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  # Move files not accessed in 30 days to Infrequent Access (cost optimisation)
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = local.common_tags
}

resource "aws_efs_mount_target" "main" {
  for_each = toset(var.subnet_ids)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "efs-sg"
  description = "EFS — NFS ingress from app tier only (SOC 2 CC6.6)"
  vpc_id      = var.vpc_id
  tags        = local.common_tags
}

# ─── Redshift ─────────────────────────────────────────────────────────────────

resource "aws_redshift_subnet_group" "main" {
  name       = "production-redshift-subnets"
  subnet_ids = var.subnet_ids
  tags       = local.common_tags
}

resource "aws_redshift_parameter_group" "ssl" {
  name   = "production-ssl"
  family = "redshift-1.0"

  # CC6.7: enforce SSL for all client connections
  parameter {
    name  = "require_ssl"
    value = "true"
  }

  tags = local.common_tags
}

resource "aws_redshift_cluster" "main" {
  cluster_identifier = "production-dw"
  node_type          = "dc2.large"
  number_of_nodes    = 2
  database_name      = "analytics"
  master_username    = "admin"
  master_password    = var.redshift_master_password

  cluster_subnet_group_name  = aws_redshift_subnet_group.main.name
  cluster_parameter_group_name = aws_redshift_parameter_group.ssl.name

  # CC6.7: encryption at rest
  encrypted  = true
  kms_key_id = aws_kms_key.redshift.arn

  # CC6.6: not publicly accessible, route traffic through VPC
  publicly_accessible  = false
  enhanced_vpc_routing = true

  # A1.2: 35-day automated snapshot retention
  automated_snapshot_retention_period = 35
  snapshot_window                     = "03:00-05:00"

  # A1.1: multi-AZ (Redshift RA3 clusters only — dc2 uses multi-node instead)
  availability_zone_relocation_enabled = false

  # CC7.2: ship database audit logs to an immutable S3 log bucket.
  logging {
    enable        = true
    bucket_name   = var.redshift_audit_log_bucket_name
    s3_key_prefix = "redshift/production-dw/"
  }

  tags = local.common_tags
}

variable "redshift_audit_log_bucket_name" {
  description = "S3 bucket name for Redshift audit logs"
  type        = string
}

variable "redshift_master_password" {
  description = "Redshift master password — store in Secrets Manager, not in tfvars"
  type        = string
  sensitive   = true
}

# Provisions an Amazon Managed Prometheus workspace and deploys DORA recording
# rules using the community Terraform module.
#
# Module: terraform-aws-modules/managed-service-prometheus/aws
# Requires: Terraform >= 1.5.7, AWS provider >= 6.28
#
# Usage:
#   cd examples/dora/amp-variant
#   terraform init
#   terraform plan -var="workspace_alias=dora-platform"
#   terraform apply -var="workspace_alias=dora-platform"
#
# The workspace_prometheus_endpoint output is the value to set in:
#   - prometheus-agent-values.yaml  →  server.remoteWrite[0].url
#   - grafana-amp-datasource.yaml   →  datasources[0].url

terraform {
  required_version = ">= 1.5.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "workspace_alias" {
  description = "Alias for the AMP workspace (human-readable name)"
  type        = string
  default     = "dora-platform"
}

variable "retention_period_in_days" {
  description = "Metric retention in days. null = AMP default (150 days)"
  type        = number
  default     = null
}

variable "kms_key_arn" {
  description = "KMS key ARN for workspace encryption. null = AWS-managed key"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    Purpose   = "dora-metrics"
  }
}

# ---------------------------------------------------------------------------
# AMP workspace + DORA recording rules
# ---------------------------------------------------------------------------

module "amp" {
  source  = "terraform-aws-modules/managed-service-prometheus/aws"
  version = "~> 3.0"

  workspace_alias          = var.workspace_alias
  retention_period_in_days = var.retention_period_in_days
  kms_key_arn              = var.kms_key_arn

  # Deploy the DORA recording rules from the shared rules file.
  # The module encodes the YAML to base64 before calling the AMP API.
  # file() path is relative to this .tf file — adjust if running from repo root.
  rule_group_namespaces = {
    dora = {
      name = "dora-rules"
      data = file("../prometheus-recording-rules.yaml")
    }
  }

  # Alert manager is not required for DORA metrics — disable to keep scope narrow.
  create_alert_manager = false

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Outputs — use these to configure Prometheus Agent and Grafana
# ---------------------------------------------------------------------------

output "workspace_id" {
  description = "AMP workspace ID — use in aws amp CLI commands and IAM policies"
  value       = module.amp.workspace_id
}

output "workspace_arn" {
  description = "AMP workspace ARN — use in IAM resource conditions"
  value       = module.amp.workspace_arn
}

output "workspace_prometheus_endpoint" {
  description = "AMP endpoint URL — set as remoteWrite.url in Prometheus Agent and as datasource URL in Grafana"
  value       = module.amp.workspace_prometheus_endpoint
}

output "remote_write_url" {
  description = "Full remote_write URL for Prometheus Agent configuration"
  value       = "${module.amp.workspace_prometheus_endpoint}api/v1/remote_write"
}

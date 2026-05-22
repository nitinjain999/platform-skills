variable "name" {
  type        = string
  description = "Name prefix applied to all resources."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name)) && length(var.name) <= 32
    error_message = "Name must be lowercase alphanumeric and hyphens, max 32 chars."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for origin resources (S3, ALB). CloudFront is global."
  default     = "eu-central-1"
}

variable "default_tags" {
  type        = map(string)
  description = "Tags applied to all resources via provider default_tags."
  default     = {}
}

variable "domain_names" {
  type        = list(string)
  description = "Alternate domain names (CNAMEs) for the distribution. Requires matching ACM cert in us-east-1."
  default     = []
}

variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate ARN in us-east-1 for the alternate domain names. Required when domain_names is non-empty."
  default     = null
}

variable "price_class" {
  type        = string
  description = "CloudFront price class. PriceClass_100 = US/EU (cheapest). PriceClass_All = global."
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "Must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "waf_web_acl_arn" {
  type        = string
  description = "ARN of a WAF WebACL with CLOUDFRONT scope (must be in us-east-1). Leave null to skip WAF."
  default     = null
}

variable "geo_restriction_type" {
  type        = string
  description = "Geo restriction type. 'none' disables restriction. 'allowlist' or 'blacklist'."
  default     = "none"

  validation {
    condition     = contains(["none", "allowlist", "blacklist"], var.geo_restriction_type)
    error_message = "Must be none, allowlist, or blacklist."
  }
}

variable "geo_restriction_locations" {
  type        = list(string)
  description = "ISO 3166-1 alpha-2 country codes for geo restriction. Required when geo_restriction_type != none."
  default     = []
}

variable "enable_cloudfront_function" {
  type        = bool
  description = "Deploy the URL rewrite CloudFront Function on the default cache behavior."
  default     = false
}

variable "enable_lambda_edge" {
  type        = bool
  description = "Deploy the viewer-request Lambda@Edge function on the default cache behavior."
  default     = false
}

variable "log_bucket_domain_name" {
  type        = string
  description = "S3 bucket domain name for CloudFront standard access logs. Leave null to disable logging."
  default     = null
}

variable "log_prefix" {
  type        = string
  description = "S3 key prefix for CloudFront access logs."
  default     = "cloudfront/"
}

variable "s3_origin_force_destroy" {
  type        = bool
  description = "Allow Terraform to destroy the origin S3 bucket even if it contains objects. Use false in production."
  default     = false
}

variable "custom_origin_domain" {
  type        = string
  description = "Custom HTTP origin domain name (ALB, API GW). When set, an ALB origin is added alongside S3."
  default     = null
}

variable "cloudfront_origin_secret" {
  type        = string
  description = "Secret value sent as X-CloudFront-Secret header to ALB origin. Store in Secrets Manager and rotate."
  default     = null
  sensitive   = true
}

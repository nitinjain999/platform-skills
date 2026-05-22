locals {
  s3_origin_id  = "s3-${var.name}"
  alb_origin_id = "alb-${var.name}"

  # Use custom domains + ACM cert when provided; fall back to CloudFront default cert
  use_custom_domain = length(var.domain_names) > 0 && var.acm_certificate_arn != null

  viewer_certificate = local.use_custom_domain ? {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  } : {
    acm_certificate_arn      = null
    ssl_support_method       = null
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # Default cache behavior points at S3; ALB path patterns override when custom_origin_domain is set
  default_origin_id = local.use_alb ? local.alb_origin_id : local.s3_origin_id
  use_alb           = var.custom_origin_domain != null
}

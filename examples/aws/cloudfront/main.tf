# ─── S3 Origin ───────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "origin" {
  bucket        = "${var.name}-origin"
  force_destroy = var.s3_origin_force_destroy
}

resource "aws_s3_bucket_public_access_block" "origin" {
  bucket                  = aws_s3_bucket.origin.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "origin" {
  bucket = aws_s3_bucket.origin.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "origin" {
  bucket = aws_s3_bucket.origin.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# ─── Origin Access Control ───────────────────────────────────────────────────

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = var.name
  description                       = "OAC for ${var.name} S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Bucket policy: allow only this specific distribution via OAC
resource "aws_s3_bucket_policy" "origin" {
  bucket = aws_s3_bucket.origin.id
  policy = data.aws_iam_policy_document.s3_oac.json

  depends_on = [aws_s3_bucket_public_access_block.origin]
}

data "aws_iam_policy_document" "s3_oac" {
  statement {
    sid    = "AllowCloudFrontServicePrincipal"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.origin.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

# ─── Response Headers Policy ─────────────────────────────────────────────────

resource "aws_cloudfront_response_headers_policy" "security" {
  name = "${var.name}-security-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_type_options { override = true }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=()"
      override = true
    }
  }
}

# ─── CloudFront Function ──────────────────────────────────────────────────────

resource "aws_cloudfront_function" "url_rewrite" {
  count   = var.enable_cloudfront_function ? 1 : 0
  name    = "${var.name}-url-rewrite"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/functions/url-rewrite.js")
}

# ─── Distribution ─────────────────────────────────────────────────────────────

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.name
  price_class         = var.price_class
  web_acl_id          = var.waf_web_acl_arn
  aliases             = local.use_custom_domain ? var.domain_names : []
  default_root_object = "index.html"

  # ── S3 origin
  origin {
    domain_name              = aws_s3_bucket.origin.bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  # ── ALB origin without secret header
  dynamic "origin" {
    for_each = local.use_alb && var.cloudfront_origin_secret == null ? { alb = true } : {}
    content {
      domain_name = var.custom_origin_domain
      origin_id   = local.alb_origin_id
      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # ── ALB origin with secret header (prevents direct ALB access — WAF on ALB blocks missing header)
  dynamic "origin" {
    for_each = local.use_alb && var.cloudfront_origin_secret != null ? { alb = true } : {}
    content {
      domain_name = var.custom_origin_domain
      origin_id   = local.alb_origin_id
      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
      custom_header {
        name  = "X-CloudFront-Secret"
        value = var.cloudfront_origin_secret
      }
    }
  }

  # ── Default cache behavior
  default_cache_behavior {
    allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = local.default_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    # Use AWS managed CachingOptimized for static; CachingDisabled for API
    cache_policy_id = data.aws_cloudfront_cache_policy.optimized.id

    # CloudFront Function association (optional)
    dynamic "function_association" {
      for_each = var.enable_cloudfront_function ? { cf_fn = true } : {}
      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.url_rewrite[0].arn
      }
    }

    # Lambda@Edge association (optional) — must use qualified_arn (numbered version, not $LATEST)
    # Deploy lambda-edge/ first, then pass its qualified_arn output to this variable.
    dynamic "lambda_function_association" {
      for_each = var.lambda_edge_function_arn != null ? { fn = var.lambda_edge_function_arn } : {}
      content {
        event_type   = "viewer-request"
        lambda_arn   = lambda_function_association.value
        include_body = false
      }
    }
  }

  # ── API path behavior (when ALB origin is configured)
  dynamic "ordered_cache_behavior" {
    for_each = local.use_alb ? { api = true } : {}
    content {
      path_pattern               = "/api/*"
      allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods             = ["GET", "HEAD"]
      target_origin_id           = local.alb_origin_id
      viewer_protocol_policy     = "https-only"
      compress                   = false
      response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
      cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    }
  }

  # ── Geo restriction
  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_restriction_locations
    }
  }

  # ── TLS
  viewer_certificate {
    acm_certificate_arn            = local.viewer_certificate.acm_certificate_arn
    ssl_support_method             = local.viewer_certificate.ssl_support_method
    minimum_protocol_version       = local.viewer_certificate.minimum_protocol_version
    cloudfront_default_certificate = !local.use_custom_domain
  }

  # ── Access logging
  dynamic "logging_config" {
    for_each = var.log_bucket_domain_name != null ? { log = true } : {}
    content {
      bucket          = var.log_bucket_domain_name
      prefix          = var.log_prefix
      include_cookies = false
    }
  }
}

# ─── Data sources ─────────────────────────────────────────────────────────────

data "aws_cloudfront_cache_policy" "optimized" {
  name = "CachingOptimized"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "CachingDisabled"
}

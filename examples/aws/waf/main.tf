# ─── IP Allowlist ─────────────────────────────────────────────────────────────

# ─── Cross-variable validations ───────────────────────────────────────────────

check "atp_requires_login_path" {
  assert {
    condition     = !var.enable_atp || var.login_path != null
    error_message = "login_path must be set when enable_atp = true."
  }
}

resource "aws_wafv2_ip_set" "allowlist" {
  provider           = aws.us_east_1
  count              = length(var.trusted_cidrs) > 0 ? 1 : 0
  name               = "${var.name}-allowlist"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = var.trusted_cidrs
}

# ─── Web ACL ──────────────────────────────────────────────────────────────────

resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.us_east_1
  name     = "${var.name}-cloudfront"
  scope    = "CLOUDFRONT" # must be CLOUDFRONT for CloudFront distributions
  tags     = {}           # tags come from provider default_tags

  default_action {
    dynamic "allow" {
      for_each = var.default_action == "allow" ? { v = true } : {}
      content {}
    }
    dynamic "block" {
      for_each = var.default_action == "block" ? { v = true } : {}
      content {}
    }
  }

  # ── Priority 0: Allowlist trusted CIDRs (terminates evaluation immediately)
  dynamic "rule" {
    for_each = length(var.trusted_cidrs) > 0 ? { v = true } : {}
    content {
      name     = "AllowTrustedIPs"
      priority = 0
      action {
        allow {}
      }
      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.allowlist[0].arn
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-AllowTrustedIPs"
        sampled_requests_enabled   = false
      }
    }
  }

  # ── Priority 5: AWS IP reputation list (free — always include)
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 5
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-IpReputationList"
      sampled_requests_enabled   = true
    }
  }

  # ── Priority 6: Anonymous IP list — VPN/Tor/hosting IPs (free)
  rule {
    name     = "AWSManagedRulesAnonymousIpList"
    priority = 6
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAnonymousIpList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-AnonymousIpList"
      sampled_requests_enabled   = true
    }
  }

  # ── Priority 10: Core Rule Set — OWASP Top 10 (free)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # SizeRestrictions_BODY fires on large uploads — Count initially, promote to Block after testing
        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            count {}
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ── Priority 11: Known bad inputs — Log4Shell, SSRF (free)
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleGroup"
    priority = 11
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleGroup"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  # ── Priority 20: Geo block (optional)
  dynamic "rule" {
    for_each = length(var.blocked_country_codes) > 0 ? { v = true } : {}
    content {
      name     = "BlockHighRiskGeos"
      priority = 20
      action {
        block {}
      }
      statement {
        geo_match_statement {
          country_codes = var.blocked_country_codes
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-GeoBlock"
        sampled_requests_enabled   = true
      }
    }
  }

  # ── Priority 30: Rate limit per IP (optional)
  dynamic "rule" {
    for_each = var.rate_limit > 0 ? { v = true } : {}
    content {
      name     = "RateLimitPerIP"
      priority = 30
      action {
        block {
          custom_response {
            response_code = 429
            response_header {
              name  = "Retry-After"
              value = "60"
            }
          }
        }
      }
      statement {
        rate_based_statement {
          limit              = var.rate_limit
          aggregate_key_type = "IP"

          dynamic "scope_down_statement" {
            for_each = var.rate_limit_scope_path != "" ? { v = true } : {}
            content {
              byte_match_statement {
                search_string         = var.rate_limit_scope_path
                positional_constraint = "STARTS_WITH"
                field_to_match {
                  uri_path {}
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-RateLimitPerIP"
        sampled_requests_enabled   = true
      }
    }
  }

  # ── Priority 40: Bot Control (paid — opt-in)
  dynamic "rule" {
    for_each = var.enable_bot_control ? { v = true } : {}
    content {
      name     = "AWSManagedRulesBotControlRuleSet"
      priority = 40
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesBotControlRuleSet"
          vendor_name = "AWS"
          managed_rule_group_configs {
            aws_managed_rules_bot_control_rule_set {
              inspection_level = "COMMON" # COMMON (free bots) or TARGETED (sophisticated bots, higher cost)
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-BotControl"
        sampled_requests_enabled   = true
      }
    }
  }

  # ── Priority 50: Account Takeover Prevention (paid — opt-in)
  dynamic "rule" {
    for_each = var.enable_atp && var.login_path != null ? { v = true } : {}
    content {
      name     = "AWSManagedRulesATPRuleSet"
      priority = 50
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesATPRuleSet"
          vendor_name = "AWS"
          managed_rule_group_configs {
            aws_managed_rules_atp_rule_set {
              login_path = var.login_path
              request_inspection {
                # Adjust to match your login form field names
                username_field {
                  identifier = "/username"
                }
                password_field {
                  identifier = "/password"
                }
                payload_type = "JSON"
              }
              response_inspection {
                status_code {
                  success_codes = [200]
                  failure_codes = [401, 403]
                }
              }
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-ATP"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-cloudfront-waf"
    sampled_requests_enabled   = true
  }
}

# ─── Logging ──────────────────────────────────────────────────────────────────

# CloudWatch log group name MUST start with "aws-waf-logs-" — AWS requirement
resource "aws_cloudwatch_log_group" "waf" {
  provider          = aws.us_east_1
  name              = "aws-waf-logs-${var.name}"
  retention_in_days = var.cloudwatch_log_retention_days
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  provider                = aws.us_east_1
  resource_arn            = aws_wafv2_web_acl.cloudfront.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  # Redact sensitive headers from logs
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
  redacted_fields {
    single_header {
      name = "cookie"
    }
  }

  # Log only blocked and counted requests — reduces log volume and cost
  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior    = "KEEP"
      requirement = "MEETS_ANY"
      condition {
        action_condition {
          action = "BLOCK"
        }
      }
    }

    filter {
      behavior    = "KEEP"
      requirement = "MEETS_ANY"
      condition {
        action_condition {
          action = "COUNT"
        }
      }
    }
  }
}

---
title: AWS WAF
custom_edit_url: null
---

# AWS WAF Reference

## Contents

- Scope — the most common footgun
- Web ACL anatomy
- Managed rule groups
- Rate limiting
- Custom rules
- CAPTCHA and Challenge
- Logging
- Testing workflow
- Multi-account with Firewall Manager
- Shield Advanced integration
- Production checklist

---

## Scope — the most common footgun

WAF web ACLs have two scopes and the distinction affects where the resource must be created.

| Scope | Resource Types | AWS Region | Terraform provider |
|---|---|---|---|
| `CLOUDFRONT` | CloudFront distributions | **Must be `us-east-1`** — always | `provider = aws.us_east_1` alias |
| `REGIONAL` | ALB, API Gateway, Cognito, AppSync, App Runner, Verified Access | Same region as the resource | Default provider |

**This is the single most common WAF Terraform mistake.** A web ACL with `scope = "CLOUDFRONT"` created in any region other than `us-east-1` will fail to associate with a CloudFront distribution.

```hcl
# In versions.tf — always define a us-east-1 alias for CloudFront WAF
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags { tags = var.default_tags }
}

resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.us_east_1   # mandatory for CLOUDFRONT scope
  name     = "${var.name}-cloudfront-waf"
  scope    = "CLOUDFRONT"
  ...
}
```

---

## Web ACL anatomy

A web ACL evaluates rules in **priority order** (lowest number first). The first matching rule's action applies.

```
Web ACL
├── Rule priority 0 — IP allowlist (Allow, terminates evaluation)
├── Rule priority 10 — AWS Managed: IP Reputation (Block)
├── Rule priority 20 — AWS Managed: Core Rule Set (Block)
├── Rule priority 30 — Rate limit: 2000 req/5min per IP (Block)
├── Rule priority 40 — Custom: block missing User-Agent (Block)
└── Default action — Allow (or Block for closed APIs)
```

**Rule actions:**

| Action | Behavior |
|---|---|
| `Allow` | Permit the request, stop rule evaluation |
| `Block` | Return HTTP 403 (or custom response), stop evaluation |
| `Count` | Increment counter, continue evaluation |
| `CAPTCHA` | Challenge with CAPTCHA puzzle |
| `Challenge` | Silent JS token challenge (no user friction) |

Use `Count` when testing new rules before promoting to `Block`.

---

## Managed rule groups

AWS provides these rule groups free of charge unless marked **Paid**.

### Baseline — start here for all distributions

| Rule Group | Vendor ID | Protects Against |
|---|---|---|
| `AWSManagedRulesCommonRuleSet` | `aws` | OWASP Top 10, XSS, SQLi, LFI, RFI |
| `AWSManagedRulesAdminProtectionRuleGroup` | `aws` | Exposed admin pages (/admin, /wp-admin) |
| `AWSManagedRulesKnownBadInputsRuleGroup` | `aws` | Log4Shell, SSRF, bad HTTP inputs |

### Use-case specific — add based on your stack

| Rule Group | Vendor ID | Add When |
|---|---|---|
| `AWSManagedRulesSQLiRuleGroup` | `aws` | Any SQL database backend |
| `AWSManagedRulesLinuxRuleGroup` | `aws` | Linux-based origin servers |
| `AWSManagedRulesPHPRuleGroup` | `aws` | PHP applications |
| `AWSManagedRulesWindowsRuleGroup` | `aws` | Windows/.NET backends |
| `AWSManagedRulesWordPressRuleGroup` | `aws` | WordPress sites |

### IP reputation — always include

| Rule Group | Protects Against |
|---|---|
| `AWSManagedRulesAmazonIpReputationList` | AWS threat intelligence, scrapers, bots |
| `AWSManagedRulesAnonymousIpList` | VPN exits, Tor nodes, hosting provider IPs used to anonymize |

### Paid intelligent threat protection

| Rule Group | Cost Basis | Use For |
|---|---|---|
| `AWSManagedRulesBotControlRuleSet` | Per request inspected | Bot detection — Common level (free-tier bots) or Targeted (sophisticated bots) |
| `AWSManagedRulesACFPRuleSet` | Per request to registration endpoints | Account creation fraud prevention |
| `AWSManagedRulesATPRuleSet` | Per request to login endpoints | Account takeover / credential stuffing |
| `AWSManagedRulesAntiDDoSRuleGroup` | Requires Shield Advanced subscription | L7 DDoS mitigation |

### Terraform — managed rule group block

```hcl
resource "aws_wafv2_web_acl" "cloudfront" {
  provider      = aws.us_east_1
  name          = "${var.name}-cloudfront"
  scope         = "CLOUDFRONT"
  default_action { allow {} }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action { none {} }  # use none{} to respect rule group's own actions

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # Override specific rules to Count instead of Block (use during testing)
        rule_action_override {
          name          = "SizeRestrictions_BODY"
          action_to_use { count {} }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 5

    override_action { none {} }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesAmazonIpReputationList"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-cloudfront-waf"
    sampled_requests_enabled   = true
  }
}
```

---

## Rate limiting

Rate-based rules count requests matching a statement over a **5-minute sliding window**.

### Aggregation keys

| Key | Use Case |
|---|---|
| `IP` | Per source IP (default, most common) |
| `FORWARDED_IP` | Behind a proxy/load balancer — uses `X-Forwarded-For` |
| `HTTP_HEADER` | Per API key or session header |
| `QUERY_STRING` | Per query parameter value |
| `CUSTOM_KEYS` | Combination of the above |

```hcl
rule {
  name     = "RateLimitPerIP"
  priority = 30

  action { block {} }

  statement {
    rate_based_statement {
      limit              = 2000   # requests per 5-minute window per aggregation key
      aggregate_key_type = "IP"

      # Optional: only count requests matching a scope-down statement
      scope_down_statement {
        byte_match_statement {
          search_string         = "/api/"
          positional_constraint = "STARTS_WITH"
          field_to_match { uri_path {} }
          text_transformation { priority = 0; type = "NONE" }
        }
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "RateLimitPerIP"
    sampled_requests_enabled   = true
  }
}
```

### Custom block response with Retry-After

```hcl
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
```

---

## Custom rules

### IP set — allowlist trusted CIDRs

```hcl
resource "aws_wafv2_ip_set" "allowlist" {
  provider           = aws.us_east_1
  name               = "${var.name}-allowlist"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"

  addresses = var.trusted_cidrs  # ["10.0.0.0/8", "192.168.1.0/24"]
}

rule {
  name     = "AllowTrustedIPs"
  priority = 0

  action { allow {} }

  statement {
    ip_set_reference_statement {
      arn = aws_wafv2_ip_set.allowlist.arn
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "AllowTrustedIPs"
    sampled_requests_enabled   = false
  }
}
```

### Geo match — block specific countries

```hcl
rule {
  name     = "BlockHighRiskGeos"
  priority = 15

  action { block {} }

  statement {
    geo_match_statement {
      country_codes = var.blocked_country_codes  # ["RU", "KP", "IR"]
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "BlockHighRiskGeos"
    sampled_requests_enabled   = true
  }
}
```

### Label matching — chain managed rule labels

Managed rule groups attach labels to requests. Use label matching to apply custom actions:

```hcl
# Count requests that Bot Control identifies as verified bots (Googlebot etc.)
rule {
  name     = "AllowVerifiedBots"
  priority = 25

  action { allow {} }

  statement {
    label_match_statement {
      scope = "LABEL"
      key   = "awswaf:managed:aws:bot-control:bot:verified"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "AllowVerifiedBots"
    sampled_requests_enabled   = true
  }
}
```

### Regex pattern set

```hcl
resource "aws_wafv2_regex_pattern_set" "bad_paths" {
  provider = aws.us_east_1
  name     = "${var.name}-bad-paths"
  scope    = "CLOUDFRONT"

  regular_expression {
    regex_string = "^/\\.env$|^/wp-config\\.php$|^/\\.git/"
  }
}
```

---

## CAPTCHA and Challenge

- **Challenge** — silent JavaScript token validation. No user interaction. Effective against simple bots. Requires JavaScript enabled; **not suitable for API endpoints**.
- **CAPTCHA** — interactive puzzle. Use only for human-facing pages (login, registration).

Both issue a **token** (cookie + header) with an immunity period. Requests with valid unexpired tokens skip the challenge.

```hcl
rule {
  name     = "ChallengeLoginPage"
  priority = 50

  action {
    challenge {
      custom_request_handling {
        insert_header {
          name  = "x-waf-challenged"
          value = "true"
        }
      }
    }
  }

  statement {
    byte_match_statement {
      search_string         = "/login"
      positional_constraint = "STARTS_WITH"
      field_to_match { uri_path {} }
      text_transformation { priority = 0; type = "LOWERCASE" }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "ChallengeLoginPage"
    sampled_requests_enabled   = true
  }
}
```

---

## Logging

### Destinations

| Destination | Retention | Best For |
|---|---|---|
| CloudWatch Logs | Configurable | Alerting, short-term analysis |
| S3 | Indefinite | Long-term storage, Athena queries |
| Kinesis Data Firehose | Configurable | Real-time streaming, SIEM integration |

### Logging configuration with field redaction

```hcl
resource "aws_wafv2_web_acl_logging_configuration" "this" {
  provider                = aws.us_east_1
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.cloudfront.arn

  redacted_fields {
    single_header { name = "authorization" }
  }

  redacted_fields {
    single_header { name = "cookie" }
  }

  # Only log blocked/counted requests — reduce volume and cost
  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior = "KEEP"
      condition {
        action_condition { action = "BLOCK" }
      }
      requirement = "MEETS_ANY"
    }

    filter {
      behavior = "KEEP"
      condition {
        action_condition { action = "COUNT" }
      }
      requirement = "MEETS_ANY"
    }
  }
}

resource "aws_cloudwatch_log_group" "waf" {
  provider          = aws.us_east_1
  name              = "aws-waf-logs-${var.name}"  # must start with aws-waf-logs-
  retention_in_days = 30
}
```

**CloudWatch log group name must start with `aws-waf-logs-`** — this is an AWS requirement, not a convention.

### Security Lake integration

WAF logs can be sent to Amazon Security Lake for centralized cross-account security analysis. No extra WAF charge — Security Lake pricing applies separately. Configure via the Security Lake console or `aws_securitylake_data_lake` Terraform resource.

---

## Testing workflow

Never deploy new rules directly to `Block` in production.

```
1. Add rule with action = Count
        ↓
2. Monitor for 24–48 hours:
   - CloudWatch: AllowedRequests / BlockedRequests / CountedRequests metrics per rule
   - WAF console: sampled requests (up to 500 per 3 hours)
   - Logs: query for rule matches
        ↓
3. Review false positives:
   - Identify legitimate traffic matching the rule
   - Add rule_action_override or scope-down statement to exclude
        ↓
4. Promote to Block
        ↓
5. Monitor for 1 hour after promotion
   - Check 4xx/5xx error rates on origin
   - Check CloudFront cache hit ratio (unexpected drops = origin seeing more requests)
```

### CloudWatch metric query — blocked requests per rule

```
SELECT SUM(BlockedRequests)
FROM SCHEMA("aws/wafv2", Rule, WebACL, Region, Stage)
WHERE WebACL = 'your-web-acl-name'
GROUP BY Rule
ORDER BY SUM(BlockedRequests) DESC
```

---

## Multi-account with Firewall Manager

AWS Firewall Manager (FMS) is the correct solution for enforcing WAF policies across accounts in an AWS Organization. Do not manage per-account WAF rules independently when you have more than 3 accounts.

### Prerequisites

1. AWS Organizations must be enabled with all features active
2. An FMS administrator account must be designated (management account or a delegated security account)
3. Member accounts must be in the same Organization
4. The FMS service-linked role must exist in each member account (auto-created on first FMS action)

```hcl
# Run once in the management account or via aws CLI:
resource "aws_fms_admin_account" "this" {
  account_id = var.security_account_id  # dedicated security account (recommended)
}
```

### FMS policy anatomy

```hcl
resource "aws_fms_policy" "cloudfront_waf" {
  provider                  = aws.us_east_1  # FMS CloudFront policies must be us-east-1
  name                      = "cloudfront-waf-baseline"
  exclude_resource_tags     = false
  remediation_enabled       = true   # auto-create/update WebACLs — set false for audit mode
  resource_type             = "AWS::CloudFront::Distribution"

  # Target entire OU — new accounts automatically included
  include_map {
    orgunit = [var.production_ou_id]
  }

  # Exclude sandbox/dev accounts
  exclude_map {
    account = var.excluded_account_ids
  }

  # Optional: only protect distributions with this tag
  resource_tags = {
    "FMSProtected" = "true"
  }

  security_service_policy_data {
    type = "WAFV2"

    managed_service_data = jsonencode({
      type = "WAFV2"
      defaultAction = { type = "ALLOW" }

      # FIRST rule groups — security team owns, app teams cannot remove
      preProcessRuleGroups = [
        {
          ruleGroupType = "ManagedRuleGroup"
          managedRuleGroupIdentifier = {
            vendorName        = "AWS"
            managedRuleGroupName = "AWSManagedRulesAmazonIpReputationList"
          }
          overrideAction = { type = "NONE" }
          priority       = 5
        },
        {
          ruleGroupType = "ManagedRuleGroup"
          managedRuleGroupIdentifier = {
            vendorName        = "AWS"
            managedRuleGroupName = "AWSManagedRulesCommonRuleSet"
          }
          overrideAction = { type = "NONE" }
          priority       = 10
        }
      ]

      # LAST rule groups — security team owns
      postProcessRuleGroups = []

      # Allow app teams to add rules in the middle
      overrideCustomerWebACLAssociation = false
    })
  }
}
```

### Rule group ownership model

```
Priority 0–19   FIRST (FMS locked — security team)
                  ├── IP reputation list
                  └── Core Rule Set

Priority 20–79  MIDDLE (app team — local additions via their own rules)
                  ├── App-specific rate limits
                  ├── Path-based blocks
                  └── Bot Control (if purchased per-account)

Priority 80–99  LAST (FMS locked — security team)
                  └── Default deny for unmatched internal paths
```

### Auto-remediation behavior

| Setting | Effect |
|---|---|
| `remediation_enabled = true` | FMS creates WebACLs automatically, attaches to in-scope resources, re-attaches if manually detached |
| `remediation_enabled = false` | Audit mode — compliance dashboard shows violations, no automatic changes |

Use audit mode first when rolling out to an existing org to identify existing non-compliant resources before enforcing.

### Compliance dashboard

FMS compliance dashboard shows per-account, per-resource policy compliance without requiring access to member accounts. Access from the FMS administrator account.

```bash
# CLI — list non-compliant resources across all accounts
aws fms list-compliance-status \
  --policy-id <policy-id> \
  --region us-east-1
```

### Cross-account WAF logging

Central logging pattern for FMS-managed WebACLs:

```
Member accounts                    Security account
───────────────                    ─────────────────────────────
WAF logs → Firehose  ──────────►  S3: central-security-logs/waf/
(auto-created by FMS)              Athena / Security Lake
```

Configure in the FMS policy `managed_service_data` with a centralized Firehose ARN in the security account. The Firehose resource policy must allow `delivery.amazonaws.com` from the Organization.

---

## Shield Advanced integration

Shield Advanced extends WAF with DDoS-specific capabilities.

### What it adds

- **`AWSManagedRulesAntiDDoSRuleGroup`** — L7 DDoS detection and mitigation via WAF (requires subscription)
- **Automatic application layer DDoS mitigation** — Shield automatically creates WAF rules during an active DDoS attack
- **Shield Response Team (SRT) access** — proactive engagement, attack forensics, custom rule tuning
- **Cost protection** — AWS credits scaling charges incurred during DDoS attacks

### SRT IAM role (required for proactive engagement)

```hcl
resource "aws_iam_role" "shield_srt" {
  name = "AWSShieldDRTAccessRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "drt.shield.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "shield_srt" {
  role       = aws_iam_role.shield_srt.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSShieldDRTAccessPolicy"
}
```

### Decision: WAF alone vs Shield Advanced

| Scenario | Recommendation |
|---|---|
| Standard web app, occasional scraping | WAF alone |
| High-value target, DDoS history | Shield Advanced |
| Financial, government, critical infrastructure | Shield Advanced mandatory |
| CloudFront + Route 53 + ALB (all in one org) | Shield Advanced at org level via FMS |

Shield Advanced is a paid subscription (~$3,000/month base + data transfer). Evaluate against your DDoS risk profile.

---

## Production checklist

Before associating a WebACL with a CloudFront distribution:

- [ ] Scope is `CLOUDFRONT` and provider is `us_east_1`
- [ ] IP reputation rule group included (free, always include)
- [ ] Core Rule Set included
- [ ] All new rules tested in Count mode first
- [ ] Rate limiting configured for login and API endpoints
- [ ] Logging enabled — CloudWatch log group name starts with `aws-waf-logs-`
- [ ] Sensitive headers (Authorization, Cookie) redacted from logs
- [ ] Default action is `Allow` for public sites, `Block` for private APIs
- [ ] WAF metrics enabled per rule (required for alerting)
- [ ] CloudWatch alarms on `BlockedRequests` sudden spike (may indicate false positive)
- [ ] Multi-account: FMS policy in place — do not manage per-account if on Organizations

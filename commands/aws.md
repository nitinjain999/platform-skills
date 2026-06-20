---
name: aws
description: Structured guidance for AWS CloudFront distributions, WAF web ACLs, Lambda@Edge, CloudFront Functions, Firewall Manager multi-account enforcement, and IAM/IRSA patterns. Covers OAC, cache policies, security headers, managed rule groups, rate limiting, FMS FIRST/MIDDLE/LAST ownership model, and production-ready Terraform generation.
argument-hint: "[cloudfront|waf|lambda-edge|multi-account|orgs|review|terraform] [description or code]"
title: "AWS Command"
sidebar_label: "aws"
custom_edit_url: null
---

# AWS Command

Structured guidance for AWS CloudFront, WAF, Lambda@Edge, and multi-account security patterns.

## Interactive Wizard (fires when no mode is provided)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. cloudfront   — distributions, OAC, cache policies, security headers, Lambda@Edge
  2. waf          — web ACLs, managed rule groups, rate limiting, false positive tuning
  3. lambda-edge  — CloudFront Functions vs Lambda@Edge, viewer/origin events
  4. multi-account — Firewall Manager, cross-account OAC, FMS WAF enforcement
  5. orgs         — Organizations, SCPs, OU design, account vending, Control Tower
  6. review       — production-readiness review of CloudFront + WAF config
  7. terraform    — generate a Terraform module scaffold

Enter 1–7 or mode name:
```

**Q2 — Context** (after mode selected):
- **cloudfront**: `Describe the issue or what you want to build (distribution, OAC, cache, edge function):`
- **waf**: `Describe the use case — new WebACL, false positive, adding a rule, or multi-account enforcement:`
- **lambda-edge**: `What does the edge function need to do? (auth, URL rewrite, A/B test, dynamic routing):`
- **multi-account**: `How many accounts? Do you have FMS administrator configured in the security account?`
- **orgs**: `Describe what you need — SCP enforcement, OU design, account vending, or Control Tower setup:`
- **review / terraform**: no follow-up needed — proceed directly

---

## Activation

Invoke with `/platform-skills:aws` followed by a mode, or describe your problem and the command will route automatically.

```
/platform-skills:aws cloudfront        # CloudFront distributions, OAC, cache, security headers
/platform-skills:aws waf               # WAF web ACLs, managed rules, rate limiting
/platform-skills:aws lambda-edge       # Lambda@Edge and CloudFront Functions
/platform-skills:aws multi-account     # Firewall Manager, cross-account, Organizations
/platform-skills:aws review            # Production-readiness review of your config
/platform-skills:aws terraform         # Generate Terraform module scaffold
```

---

## Mode: cloudfront

**Triggers:** distribution, CDN, OAC, cache behavior, price class, CNAME, SSL, geo restriction, origin, CloudFront

**Reference:** `references/aws-cloudfront.md`

Steps:

1. Identify the problem layer:
   - **Origin access** — OAC/OAI, S3 bucket policy, cross-account origin
   - **Cache** — TTL, cache key, cache policy vs origin request policy
   - **Security** — response headers, HTTPS enforcement, WAF attachment
   - **Edge compute** — Lambda@Edge vs CloudFront Functions decision
   - **Logging** — standard logs, real-time logs, Athena

2. Check for the common footguns:
   - WAF for CloudFront **must** be `CLOUDFRONT` scope in `us-east-1`
   - OAC not OAI — OAI is legacy; new distributions must use OAC
   - Lambda@Edge must use numbered version ARN (`qualified_arn`), not `$LATEST`
   - ACM certificate for custom domains must be in `us-east-1`

3. Provide: problem diagnosis, Terraform snippet, validation steps, rollback plan.

**Key Terraform resources:**

| Resource | Purpose |
|---|---|
| `aws_cloudfront_distribution` | The distribution |
| `aws_cloudfront_origin_access_control` | OAC (replaces OAI) |
| `aws_cloudfront_cache_policy` | Custom cache key and TTL |
| `aws_cloudfront_origin_request_policy` | What to forward to origin |
| `aws_cloudfront_response_headers_policy` | Security headers |
| `aws_cloudfront_function` | CloudFront Function (JS, viewer events) |
| `aws_cloudfront_realtime_log_config` | Real-time logs to Kinesis |

---

## Mode: waf

**Triggers:** WAF, web ACL, rule group, managed rules, rate limit, Bot Control, CAPTCHA, Challenge, IP set, geo block

**Reference:** `references/aws-waf.md`

Steps:

1. Confirm scope:
   - `CLOUDFRONT` → must use `us-east-1` provider alias
   - `REGIONAL` → same region as the protected resource

2. Classify the request:
   - **New WebACL** → baseline rule groups + rate limit + logging
   - **False positive** → use `rule_action_override` to Count the specific rule
   - **Adding rule** → Count first, monitor 24–48h, then Block
   - **Performance** → review sampled requests, check which rules add latency
   - **Multi-account** → use Firewall Manager (see multi-account mode)

3. Provide: exact rule block, priority placement, visibility config, logging config.

**Baseline rule groups (always include for CloudFront):**

```hcl
# Priority 5 — IP reputation (free)
AWSManagedRulesAmazonIpReputationList

# Priority 10 — Core Rule Set (free)
AWSManagedRulesCommonRuleSet

# Priority 15 — Known bad inputs: Log4Shell, SSRF (free)
AWSManagedRulesKnownBadInputsRuleGroup

# Priority 30 — Rate limit: 2000 req/5min per IP
rate_based_statement { limit = 2000; aggregate_key_type = "IP" }
```

**Paid additions (evaluate based on risk):**

- `AWSManagedRulesBotControlRuleSet` — bot traffic (Common or Targeted level)
- `AWSManagedRulesATPRuleSet` — credential stuffing on login endpoints
- `AWSManagedRulesACFPRuleSet` — account creation fraud on registration endpoints

---

## Mode: lambda-edge

**Triggers:** Lambda@Edge, CloudFront Functions, viewer-request, origin-request, edge function, A/B test, auth at edge, URL rewrite

**Reference:** `references/aws-cloudfront.md` → Lambda@Edge section

Decision — CloudFront Functions vs Lambda@Edge:

```
Need network calls?                → Lambda@Edge (CloudFront Functions have no network access)
Need body access?                  → Lambda@Edge (origin events only)
Need execution > 1ms?              → Lambda@Edge
Need viewer-request/response only? → CloudFront Functions (6× cheaper)
Need complex logic / Node modules? → Lambda@Edge
Need dynamic config without deploy?→ CloudFront Functions + KeyValueStore
Simple URL rewrite / header add?   → CloudFront Functions
Auth token validation (JWT)?       → Lambda@Edge viewer-request
Dynamic origin routing?            → Lambda@Edge origin-request
```

**Lambda@Edge checklist:**

- [ ] Function authored in `us-east-1`
- [ ] `publish = true` in Terraform
- [ ] Using `qualified_arn` (not `arn`) in `lambda_function_association`
- [ ] IAM trust includes `edgelambda.amazonaws.com` AND `lambda.amazonaws.com`
- [ ] No VPC attachment
- [ ] No environment variables (use KeyValueStore for config)
- [ ] No `$LATEST` version reference
- [ ] Log group pre-created in `us-east-1`

---

## Mode: multi-account

**Triggers:** Firewall Manager, FMS, Organizations, cross-account, OU, security account, delegated admin, centralized WAF

**References:** `references/aws-waf.md` → Multi-account section, `references/aws-cloudfront.md` → Multi-account patterns

Steps:

1. **Confirm prerequisites:**
   - AWS Organizations with all features enabled
   - FMS administrator account designated
   - Member accounts in-scope (OU or account list)

2. **Choose pattern:**

| Pattern | When to use |
|---|---|
| Shared CloudFront account | Platform team owns distributions; app teams own origins |
| Per-account distributions + FMS WAF | App team autonomy; security team enforces WAF centrally |
| FMS audit mode first | Existing org — identify violations before enforcing |

3. **FMS WAF policy structure:**
   - `preProcessRuleGroups` (priority 0–19) — security team, locked
   - App team rules (priority 20–79) — local additions allowed
   - `postProcessRuleGroups` (priority 80+) — security team, locked

4. **Cross-account OAC pattern (shared CDN account):**
   - Bucket policy `AWS:SourceArn` scoped to distribution ARN works cross-account
   - Distribution ARN includes the CDN account ID — spoke accounts are locked to that distribution

5. Provide: FMS policy Terraform, OAC cross-account bucket policy, SCP to enforce WAF attachment.

---

## Mode: orgs

**Triggers:** Organizations, SCPs, OU, account vending, Control Tower, delegated admin, account factory, guardrails

Steps:

1. **Identify the request:**
   - **SCP design** — what to restrict and at which OU level
   - **OU structure** — hierarchy that reflects environment and risk boundary
   - **Account vending** — automated account creation with baseline config
   - **Control Tower** — managed landing zone setup and customizations

2. **OU design principles:**

   | OU | Accounts | SCP stance |
   |----|----------|------------|
   | Security | Log archive, Audit | Deny all except security tooling |
   | Infrastructure | Network, Shared services | Restricted; platform team only |
   | Workloads/Prod | Production app accounts | Deny risky actions (delete trail, disable GuardDuty) |
   | Workloads/SDLC | Dev, staging accounts | More permissive; deny prod data access |
   | Sandbox | Developer personal accounts | Deny spend > threshold; deny production-touching actions |

3. **Essential SCPs (apply at root or Workloads OU):**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "DenyLeavingOrg",
         "Effect": "Deny",
         "Action": "organizations:LeaveOrganization",
         "Resource": "*"
       },
       {
         "Sid": "DenyDisableCloudTrail",
         "Effect": "Deny",
         "Action": ["cloudtrail:StopLogging", "cloudtrail:DeleteTrail"],
         "Resource": "*"
       },
       {
         "Sid": "DenyDisableGuardDuty",
         "Effect": "Deny",
         "Action": ["guardduty:DeleteDetector", "guardduty:DisassociateFromMasterAccount"],
         "Resource": "*"
       },
       {
         "Sid": "DenyRootUser",
         "Effect": "Deny",
         "Action": "*",
         "Resource": "*",
         "Condition": {
           "StringLike": { "aws:PrincipalArn": "arn:aws:iam::*:root" }
         }
       }
     ]
   }
   ```

4. **Account vending (Account Factory for Terraform — AFT):**
   ```hcl
   module "account_request" {
     source = "github.com/aws-ia/terraform-aws-control_tower_account_factory"
     control_tower_parameters = {
       AccountEmail = "platform+prod-payments@company.com"
       AccountName  = "prod-payments"
       ManagedOrganizationalUnit = "Workloads/Prod"
       SSOUserEmail = "admin@company.com"
     }
     account_tags = { env = "prod", team = "payments", cost-center = "eng" }
     account_customizations_name = "prod-baseline"
   }
   ```

5. **Delegated administrators** — always delegate to a dedicated account, never the management account:
   - GuardDuty: `aws organizations register-delegated-administrator --service-principal guardduty.amazonaws.com`
   - SecurityHub: `--service-principal securityhub.amazonaws.com`
   - FMS: designated separately via FMS console or Terraform

6. **Validate SCP effect before attaching:**
   ```bash
   # Simulate an action under the SCP (requires aws-cli v2)
   aws iam simulate-custom-policy \
     --policy-input-list file://scp.json \
     --action-names cloudtrail:StopLogging \
     --resource-arns "*"
   ```

→ **Next:** Run `/platform-skills:aws review` to audit the account configuration, or `/platform-skills:compliance checklist` to validate SOC 2 controls across the org.

---

## Mode: review

**Triggers:** review, production ready, production checklist, audit my CloudFront, audit my WAF

Structured production-readiness review. Ask for:
1. The CloudFront distribution config (Terraform or describe key settings)
2. The associated WAF WebACL config
3. The origin type (S3, ALB, custom)

Then evaluate against:

**CloudFront:**
- [ ] Viewer protocol: `https-only` or `redirect-to-https`
- [ ] Minimum TLS: `TLSv1.2_2021`
- [ ] OAC configured (not OAI, not public bucket)
- [ ] WAF attached
- [ ] Response headers policy: HSTS, X-Frame-Options, X-Content-Type-Options
- [ ] Standard logging enabled
- [ ] Price class appropriate for audience geography
- [ ] Lambda@Edge: `qualified_arn` used, `publish = true`

**WAF:**
- [ ] Scope is `CLOUDFRONT`, provider is `us_east_1`
- [ ] IP reputation list included
- [ ] Core Rule Set included
- [ ] Rate limiting on sensitive endpoints
- [ ] Logging enabled, sensitive headers redacted
- [ ] CloudWatch metrics enabled per rule
- [ ] New rules tested in Count mode before Block

**Multi-account:**
- [ ] FMS policy in place (if on Organizations with >3 accounts)
- [ ] Compliance dashboard reviewed
- [ ] Centralized logging configured

Report: CRITICAL issues (must fix before launch) → WARNINGS (should fix) → INFORMATIONAL.

---

## Mode: terraform

**Triggers:** generate terraform, scaffold, create module, write terraform for

Generate a Terraform module scaffold using best practices. Ask:
1. What are you building? (CloudFront + S3, CloudFront + ALB, WAF only, FMS policy)
2. Multi-account? (yes/no — affects provider aliases and FMS resources)
3. Lambda@Edge or CloudFront Functions needed? (affects us-east-1 provider alias)
4. Existing WAF or new? (affects whether WAF module is separate)

Then generate complete module files:

```
<module-name>/
├── versions.tf    # terraform{} block + required_providers + provider aliases
├── variables.tf   # typed inputs with validation{} blocks
├── locals.tf      # computed values, name prefixes
├── main.tf        # all resources
└── outputs.tf     # ARNs, IDs, domain names with descriptions
```

**Non-negotiable patterns in every generated module:**

---

## Common mistakes

- **WAF scope in wrong region** — `CLOUDFRONT` scope WebACLs must be created in `us-east-1`. Any other region returns `WAFInvalidParameterException`. Use a provider alias `aws.us_east_1` explicitly
- **OAI instead of OAC** — OAI (Origin Access Identity) is legacy. New distributions must use OAC (`aws_cloudfront_origin_access_control`). OAI does not support non-S3 origins or newer signing protocols
- **Lambda@Edge using `$LATEST`** — `$LATEST` is not a publishable version and cannot be associated with CloudFront. Set `publish = true` in the resource and reference `aws_lambda_function.this.qualified_arn`
- **ACM certificate not in us-east-1** — CloudFront only accepts ACM certificates created in `us-east-1`, regardless of where the distribution serves traffic
- **SCP accidentally blocking the management account** — SCPs do not apply to the management account. Policies intended to restrict member accounts work correctly; don't expect them to constrain root
- **Attaching WAF rules directly in Block mode** — always Count first for 24–48h before switching to Block. A misconfigured rule in Block mode silently drops legitimate traffic

```hcl
# versions.tf — always pin providers
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = { source = "hashicorp/aws"; version = ">= 5.0.0" }
  }
}

# variables.tf — always include description and type
variable "name" {
  type        = string
  description = "Name prefix applied to all resources."
  validation {
    condition     = length(var.name) <= 32
    error_message = "Name must be 32 characters or fewer."
  }
}

variable "default_tags" {
  type        = map(string)
  description = "Tags applied to all resources via provider default_tags."
  default     = {}
}

# Provider — always use default_tags
provider "aws" {
  region = var.aws_region
  default_tags { tags = var.default_tags }
}

# CloudFront WAF / Lambda@Edge — always add us-east-1 alias
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags { tags = var.default_tags }
}

# outputs.tf — always include description
output "distribution_arn" {
  description = "ARN of the CloudFront distribution."
  value       = aws_cloudfront_distribution.this.arn
}
```

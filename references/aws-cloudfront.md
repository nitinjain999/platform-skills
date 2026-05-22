# AWS CloudFront Reference

## Contents

- Distribution anatomy
- Origin Access Control (OAC)
- Cache and origin request policies
- Security headers
- WAF integration
- Lambda@Edge
- CloudFront Functions vs Lambda@Edge
- Logging
- Multi-account patterns
- Production checklist

---

## Distribution anatomy

A CloudFront distribution defines:

- **Origins** — up to 25 per distribution (S3, ALB, API Gateway, custom HTTP, MediaStore, Lambda URL)
- **Cache behaviors** — path pattern → origin mapping, evaluated top to bottom; default (`*`) always last
- **Price class** — controls which edge locations serve traffic

| Price Class | Edge Locations | Use Case |
|---|---|---|
| `PriceClass_100` | US, EU, Israel | Cheapest — most orgs start here |
| `PriceClass_200` | Above + Asia, Africa, Middle East | Mid-tier |
| `PriceClass_All` | All edge locations globally | Lowest latency worldwide |

- **Alternate CNAMEs** — custom domains; require a matching ACM certificate in `us-east-1`
- **IPv6** — enable unless your origin explicitly rejects IPv6 connections
- **Continuous deployment** — staging distribution receives a configurable traffic weight before promoting config to primary

---

## Origin Access Control (OAC)

OAC is the modern replacement for Origin Access Identity (OAI). Always use OAC for new distributions.

### How it works

CloudFront signs requests to the origin using **AWS Signature Version 4 (SigV4)**. The origin's resource policy allows only requests from the specific CloudFront distribution.

### Supported origins

| Origin Type | Terraform resource attribute |
|---|---|
| S3 | `origin_access_control_origin_type = "s3"` |
| AWS Elemental MediaStore | `"mediastore"` |
| Lambda Function URL | `"lambda"` |
| API Gateway | `"apigateway"` |
| AWS Elemental MediaPackage v2 | `"mediapackagev2"` |

### Signing behavior

Use `always` for all new distributions. `no-override` is only for origins that set their own auth header.

```hcl
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
```

### S3 bucket policy

```hcl
data "aws_iam_policy_document" "cloudfront_oac" {
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
      # Scope to the specific distribution — not all CloudFront
      values = [aws_cloudfront_distribution.this.arn]
    }
  }
}
```

### OAI vs OAC

| Feature | OAI (Legacy) | OAC (Recommended) |
|---|---|---|
| S3 support | ✅ | ✅ |
| Non-S3 origins | ❌ | ✅ |
| Signing protocol | Custom | SigV4 |
| Principal type | `CanonicalUser` | `Service` |
| Per-distribution scope | ❌ | ✅ via `AWS:SourceArn` |
| Status | **Do not use for new distributions** | ✅ |

---

## Cache and origin request policies

### The split

- **Cache policy** — what goes into the cache key (headers, cookies, query strings) and TTL settings
- **Origin request policy** — what CloudFront forwards to the origin (can include values not in the cache key)

Keep the cache key narrow. Every unique combination of cache-key values creates a separate cache entry.

### AWS managed cache policies

| Policy name | Cache key | Use for |
|---|---|---|
| `CachingOptimized` | URI only | Static assets (S3) |
| `CachingDisabled` | Everything | API pass-through |
| `CachingOptimizedForUncompressedObjects` | URI only, no compression | Binary/already compressed |
| `CORS-S3Origin` | URI + Origin header | S3 CORS |
| `UseOriginCacheControlHeaders` | URI + Cache-Control from origin | Dynamic content |

### TTL hierarchy (highest precedence first)

1. `Cache-Control: max-age` / `Expires` from origin response
2. `default_ttl` in the cache policy
3. `max_ttl` cap (CloudFront never exceeds this regardless of origin headers)

### Custom cache policy

```hcl
resource "aws_cloudfront_cache_policy" "api" {
  name        = "${var.name}-api"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config  { cookie_behavior = "none" }
    headers_config  { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
    enable_accept_encoding_gzip   = false
    enable_accept_encoding_brotli = false
  }
}
```

---

## Security headers

Use a response headers policy to attach security headers without Lambda@Edge.

```hcl
resource "aws_cloudfront_response_headers_policy" "security" {
  name = "${var.name}-security-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    content_type_options {
      override = true  # X-Content-Type-Options: nosniff
    }

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
```

### Custom origin header (ALB secret)

Prevent direct ALB access by requiring a secret header that only CloudFront adds:

```hcl
origin {
  domain_name = aws_lb.this.dns_name
  origin_id   = "alb"

  custom_header {
    name  = "X-CloudFront-Secret"
    value = var.cloudfront_origin_secret  # stored in Secrets Manager, rotated
  }
}
```

On the ALB WAF: block requests where `X-CloudFront-Secret` is absent or wrong.

---

## WAF integration

### Critical constraint

**WAF web ACLs for CloudFront must use `CLOUDFRONT` scope and be created in `us-east-1`** — even if your origin is in another region. Use a provider alias.

```hcl
# In your CloudFront distribution
resource "aws_cloudfront_distribution" "this" {
  web_acl_id = var.waf_web_acl_arn  # pass in from WAF module (us-east-1)
  ...
}
```

The WAF module must be instantiated with a `us-east-1` provider. See `references/aws-waf.md` for the full WAF reference.

---

## Lambda@Edge

Lambda@Edge lets you run Node.js or Python code at CloudFront edge locations. All functions must be authored in `us-east-1` and are replicated globally by CloudFront.

### Four event types

| Event | Where | Cache | Max Memory | Max Timeout | Body Access | Use Cases |
|---|---|---|---|---|---|---|
| `viewer-request` | Edge, before cache lookup | Always runs | 128 MB | 5s | ❌ | Auth, geo redirect, A/B routing |
| `viewer-response` | Edge, after cache | Always runs | 128 MB | 5s | ❌ | Add/modify response headers |
| `origin-request` | Edge, cache miss only | Cache miss | 512 MB | 30s | ❌ | URL rewrite, dynamic origin selection |
| `origin-response` | Edge, cache miss only | Cache miss | 512 MB | 30s | ❌ | Error handling, fallback origin |

**Cost note:** `viewer-request` and `viewer-response` run on every request. `origin-request` and `origin-response` run only on cache misses. Prefer origin events for expensive logic.

### Common footguns

**Must use numbered version ARN — not `$LATEST`**

```hcl
resource "aws_lambda_function" "edge" {
  provider  = aws.us_east_1
  publish   = true  # creates a numbered version
  ...
}

# Use qualified_arn (includes version number), NOT arn
lambda_function_association {
  event_type   = "viewer-request"
  lambda_arn   = aws_lambda_function.edge.qualified_arn  # ✅ e.g. arn:...:function:name:3
  include_body = false
}
```

**IAM trust policy must include both principals**

```hcl
data "aws_iam_policy_document" "edge_trust" {
  statement {
    principals {
      type = "Service"
      identifiers = [
        "lambda.amazonaws.com",
        "edgelambda.amazonaws.com",  # required — without this, replication fails silently
      ]
    }
    actions = ["sts:AssumeRole"]
  }
}
```

**No VPC, no environment variables, no layers with platform-specific binaries**

Lambda@Edge functions cannot be attached to a VPC and cannot use environment variables. Use CloudFront KeyValueStore for configuration data that needs to change without redeployment.

### Viewer-request auth example (Node.js)

```javascript
// index.js — runs at viewer-request, validates JWT in Authorization header
exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  const headers = request.headers;

  const auth = headers['authorization'] ? headers['authorization'][0].value : null;

  if (!auth || !auth.startsWith('Bearer ')) {
    return {
      status: '401',
      statusDescription: 'Unauthorized',
      headers: {
        'www-authenticate': [{ key: 'WWW-Authenticate', value: 'Bearer' }],
      },
    };
  }

  // validate token here (no network calls — validate signature locally)
  return request;
};
```

### Terraform — Lambda@Edge function

```hcl
# Must use us-east-1 provider alias
resource "aws_lambda_function" "edge" {
  provider         = aws.us_east_1
  filename         = data.archive_file.edge.output_path
  source_code_hash = data.archive_file.edge.output_base64sha256
  function_name    = "${var.name}-edge-viewer-request"
  role             = aws_iam_role.edge.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  publish          = true  # numbered version required

  depends_on = [aws_cloudwatch_log_group.edge]
}

data "archive_file" "edge" {
  type        = "zip"
  source_file = "${path.module}/functions/index.js"
  output_path = "${path.module}/functions/edge.zip"
}

resource "aws_iam_role" "edge" {
  provider           = aws.us_east_1
  name               = "${var.name}-edge-role"
  assume_role_policy = data.aws_iam_policy_document.edge_trust.json
}

resource "aws_iam_role_policy_attachment" "edge_basic" {
  provider   = aws.us_east_1
  role       = aws_iam_role.edge.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# CloudWatch log group in us-east-1 — edge logs replicate here
resource "aws_cloudwatch_log_group" "edge" {
  provider          = aws.us_east_1
  name              = "/aws/lambda/us-east-1.${var.name}-edge-viewer-request"
  retention_in_days = 30
}
```

---

## CloudFront Functions vs Lambda@Edge

| Capability | CloudFront Functions | Lambda@Edge |
|---|---|---|
| Supported events | viewer-request, viewer-response | All 4 event types |
| Runtime | JavaScript 2.0 (ES5.1 + partial ES6–12) | Node.js 22.x, Python 3.x |
| Max execution time | **1ms** | 5s (viewer) / 30s (origin) |
| Max memory | **2 MB** | 128–512 MB |
| Network calls | ❌ | ✅ (allowed but discouraged — adds latency and reliability risk at edge) |
| Body access | ❌ | Origin events only |
| Environment variables | ❌ (use KeyValueStore) | ❌ |
| KV configuration store | ✅ CloudFront KeyValueStore | ❌ |
| Cost | ~6× cheaper than Lambda@Edge | Per invocation + GB-second |
| Deployment | Seconds | Minutes (replication) |
| **Best for** | URL rewrites, header manipulation, simple redirects, A/B by cookie | Auth, complex routing, dynamic origin selection, error handling |

### CloudFront Function — URL rewrite example

```javascript
// Rewrites /product/123 → /product?id=123
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  var match = uri.match(/^\/product\/(\d+)$/);
  if (match) {
    request.uri = '/product';
    request.querystring = { id: { value: match[1] } };
  }

  return request;
}
```

```hcl
resource "aws_cloudfront_function" "url_rewrite" {
  name    = "${var.name}-url-rewrite"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/functions/url-rewrite.js")
}

# Associate in cache behavior
function_association {
  event_type   = "viewer-request"
  function_arn = aws_cloudfront_function.url_rewrite.arn
}
```

---

## Logging

### Standard logs (v2)

Detailed per-request logs. Destinations: S3, CloudWatch Logs, Kinesis Data Firehose.

```hcl
resource "aws_cloudfront_distribution" "this" {
  logging_config {
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    prefix          = "cloudfront/${var.name}/"
    include_cookies = false  # enable for debugging, disable for cost
  }
}
```

### Real-time logs

Sub-second delivery to Kinesis Data Streams. Use for live dashboards and anomaly detection.

```hcl
resource "aws_cloudfront_realtime_log_config" "this" {
  name          = "${var.name}-realtime"
  sampling_rate = 5  # 1–100 percent of requests

  endpoint {
    stream_type = "Kinesis"
    kinesis_stream_config {
      role_arn   = aws_iam_role.realtime_log.arn
      stream_arn = aws_kinesis_stream.logs.arn
    }
  }

  fields = [
    "timestamp", "c-ip", "sc-status", "cs-method",
    "cs-uri-stem", "time-taken", "x-edge-location",
    "cs-protocol", "cs-bytes", "x-edge-result-type",
    "x-host-header", "cs-user-agent",
  ]
}
```

### Athena partitioning

Partition the S3 log prefix by date for cost-efficient queries:

```
s3://logs-bucket/cloudfront/my-distribution/year=2026/month=05/day=22/
```

Use a Lambda or Glue crawler to create partitions, or use Athena partition projection:

```sql
CREATE EXTERNAL TABLE cloudfront_logs (
  date DATE, time STRING, x_edge_location STRING,
  sc_bytes BIGINT, cs_method STRING, cs_host STRING,
  cs_uri_stem STRING, sc_status INT, cs_referer STRING,
  cs_user_agent STRING, cs_uri_query STRING
)
PARTITIONED BY (year STRING, month STRING, day STRING)
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
LOCATION 's3://logs-bucket/cloudfront/my-distribution/'
TBLPROPERTIES (
  'projection.enabled' = 'true',
  'projection.year.type' = 'integer', 'projection.year.range' = '2024,2030',
  'projection.month.type' = 'integer', 'projection.month.range' = '1,12', 'projection.month.digits' = '2',
  'projection.day.type' = 'integer', 'projection.day.range' = '1,31', 'projection.day.digits' = '2',
  'storage.location.template' = 's3://logs-bucket/cloudfront/my-distribution/year=${year}/month=${month}/day=${day}/'
);
```

### Cross-account log bucket

Central logging account S3 bucket resource policy:

```json
{
  "Effect": "Allow",
  "Principal": { "Service": "delivery.logs.amazonaws.com" },
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::central-logs-bucket/cloudfront/*",
  "Condition": {
    "StringEquals": { "aws:SourceOrgID": "o-xxxxxxxxxxxx" }
  }
}
```

---

## Multi-account patterns

### Pattern A — Shared CloudFront account (recommended for platform teams)

Platform team owns distributions in a dedicated CDN account. Origin S3 buckets live in spoke accounts.

```
CDN account (platform)          Spoke account (app team)
──────────────────────          ─────────────────────────
aws_cloudfront_distribution  →  aws_s3_bucket (origin)
aws_cloudfront_origin_access_control
                                aws_s3_bucket_policy:
                                  Principal: cloudfront.amazonaws.com
                                  Condition: AWS:SourceArn = distribution ARN
                                  (cross-account — account ID in ARN differs)
```

The bucket policy `AWS:SourceArn` condition works cross-account — the distribution ARN includes the CDN account ID, so spoke-account buckets are locked to that specific distribution.

### Pattern B — Per-account distributions (app team autonomy)

Each application account owns its own distribution. Security team enforces WAF via Firewall Manager from the security account.

```
Security account                App account
────────────────                ──────────────────────────
aws_fms_policy          →       aws_wafv2_web_acl (auto-created by FMS)
  scope: OU=production           aws_cloudfront_distribution
  auto_remediation: true           web_acl_id = (FMS-managed)
```

### Organizations SCP — enforce WAF attachment

```json
{
  "Effect": "Deny",
  "Action": "cloudfront:CreateDistribution",
  "Resource": "*",
  "Condition": {
    "Null": { "cloudfront:WebAclId": "true" }
  }
}
```

Blocks creating distributions without a WAF web ACL. Apply to production OU.

### Centralized logging bucket

```hcl
resource "aws_s3_bucket_policy" "central_logs" {
  bucket = aws_s3_bucket.central_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontLogsFromOrg"
        Effect = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.central_logs.arn}/cloudfront/*"
        Condition = {
          StringEquals = { "aws:SourceOrgID" = var.org_id }
        }
      },
      {
        Sid    = "AllowCloudFrontACLCheck"
        Effect = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.central_logs.arn
      }
    ]
  })
}
```

---

## Production checklist

Before any distribution goes live:

- [ ] Viewer protocol policy: `redirect-to-https` or `https-only` — never `allow-all`
- [ ] Minimum TLS version: `TLSv1.2_2021` — not `TLSv1` or `TLSv1.1`
- [ ] OAC configured — not OAI, not public bucket
- [ ] WAF web ACL attached (CLOUDFRONT scope, us-east-1)
- [ ] Response headers policy with HSTS, X-Frame-Options, X-Content-Type-Options
- [ ] Standard logging enabled (S3 or CloudWatch)
- [ ] Custom domain with ACM certificate (not CloudFront default `*.cloudfront.net` for production)
- [ ] Geo restriction reviewed — allowlist or blocklist as required by compliance
- [ ] No wildcard CORS — scope `AllowedOrigins` to specific domains
- [ ] `default_cache_behavior` has explicit TTLs — not relying on `Cache-Control` from untrusted origins
- [ ] Lambda@Edge functions using numbered version ARN (not `$LATEST`)
- [ ] Price class reviewed — `PriceClass_100` for EU/US-only services

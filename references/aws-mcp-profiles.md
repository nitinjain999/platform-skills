# AWS MCP Profiles Reference

Deep-dive guide for managing AWS MCP servers across VS Code (GitHub Copilot) and Claude Code with multiple AWS accounts.

## Contents

1. [When MCP vs CLI](#1-when-mcp-vs-cli)
2. [Context Budget Table](#2-context-budget-table)
3. [AWS MCP Server Catalog](#3-aws-mcp-server-catalog)
4. [Profile Type Detection](#4-profile-type-detection)
5. [Auth Flows](#5-auth-flows)
6. [Credential Lifecycle](#6-credential-lifecycle)
7. [credential_process Pattern](#7-credential_process-pattern)
8. [Config File Locations](#8-config-file-locations)
9. [VS Code Input Variables](#9-vs-code-input-variables)
10. [Team Sharing Pattern](#10-team-sharing-pattern)
11. [Multi-Region Handling](#11-multi-region-handling)
12. [Multi-Account EKS](#12-multi-account-eks)
13. [Health Check Checklist](#13-health-check-checklist)
14. [Prod Safety](#14-prod-safety)
15. [Starter Kits](#15-starter-kits)

---

## 1. When MCP vs CLI

MCP servers cost context window tokens the moment they are configured — every registered tool definition is loaded at session start, before you type a single character.

**Use the CLI when:**
- You need one answer: `aws eks list-clusters --profile prod-eu`
- The operation is a single API call with no follow-up reasoning
- You are scripting or automating

**Use MCP when:**
- You need AI to chain multiple AWS API calls and reason across the results
- Example: list EKS clusters → describe nodegroups → correlate with CloudWatch alarms → summarise degraded nodes
- Example: query Bedrock KB → cross-reference AWS docs → generate runbook

**Rule of thumb:** If the task fits in one AWS CLI command, use the CLI. MCP earns its context cost when the AI needs to make 3+ calls and synthesise the results.

| Task | CLI sufficient? | MCP adds value? |
|------|----------------|----------------|
| List EKS clusters | ✓ `aws eks list-clusters` | ✗ |
| Describe a nodegroup | ✓ `aws eks describe-nodegroup` | ✗ |
| Debug why pods are evicted | ✗ | ✓ (cluster + CW + nodes) |
| Find cost anomaly | ✗ | ✓ (billing + pricing + tags) |
| Retrieve from knowledge base | ✗ | ✓ (KB + docs synthesis) |

---

## 2. Context Budget Table

Each MCP server registers all its tools at session start. Approximate tool counts and token costs:

| Server | Package | ~Tools | ~Tokens | Notes |
|--------|---------|--------|---------|-------|
| EKS | `awslabs.eks-mcp-server` | ~40 | ~2,000 | Cluster, nodegroups, pods |
| CloudWatch | `awslabs.cloudwatch-mcp-server` | ~35 | ~1,750 | Logs, metrics, alarms |
| Prometheus (AMP) | `awslabs.prometheus-mcp-server` | ~20 | ~1,000 | AMP workspaces, rules |
| IAM | `awslabs.iam-mcp-server` | ~30 | ~1,500 | Read-only IAM queries |
| Bedrock KB | `awslabs.bedrock-kb-retrieval-mcp-server` | ~15 | ~750 | KB retrieve + generate |
| AWS Docs | `awslabs.aws-documentation-mcp-server` | ~10 | ~500 | Real-time docs search |
| AWS API (general) | `awslabs.aws-api-mcp-server` | ~50 | ~2,500 | All AWS services |
| Billing/Cost | `awslabs.billing-cost-management-mcp-server` | ~20 | ~1,000 | Cost Explorer, budgets |
| Serverless | `awslabs.aws-serverless-mcp-server` | ~25 | ~1,250 | SAM, Lambda lifecycle |
| DynamoDB | `awslabs.dynamodb-mcp-server` | ~25 | ~1,250 | Table ops, queries |

**Budget guidance:**
- Under 5,000 tokens (≤3 servers): comfortable for most conversations
- 5,000–10,000 tokens: noticeable compression of available context
- Over 10,000 tokens (5+ servers): model reasoning quality degrades; split into separate sessions

---

## 3. AWS MCP Server Catalog

All servers use `uvx` (Python). Pin versions in production configs — `uvx awslabs.eks-mcp-server` pulls latest on every invocation.

```bash
# Look up current version before pinning
pip index versions awslabs.eks-mcp-server 2>/dev/null | head -1
# or: curl -s https://pypi.org/pypi/awslabs.eks-mcp-server/json | jq -r .info.version
```

**Version pin syntax in MCP config:**
```json
{
  "command": "uvx",
  "args": ["awslabs.eks-mcp-server==1.2.3", "--region", "eu-west-1"]
}
```

**Transport:** Use `stdio` for all local servers. SSE transport was removed from awslabs servers in May 2025. Streamable HTTP is available for remote deployments only.

---

## 4. Profile Type Detection

Read `~/.aws/config` and classify each `[profile name]` block:

| Type | Detection signal | Example |
|------|-----------------|---------|
| SSO | `sso_start_url` present | `sso_start_url = https://myorg.awsapps.com/start` |
| Assumed role | `role_arn` + `source_profile` | `role_arn = arn:aws:iam::123456789:role/PlatformEngineer` |
| Granted | `granted_sso_*` keys or `assume` binary in PATH | `granted_sso_account_id = 123456789` |
| Static | `aws_access_key_id` directly in profile | **Warn:** rotate to SSO |

**Detect Granted:**
```bash
which assume 2>/dev/null && echo "Granted installed" || echo "Granted not found"
# Granted profiles also show: granted_sso_account_id, granted_sso_role_name
```

**Environment tag file:** `~/.aws-profile-tags.yaml` maps profile names to environment labels:
```yaml
prod-platform-eu: prod
prod-platform-us: prod
staging-assume: staging
dev-sandbox: dev
security: shared-services
```

If this file does not exist, run `/platform-skills:aws-profile discover` (see `commands/aws-profile.md`) and it will generate a starter file from profile name heuristics for you to review.

---

## 5. Auth Flows

### SSO Login
```bash
aws sso login --profile prod-platform-eu
# Verify:
aws sts get-caller-identity --profile prod-platform-eu
```

### Granted Assume
```bash
assume prod-platform-eu
# Or with a duration override:
assume prod-platform-eu --duration 4h  # Granted v0.1.18+; older versions use seconds
# Verify:
aws sts get-caller-identity
```

### Role Chain Validation

For profiles with `role_arn` + `source_profile`, validate the full chain bottom-up:
```bash
# 1. Validate the source profile first
aws sts get-caller-identity --profile dev-sso

# 2. Then validate the target profile
aws sts get-caller-identity --profile staging-assume

# 3. Visualise the chain
grep -A 5 "\[profile staging-assume\]" ~/.aws/config
```

**Multi-hop chain example:**
```
identity-sso (111111111)
  └── assume → security-role (222222222)
      └── assume → prod-platform-eu (123456789)  ← target profile
```

If step 1 fails, fix the source profile before debugging the target.

### Static profile (warn and migrate)
```
⚠ Static credentials in ~/.aws/credentials are long-lived and do not expire cleanly.
  Rotate to SSO: configure IAM Identity Center and update ~/.aws/config.
  Interim: set a short session duration in the profile.
```

---

## 6. Credential Lifecycle

Two cache locations with different TTLs:

| Cache | Location | TTL | What expires |
|-------|----------|-----|-------------|
| SSO token | `~/.aws/sso/cache/*.json` | 8–12h (org-configured) | All profiles using this SSO session |
| Assumed role | `~/.aws/cli/cache/*.json` | 1h default | Specific role assumption |
| Granted | `~/.granted/` | Org-configured | Granted session |

**Parse expiry manually:**
```bash
# SSO cache — find the active token
cat ~/.aws/sso/cache/*.json | python3 -c "
import json, sys, datetime
for line in sys.stdin:
    try:
        d = json.loads(line)
        if 'expiresAt' in d:
            exp = datetime.datetime.fromisoformat(d['expiresAt'].replace('Z','+00:00'))
            ttl = exp - datetime.datetime.now(datetime.timezone.utc)
            print(f\"Expires: {d['expiresAt']} | TTL: {ttl}\")
    except: pass
"

# Assumed role cache
ls -la ~/.aws/cli/cache/
cat ~/.aws/cli/cache/*.json | python3 -c "
import json, sys, datetime
for d in [json.loads(l) for l in sys.stdin if l.strip()]:
    exp = d.get('Credentials',{}).get('Expiration','')
    if exp:
        print(f\"Role creds expire: {exp}\")
"
```

**Traffic-light thresholds:**
- ✓ Green: TTL > 30 minutes
- ⚠ Amber: TTL 10–30 minutes
- ✗ Red: TTL < 10 minutes or EXPIRED

**Why MCP servers go stale:** An MCP server running as a long-lived process inherits credentials at startup. When the SSO token or role creds expire, the running server continues using the expired token until it is restarted — `ExpiredTokenException` is the symptom.

---

## 7. credential_process Pattern

`credential_process` is the structural fix for stale credentials. Instead of the SDK caching credentials internally, it calls an external binary on every API call that needs fresh credentials.

**Configure in `~/.aws/config`:**

**Option A — SSO via Granted (recommended if you use Granted):**
```ini
[profile prod-platform-eu]
sso_start_url = https://myorg.awsapps.com/start
sso_region = eu-west-1
sso_account_id = 123456789
sso_role_name = PowerUser
region = eu-west-1
credential_process = granted credential-process --profile prod-platform-eu
```

**Option B — SSO via aws-vault:**
```ini
[profile prod-platform-eu]
credential_process = aws-vault export --format=json prod-platform-eu
```

**Option C — Assumed role chain (aws-vault handles the full chain):**
```ini
[profile staging-assume]
credential_process = aws-vault export --format=json staging-assume
```

(These are mutually exclusive — pick the one that matches your toolchain.)

**Verify it works:**
```bash
aws sts get-caller-identity --profile prod-platform-eu
# Should return without any cached token — fetches live via credential_process
```

**MCP config with credential_process profile:**
```json
{
  "mcpServers": {
    "eks-prod-eu": {
      "command": "uvx",
      "args": ["awslabs.eks-mcp-server==1.2.3", "--region", "eu-west-1"],
      "env": {
        "AWS_PROFILE": "prod-platform-eu",
        "AWS_REGION": "eu-west-1"
      }
    }
  }
}
```

When `prod-platform-eu` has `credential_process` configured, `AWS_PROFILE` in the MCP env block is safe — the SDK will call `credential_process` for every API call instead of using a cached token.

---

## 8. Config File Locations

| Host | Scope | Path |
|------|-------|------|
| VS Code / Copilot | Global (all workspaces) | `~/.vscode/mcp.json` |
| VS Code / Copilot | Workspace (current repo) | `.vscode/mcp.json` |
| Claude Code | Global | `~/.claude/settings.json` → `mcpServers` key |

**Rule:** Put 0–1 servers in global config (docs lookup only). Put task-specific servers in workspace `.vscode/mcp.json`. Never put prod-credential-backed servers in global config.

**Always-on global example (`~/.vscode/mcp.json`):**
```json
{
  "mcpServers": {
    "aws-docs": {
      "command": "uvx",
      "args": ["awslabs.aws-documentation-mcp-server==0.1.3"],
      "env": {}
    }
  }
}
```

---

## 9. VS Code Input Variables

VS Code supports interactive profile selection via `${input:variableId}` in `mcp.json`. This avoids hardcoding profile names:

```json
{
  "inputs": [
    {
      "id": "awsProfile",
      "type": "promptString",
      "description": "AWS profile name — run 'aws-profile discover' to list available profiles",
      "default": "dev-sandbox"
    },
    {
      "id": "awsRegion",
      "type": "promptString",
      "description": "AWS region",
      "default": "eu-west-1"
    }
  ],
  "mcpServers": {
    "eks": {
      "command": "uvx",
      "args": ["awslabs.eks-mcp-server==1.2.3", "--region", "${input:awsRegion}"],
      "env": {
        "AWS_PROFILE": "${input:awsProfile}",
        "AWS_REGION": "${input:awsRegion}"
      }
    }
  }
}
```

VS Code prompts the engineer for profile and region when the server starts.

**When to use input variables vs `switch` command:**
- Input variables: VS Code only, interactive per-session, good for teams who change accounts frequently
- `switch` command: patches hardcoded values, works for both VS Code and Claude Code, good for long-lived workspace configs (see `commands/aws-profile.md` → Mode: switch)

These are separate patterns — not interchangeable.

---

## 10. Team Sharing Pattern

Never commit `mcp.json` with real profile names to git — profile names leak account structure. Use a template:

**`.vscode/mcp.json.template`** (commit this):
```json
{
  "_setup": "Copy to .vscode/mcp.json and replace AWS_PROFILE and AWS_REGION placeholders",
  "mcpServers": {
    "eks": {
      "command": "uvx",
      "args": ["awslabs.eks-mcp-server==1.2.3", "--region", "${AWS_REGION}"],
      "env": {
        "AWS_PROFILE": "${AWS_PROFILE}",
        "AWS_REGION": "${AWS_REGION}"
      }
    },
    "cloudwatch": {
      "command": "uvx",
      "args": ["awslabs.cloudwatch-mcp-server==0.2.1"],
      "env": {
        "AWS_PROFILE": "${AWS_PROFILE}",
        "AWS_REGION": "${AWS_REGION}"
      }
    }
  }
}
```

**`.gitignore`** entries:
```
# MCP configs with real credentials/profile names
.vscode/mcp.json
!.vscode/mcp.json.template
```

**Hydration one-liner** (new engineer onboarding):
```bash
AWS_PROFILE=dev-sandbox AWS_REGION=eu-west-1 \
  envsubst < .vscode/mcp.json.template > .vscode/mcp.json
```

---

## 11. Multi-Region Handling

AWS MCP servers that interact with regional services need both `AWS_PROFILE` and `AWS_REGION`. Do not rely on the default region in `~/.aws/config` — make it explicit in every server entry.

**Always set both:**
```json
{
  "env": {
    "AWS_PROFILE": "prod-platform-eu",
    "AWS_REGION": "eu-west-1"
  }
}
```

**EKS specifically:** Pass `--region` in args AND set `AWS_REGION` in env — some EKS MCP server operations use the CLI flag, others read the env var:
```json
{
  "command": "uvx",
  "args": ["awslabs.eks-mcp-server==1.2.3", "--region", "eu-west-1"],
  "env": {
    "AWS_PROFILE": "prod-platform-eu",
    "AWS_REGION": "eu-west-1"
  }
}
```

---

## 12. Multi-Account EKS

One EKS MCP server instance = one AWS profile = one account. For engineers working across multiple accounts, generate named instances:

```json
{
  "mcpServers": {
    "eks-prod-eu": {
      "command": "uvx",
      "args": ["awslabs.eks-mcp-server==1.2.3", "--region", "eu-west-1"],
      "env": { "AWS_PROFILE": "prod-platform-eu", "AWS_REGION": "eu-west-1" },
      "_account": "123456789 | prod | PowerUser"
    },
    "eks-prod-us": {
      "command": "uvx",
      "args": ["awslabs.eks-mcp-server==1.2.3", "--region", "us-east-1"],
      "env": { "AWS_PROFILE": "prod-platform-us", "AWS_REGION": "us-east-1" },
      "_account": "234567890 | prod | PowerUser"
    },
    "eks-staging": {
      "command": "uvx",
      "args": ["awslabs.eks-mcp-server==1.2.3", "--region", "eu-west-1"],
      "env": { "AWS_PROFILE": "staging-assume", "AWS_REGION": "eu-west-1" },
      "_account": "345678901 | staging | Developer"
    }
  }
}
```

**Token cost:** 3 EKS instances = ~6,000 tokens. Use only when cross-account correlation is the explicit goal — for single-account work, use one instance.

---

## 13. Health Check Checklist

Run in order — each layer must pass before checking the next:

```bash
# 1. Token valid
aws sts get-caller-identity --profile <profile>
# Expected: JSON with Account, UserId, Arn

# 2. Server binary available
uvx awslabs.eks-mcp-server --help 2>&1 | head -5
# Expected: help text, not "command not found"

# 3. Server responds to tools/list
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | AWS_PROFILE=<profile> AWS_REGION=eu-west-1 uvx awslabs.eks-mcp-server 2>/dev/null
# Expected: JSON with "tools" array

# 4. IAM has minimum permissions
aws eks list-clusters --profile <profile> --region eu-west-1
# Expected: cluster list (empty list is fine, AccessDenied is not)
```

If step 1 fails → run `login`. If step 2 fails → `uvx` not installed or package name wrong. If step 3 fails → server startup error, check stderr. If step 4 fails → IAM permissions missing.

---

## 14. Prod Safety

Any profile tagged `prod` or with a name containing `prod` or `production` requires extra care.

**Switch guard:** Always confirm before patching prod-profile configs:
```
⚠ WARNING: You are switching to prod-platform-eu (Account: 123456789, env: prod).
  This will update MCP server configs to use production credentials.
  Any AI-driven operations will execute against production.
  
  Pass --confirm to proceed.
```

**Recommended practice:**
- Use `ReadOnly` permission set for MCP servers in prod accounts — restrict to `Get*`, `List*`, `Describe*`
- Never configure write-capable MCP servers (e.g. EKS with deploy permissions) against prod in always-on global config
- Put prod-backed servers in workspace config only, committed to ops-specific repos with appropriate access controls

---

## 15. Starter Kits

Curated minimal server sets — use these as the starting point, not the full catalog.

| Kit | Servers | ~Tokens | Best for |
|-----|---------|---------|---------|
| `eks-debug` | eks + cloudwatch | ~3,750 | Cluster troubleshooting |
| `observe` | cloudwatch + prometheus | ~2,750 | Metrics and alerting |
| `knowledge` | aws-docs + bedrock-kb | ~1,250 | AWS research + internal KB |
| `deploy` | aws-api + serverless | ~3,750 | Serverless CI/CD debugging |
| `cost` | billing-cost-management | ~1,000 | Cost investigation |

See `examples/mcp/aws-multiprofile/starter-kits/` for ready-to-use JSON files.

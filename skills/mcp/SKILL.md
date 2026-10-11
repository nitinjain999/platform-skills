---
name: mcp
description: MCP server and client development — scaffold, implement tools/resources/prompts, validate schemas, debug protocol compliance, and deploy with auth and rate limiting.
argument-hint: "[create|review|debug] [typescript|python] [description]"
title: "MCP Command"
sidebar_label: "mcp"
custom_edit_url: null
---

Build, review, or debug an MCP (Model Context Protocol) server or client.

## Mode: create

Scaffold a production-ready MCP server.

Steps:
1. Ask for: language (TypeScript or Python), transport (stdio / HTTP+SSE), list of tools and resources needed
2. Generate project scaffold with correct SDK setup
3. Implement tool handlers with Zod (TypeScript) or Pydantic (Python) schema validation
4. Add resource providers and prompt templates as needed
5. Configure transport layer
6. Add error handling — return `isError: true` content, never throw unhandled exceptions to clients
7. Add authentication and rate limiting for HTTP transports
8. Provide MCP Inspector test commands and expected responses
9. Add deployment checklist (env vars, secrets, logging)

**Validation:**
```bash
# Smoke-test the MCP server before connecting a host
npx @modelcontextprotocol/inspector <your-server-command>
# This opens an interactive inspector — verify: tools list, resources list, no startup errors
# If the server is not discovered by the host, run /platform-skills:mcp debug
```

Reference: `references/mcp.md` → Protocol Fundamentals, TypeScript SDK, Python SDK

## Mode: review

Review an existing MCP server or client implementation.

Evaluate in priority order:
1. **Protocol compliance** — JSON-RPC 2.0 correctness, proper capability negotiation, well-formed content arrays
2. **Schema validation** — all tool inputs validated with Zod/Pydantic; no `z.any()` or empty schemas
3. **Security** — no credentials in tool responses or resource content; auth on HTTP transports; rate limiting present
4. **Error handling** — errors return `isError: true` with a message, not unhandled exceptions
5. **Transport** — correct transport for the use case; no blocking sync code in async transports

Output: Critical (must fix) / Improvement (should fix) / Note (informational)

Reference: `references/mcp.md` → Security, Error Handling, Testing and Debugging

## Mode: debug

Diagnose MCP protocol or integration failures.

Classify the failure:
- **Transport** — connection refused, EOF, serialisation error
- **Protocol** — malformed JSON-RPC, missing `id`, wrong method names
- **Schema** — Zod/Pydantic validation rejection, unexpected input types
- **Handler** — unhandled exception, timeout, wrong return shape
- **Integration** — tool not appearing in host, capabilities mismatch

Evidence to collect:
```bash
# Run MCP Inspector to verify protocol compliance
npx @modelcontextprotocol/inspector node dist/index.js

# Smoke-test via stdio
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | node dist/index.js

# Check for schema errors
node -e "require('./dist/index.js')" 2>&1
```

Provide: observed symptom → likely root cause → evidence command → fix → validation step

## Mode: configure-aws

Generate version-pinned, credential_process-backed MCP server configs for AWS services, with upfront cost warnings and CLI-first alternatives.

```
/platform-skills:mcp configure-aws [service|kit] [--profile <profile>] [--region <region>] [--host vscode|claude|both] [--scope global|workspace] [--multi-account]
```

**Examples:**
```
/platform-skills:mcp configure-aws eks-debug --profile prod-platform-eu --region eu-west-1 --host both
/platform-skills:mcp configure-aws eks --profile dev-sandbox --host vscode --scope workspace
/platform-skills:mcp configure-aws knowledge --host claude
/platform-skills:mcp configure-aws eks --profile prod-eu --region eu-west-1 --multi-account
```

### Step 0: Gather Inputs (interactive — fires when any required value is missing)

When the user invokes `configure-aws` without arguments, or omits any required value, prompt for each missing piece **one question at a time** before proceeding.

**Question 1 — Service or kit** (skip if already provided as positional arg):
```
Which AWS service or starter kit do you need?

Services:
  eks         EKS cluster ops, nodegroups           (~2,000 tokens)
  cloudwatch  Logs, metrics, alarms                 (~1,750 tokens)
  prometheus  AMP metrics, rule groups              (~1,000 tokens)
  iam         IAM queries, read-only                (~1,500 tokens)
  bedrock-kb  Knowledge base retrieve + generate    (~750 tokens)
  docs        Real-time AWS documentation           (~500 tokens)
  api         All AWS services, catch-all           (~2,500 tokens)
  billing     Cost Explorer, budgets                (~1,000 tokens)
  serverless  SAM, Lambda lifecycle                 (~1,250 tokens)
  dynamodb    Table ops, queries                    (~1,250 tokens)

Starter kits (pre-bundled):
  eks-debug   eks + cloudwatch                      (~3,750 tokens)
  observe     cloudwatch + prometheus               (~2,750 tokens)
  knowledge   docs + bedrock-kb                     (~1,250 tokens)
  deploy      api + serverless                      (~3,750 tokens)
  cost        billing                               (~1,000 tokens)

Enter service or kit name:
```

**Question 2 — Host** (skip if `--host` provided):
```
Which tool are you configuring for?
  1. VS Code
  2. Claude Code
  3. Both

Enter 1, 2, or 3:
```

**Question 3 — AWS profile** (skip if `--profile` provided):

Read `~/.aws/config`, list available profiles with type and environment tag (from `~/.aws-profile-tags.yaml` if present):
```
Which AWS profile should MCP servers use?

Available profiles (from ~/.aws/config):
  prod-platform-eu   SSO          [prod]     123456789
  staging-assume     assumed-role [staging]  456789123
  dev-sandbox        SSO          [dev]      987654321

Enter profile name (or press enter for no profile — uses ambient credentials):
```

If `~/.aws/config` is not readable or has no profiles, show: `Could not read ~/.aws/config. Enter profile name manually (or press enter to skip):`

**Question 4 — Region** (skip if `--region` provided):

Detect the profile's `region` field from `~/.aws/config` and offer it as the default:
```
AWS region? [detected from profile 'prod-platform-eu': eu-west-1]
Press enter to accept or type a different region:
```

If no region is detected in the profile: `AWS region? (e.g. us-east-1):`

**Question 5 — Scope** (VS Code only; skip if `--scope` provided):
```
VS Code config scope?
  1. Workspace — .vscode/mcp.json (this project only)
  2. Global    — applies to all VS Code windows

Enter 1 or 2:
```

**Question 6 — Multi-account** (`eks` service only; skip if `--multi-account` provided or service is not eks):
```
Generate named instances for all prod-tagged profiles? (multi-account mode)
  This creates eks-prod-eu, eks-prod-us, etc. from ~/.aws-profile-tags.yaml.
  Requires ~/.aws-profile-tags.yaml with env: prod entries.

[y/N]:
```

After collecting all answers, confirm before proceeding:
```
Summary:
  Service/kit : eks-debug (eks + cloudwatch)
  Host        : both (VS Code + Claude Code)
  Profile     : prod-platform-eu
  Region      : eu-west-1
  VS Code scope: workspace

Proceeding with cost check...
```

Then continue with Steps 1–4 below using the collected values.

---

### Step 1: Cost Warning

Before generating any config, show tool count and token cost. If total exceeds 5,000 tokens, flag it:

```
Servers requested: eks-mcp-server + cloudwatch-mcp-server

  awslabs.eks-mcp-server           ~40 tools   ~2,000 tokens
  awslabs.cloudwatch-mcp-server    ~35 tools   ~1,750 tokens
  ──────────────────────────────────────────────────────────
  Total                            ~75 tools   ~3,750 tokens

✓ Within recommended budget (<5,000 tokens). Continue? [y/N]
```

If over 5,000 tokens:
```
⚠ Over budget — ~8,500 tokens will be consumed by tool definitions before any conversation.
  This will noticeably compress available context for reasoning.
  Recommended: split into separate sessions, one kit per task.
  Continue anyway? [y/N]
```

### Step 2: CLI-First Check

For simple single-service requests, show the CLI alternative before generating MCP config:

```
💡 For common EKS queries, the AWS CLI costs zero context:

  aws eks list-clusters --profile prod-platform-eu --region eu-west-1
  aws eks describe-cluster --name my-cluster --profile prod-platform-eu --region eu-west-1
  aws eks list-nodegroups --cluster-name my-cluster --profile prod-platform-eu

MCP adds value when the AI needs to chain calls — e.g., list clusters → describe all nodegroups →
correlate with CloudWatch alarms → identify degraded nodes → suggest remediation.

Is that the task you need? [y to continue with MCP / n to use CLI]
```

### Step 3: credential_process Check

Before generating the config, check whether the target profile in `~/.aws/config` has `credential_process` configured:

- **Has credential_process** → generate config with `AWS_PROFILE` env var (credential_process handles refresh)
- **No credential_process** → warn and emit both the MCP config AND the recommended `~/.aws/config` stanza:

```
⚠ Profile 'prod-platform-eu' does not have credential_process configured.
  MCP servers using this profile will fail silently when the SSO token expires (TTL: ~8h).

  Add this to ~/.aws/config for automatic credential refresh:

  [profile prod-platform-eu]
  # ... existing fields ...
  credential_process = granted credential-process --profile prod-platform-eu

  See: references/aws-mcp-profiles.md → credential_process Pattern
```

### Step 4: Config Generation

Emit ready-to-paste JSON for the target host(s). Always version-pin. Always set both `AWS_PROFILE` and `AWS_REGION`. Always include an `_account` comment.

**VS Code (`.vscode/mcp.json`):**
```json
{
  "mcpServers": {
    "eks-prod-eu": {
      "command": "uvx",
      "args": ["awslabs.eks-mcp-server==VERSION", "--region", "eu-west-1"],
      "env": {
        "AWS_PROFILE": "prod-platform-eu",
        "AWS_REGION": "eu-west-1"
      },
      "_account": "Account: 123456789 | Env: prod | Permission: PowerUser"
    },
    "cloudwatch-prod-eu": {
      "command": "uvx",
      "args": ["awslabs.cloudwatch-mcp-server==VERSION"],
      "env": {
        "AWS_PROFILE": "prod-platform-eu",
        "AWS_REGION": "eu-west-1"
      },
      "_account": "Account: 123456789 | Env: prod | Permission: PowerUser"
    }
  }
}
```

**Claude Code (`~/.claude/settings.json` → `mcpServers`):**
```json
{
  "eks-prod-eu": {
    "command": "uvx",
    "args": ["awslabs.eks-mcp-server==VERSION", "--region", "eu-west-1"],
    "env": {
      "AWS_PROFILE": "prod-platform-eu",
      "AWS_REGION": "eu-west-1"
    },
    "_account": "Account: 123456789 | Env: prod | Permission: PowerUser"
  }
}
```

Replace `VERSION` with the current version from PyPI:
```bash
pip index versions awslabs.eks-mcp-server 2>/dev/null | head -1
```

### Multi-Account Mode (`--multi-account`)

When `--multi-account` is passed for the `eks` service, generate distinct named instances for each prod-tagged profile in `~/.aws-profile-tags.yaml`:

```json
{
  "mcpServers": {
    "eks-prod-eu": {
      "command": "uvx",
      "args": ["awslabs.eks-mcp-server==VERSION", "--region", "eu-west-1"],
      "env": { "AWS_PROFILE": "prod-platform-eu", "AWS_REGION": "eu-west-1" },
      "_account": "123456789 | prod-eu"
    },
    "eks-prod-us": {
      "command": "uvx",
      "args": ["awslabs.eks-mcp-server==VERSION", "--region", "us-east-1"],
      "env": { "AWS_PROFILE": "prod-platform-us", "AWS_REGION": "us-east-1" },
      "_account": "234567890 | prod-us"
    }
  }
}
```

Show updated token cost after generating multi-instance config.

### AWS MCP Server Catalog

| Kit / Service | Package | ~Tokens | Use case |
|--------------|---------|---------|---------|
| `eks` | `awslabs.eks-mcp-server` | ~2,000 | Cluster ops, nodegroups |
| `cloudwatch` | `awslabs.cloudwatch-mcp-server` | ~1,750 | Logs, metrics, alarms |
| `prometheus` | `awslabs.prometheus-mcp-server` | ~1,000 | AMP metrics, rule groups |
| `iam` | `awslabs.iam-mcp-server` | ~1,500 | IAM queries (read-only) |
| `bedrock-kb` | `awslabs.bedrock-kb-retrieval-mcp-server` | ~750 | KB retrieve + generate |
| `docs` | `awslabs.aws-documentation-mcp-server` | ~500 | Real-time AWS docs |
| `api` | `awslabs.aws-api-mcp-server` | ~2,500 | All AWS services (catch-all) |
| `billing` | `awslabs.billing-cost-management-mcp-server` | ~1,000 | Cost Explorer, budgets |
| `serverless` | `awslabs.aws-serverless-mcp-server` | ~1,250 | SAM, Lambda lifecycle |
| `dynamodb` | `awslabs.dynamodb-mcp-server` | ~1,250 | Table ops, queries |

**Starter kits** (pass kit name instead of service):

| Kit | Servers | ~Tokens |
|-----|---------|---------|
| `eks-debug` | eks + cloudwatch | ~3,750 |
| `observe` | cloudwatch + prometheus | ~2,750 |
| `knowledge` | docs + bedrock-kb | ~1,250 |
| `deploy` | api + serverless | ~3,750 |
| `cost` | billing | ~1,000 |

Reference: `references/aws-mcp-profiles.md`

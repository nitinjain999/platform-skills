---
name: aws-profile
description: AWS profile management for MCP servers — discover profiles across SSO, Granted, and assumed-role chains, check credential TTL, switch profiles across VS Code and Claude Code MCP configs, and scan AWS Organization accounts.
argument-hint: "[discover|status|switch <profile>|login <profile>|org-scan] [flags]"
---

Manage AWS profiles for MCP server configurations across VS Code (GitHub Copilot) and Claude Code.

Reference: `references/aws-mcp-profiles.md`

---

## Mode: discover

Parse `~/.aws/config` and output a classified profile table with credential TTL.

```
aws-profile discover [--type sso|assume-role|granted|static] [--env prod|staging|dev] [--account <id>] [--chain] [--expired]
```

**Output:**
```
Profile               Type         Account ID    Env Tag    Permission Set    Expires      TTL
prod-platform-eu      sso          123456789     prod       PowerUser         14:32 UTC    47m ✓
staging-assume        assume-role  456789123     staging    -                 13:58 UTC    13m ⚠
dev-sandbox           granted      987654321     dev        Developer         09:00 UTC    EXPIRED ✗
security              static       890123456     -          -                 never        ⚠ rotate
```

**Steps:**

1. Parse `~/.aws/config` — classify each `[profile name]` block by type:
   - SSO: `sso_start_url` present
   - Assumed role: `role_arn` + `source_profile`
   - Granted: `granted_sso_*` keys or `assume` binary in PATH
   - Static: `aws_access_key_id` directly in profile block → warn to rotate

2. Parse `~/.aws/sso/cache/*.json` and `~/.aws/cli/cache/*.json` for `expiresAt` fields. Apply traffic-light TTL:
   - ✓ Green: >30 min
   - ⚠ Amber: 10–30 min
   - ✗ Red: <10 min or expired

3. Read `~/.aws-profile-tags.yaml` for env tags. If the file does not exist, generate a starter file:
   ```yaml
   # ~/.aws-profile-tags.yaml — edit to correct heuristic guesses
   prod-platform-eu: prod    # detected: name contains 'prod'
   staging-assume: staging   # detected: name contains 'stag'
   dev-sandbox: dev          # detected: name contains 'dev'
   security: shared-services # detected: name contains 'security'
   ```
   Print: `Generated ~/.aws-profile-tags.yaml — review and correct environment tags.`

4. Apply filters if flags provided.

**With `--chain`** — show full role assumption chain for assumed-role profiles:
```
staging-assume role chain:
  dev-sso (identity: 111111111)
    └── assume → security-role (222222222)
        └── assume → staging-platform (456789123)  ← this profile
```

Parse the chain by following `source_profile` → `role_arn` links recursively in `~/.aws/config`.

Reference: `references/aws-mcp-profiles.md` → Profile Type Detection, Credential Lifecycle

---

## Mode: status

Show which profile each configured MCP server uses, the credential TTL, and whether the credential method will auto-refresh.

**Note:** `status` reads config files and `~/.aws/sso/cache/` — it does not read the `AWS_PROFILE` shell environment variable, which is per-session and invisible to this command.

```
aws-profile status [--watch] [--all-hosts]
```

**Output:**
```
Profile in MCP configs: prod-platform-eu
  Type: SSO | Account: 123456789 | Permission: PowerUser
  Token expires: 14:32 UTC (47 minutes) ✓

MCP Servers:
  eks-prod-eu      ~/.vscode/mcp.json          credential_process ✓   47m
  cloudwatch       ~/.claude/settings.json      AWS_PROFILE ⚠         47m (will not auto-refresh on expiry)
  eks-prod-us      .vscode/mcp.json            credential_process ✓   47m

⚠ 'cloudwatch' uses raw AWS_PROFILE without credential_process.
  When the token expires, this server will fail silently.
  Fix: add credential_process to the 'prod-platform-eu' profile in ~/.aws/config.
  See: references/aws-mcp-profiles.md → credential_process Pattern
```

**Steps:**

1. Scan `~/.vscode/mcp.json`, `~/.claude/settings.json`, and `.vscode/mcp.json` (if present in cwd). Extract `AWS_PROFILE` from each server's `env` block.
2. For each unique profile found, parse TTL from `~/.aws/sso/cache/` or `~/.aws/cli/cache/`.
3. Check whether the profile in `~/.aws/config` has `credential_process` configured. Flag servers without it as ⚠.
4. If `--watch`: re-run every 60 seconds. Print a warning when any TTL drops below 30 minutes, and a loud alert when any TTL drops below 10 minutes.

---

## Mode: switch

Patch `AWS_PROFILE` (and `AWS_REGION` if `--region` provided) in MCP server config files. Requires `--confirm` for any profile tagged `prod` or whose name contains `prod` or `production`.

```
aws-profile switch <profile> [--scope global|workspace] [--server <name>] [--env <tag>] [--region <region>] [--confirm]
```

**Examples:**
```
aws-profile switch prod-platform-eu --scope workspace --confirm
aws-profile switch dev-sandbox --scope global
aws-profile switch staging-assume --server eks-staging
aws-profile switch --env prod --confirm
```

**Steps:**

1. Resolve target profile:
   - If `--env <tag>`: look up profile in `~/.aws-profile-tags.yaml` that matches the tag. Error if multiple profiles share the tag — require explicit profile name.
   - Otherwise: use the profile name directly.

2. Safety check — if profile name contains `prod` or `production` or is tagged `prod` in `~/.aws-profile-tags.yaml`:
   ```
   ⚠ WARNING: Switching to prod-platform-eu (tagged: prod, Account: 123456789).
     MCP operations will run against production.
     Pass --confirm to proceed.
   ```
   Halt without `--confirm`.

3. Determine target files by `--scope`:
   - `global` (default): `~/.vscode/mcp.json` + `~/.claude/settings.json`
   - `workspace`: `.vscode/mcp.json` in current directory only
   - `--server <name>`: patch only that named entry across all scopes

4. For each matched server entry, update `env.AWS_PROFILE` to the new profile. If `--region` provided, also update `env.AWS_REGION` and any `--region` arg in the `args` array.

5. Show a diff of what was patched:
   ```
   Patched 3 server entries:
     eks-prod-eu     ~/.vscode/mcp.json          AWS_PROFILE: old-profile → prod-platform-eu
     cloudwatch      ~/.claude/settings.json     AWS_PROFILE: old-profile → prod-platform-eu
     eks-staging     .vscode/mcp.json            AWS_PROFILE: old-profile → prod-platform-eu
   ```

6. Always emit restart instructions:
   ```
   ⚠ Restart required — config changes do not affect running server processes:
     VS Code / Copilot: Cmd+Shift+P → "MCP: Restart Server"  (or: Developer: Reload Window)
     Claude Code: exit this session and start a new one
   ```

Reference: `references/aws-mcp-profiles.md` → Config File Locations, Prod Safety

---

## Mode: login

Detect the profile type and emit the correct authentication command. After successful login, run `status` automatically.

```
aws-profile login <profile>
```

**Steps:**

1. Read `~/.aws/config` for `[profile <name>]`. Classify type.

2. Emit and explain the auth command:

   **SSO:**
   ```
   aws sso login --profile prod-platform-eu
   
   This opens a browser for SSO authentication. After approval, your token
   is cached in ~/.aws/sso/cache/ (TTL: 8–12h, org-configured).
   ```

   **Granted:**
   ```
   assume prod-platform-eu
   
   Granted will authenticate via SSO and cache credentials.
   If prompted for duration, 4h is a reasonable default for a workday session.
   ```

   **Assumed role:**
   ```
   The source profile 'dev-sso' must be authenticated first:
     aws sso login --profile dev-sso
   
   Then validate the role assumption:
     aws sts get-caller-identity --profile staging-assume
   ```

   **Static:**
   ```
   ⚠ Static credentials do not have a login flow — they are long-lived and do not expire cleanly.
     Recommendation: Rotate this profile to AWS SSO (IAM Identity Center).
     See: references/aws-mcp-profiles.md → Auth Flows
   ```

3. After emitting the command, run `status` to show TTL confirmation.

Reference: `references/aws-mcp-profiles.md` → Auth Flows

---

## Mode: org-scan

List all accounts in the AWS Organization and cross-reference with configured profiles. Requires `organizations:ListAccounts` permission — available only from the management account or a delegated admin account.

```
aws-profile org-scan [--profile <mgmt-profile>] [--generate-profiles]
```

**Output:**
```
AWS Organization accounts (via profile: org-management):

Account ID    Account Name          Env Tag    Profiles configured
123456789     prod-platform         prod       ✓ prod-platform-eu, prod-platform-us
456789123     staging               staging    ✓ staging-assume
789012345     dev-sandbox-1         dev        ✓ dev-sandbox
890123456     security-tooling      -          ✗ NO PROFILE — add to ~/.aws/config
901234567     shared-services       -          ✗ NO PROFILE — add to ~/.aws/config

2 accounts have no profile configured.
Run with --generate-profiles to emit ~/.aws/config stanzas for them.
```

**With `--generate-profiles`** — emit SSO-based stanzas for unconfigured accounts:
```ini
# Add to ~/.aws/config — replace ROLE_NAME with your SSO permission set

[profile security-tooling]
sso_start_url = https://myorg.awsapps.com/start
sso_region = eu-west-1
sso_account_id = 890123456
sso_role_name = ROLE_NAME
region = eu-west-1
credential_process = granted credential-process --profile security-tooling

[profile shared-services]
sso_start_url = https://myorg.awsapps.com/start
sso_region = eu-west-1
sso_account_id = 901234567
sso_role_name = ROLE_NAME
region = eu-west-1
credential_process = granted credential-process --profile shared-services
```

**Steps:**

1. Run: `aws organizations list-accounts --profile <mgmt-profile> --output json`
2. For each account, check if any profile in `~/.aws/config` references that account ID via `sso_account_id` or call `aws sts get-caller-identity --profile <p>` to resolve.
3. Cross-reference `~/.aws-profile-tags.yaml` for env tags.
4. If `--generate-profiles`: generate SSO stanzas using the `sso_start_url` and `sso_region` from an existing SSO profile as the template.

**Note:** `organizations:ListAccounts` requires management account access. Most platform engineers work from member accounts and will not have this permission. This mode is intended for platform leads and account vending workflows.

Reference: `references/aws-mcp-profiles.md` → Profile Type Detection, credential_process Pattern

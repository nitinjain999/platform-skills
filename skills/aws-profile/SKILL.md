---
name: aws-profile
description: Manage AWS profiles for MCP servers — discover SSO, Granted and role-chain profiles, check authentication with STS, switch configured profiles, and scan AWS Organization accounts. TTL is unknown unless the user shares an expiry timestamp without credentials.
argument-hint: "[discover|status|switch <profile>|login <profile>|org-scan] [flags]"
title: "AWS Profile Command"
sidebar_label: "aws-profile"
custom_edit_url: null
---

Manage AWS profiles for MCP server configurations across VS Code (GitHub Copilot) and Claude Code.

Reference: `references/aws-mcp-profiles.md`

## Credential boundary

List profiles with `aws configure list-profiles`. Read only these non-secret settings with `aws configure get <key> --profile <profile>`: `sso_session`, `sso_start_url`, `sso_region`, `sso_account_id`, `sso_role_name`, `role_arn`, `source_profile`, `region`, `granted_sso_account_id`, `granted_sso_role_name`. A missing setting is normal. Never retrieve access keys, session tokens, raw config files or credential caches, or execute `credential_process` to inspect its output. Let the AWS CLI handle authentication for the selected profile.

The AWS CLI continues to use its native credential chain, including `credential_process`. Keep the SSO, Granted and role-chain authentication setup guidance in `references/aws-mcp-profiles.md`.

For TTL, use only a profile-specific expiration timestamp the user has shared without credentials. Otherwise display `unknown`; successful authentication does not establish an expiry time. Parse MCP config files locally and return only server names, paths, `AWS_PROFILE` and `AWS_REGION`, since other fields can contain secrets. Do not print entire config files or diffs of unrelated fields.

---

## Interactive Wizard (fires when no mode is provided)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. discover  — list AWS profiles with type, account ID, env tag, and expiry when shared
  2. status    — show configured MCP profiles and check current authentication
  3. switch    — update MCP config files to use a different profile
  4. login     — authenticate and refresh credentials for a specific profile
  5. org-scan  — list all AWS Organization accounts and cross-reference with configured profiles

Enter 1–5 or mode name:
```

**Q2 — Mode-specific follow-up** (one question, after mode is selected):
- **discover**: `Any filters? (e.g. --expired to show only expired, --type sso, --env prod) — or press enter to list all:`
- **switch**: List profiles with `aws configure list-profiles`, then ask: `Which profile should MCP servers switch to?`
- **login**: List profiles with `aws configure list-profiles`, then ask: `Which profile needs authentication?`
- **status**: no follow-up — proceed directly
- **org-scan**: `Which management account profile has organizations:ListAccounts permission? (default: current profile):`

Then proceed into the relevant mode below.

---

## Mode: discover

List profiles and output a classified profile table with TTL where shared expiration metadata is available.

```
aws-profile discover [--type sso|assume-role|granted|static] [--env prod|staging|dev] [--account <id>] [--chain] [--expired]
```

**Output:**
```
Profile               Type         Account ID    Env Tag    Permission Set    Expires      TTL
prod-platform-eu      sso          123456789     prod       PowerUser         14:32 UTC    47m ✓
staging-assume        assume-role  456789123     staging    -                 13:58 UTC    13m ⚠
dev-sandbox           granted      987654321     dev        Developer         09:00 UTC    EXPIRED ✗
security              unknown      890123456     -          -                 unknown      unknown
```

The timestamp examples above assume the user supplied profile-specific expiry metadata. Without it, show `unknown` in both expiry columns.

**Steps:**

1. Run `aws configure list-profiles`, then query only the metadata keys in Credential boundary. Classify each profile by the settings present:
   - SSO: `sso_session` or `sso_start_url` present
   - Assumed role: `role_arn` + `source_profile`
   - Granted: `granted_sso_account_id` or `granted_sso_role_name` present; an `assume` binary alone does not classify every profile
   - Static: only if the user identifies it as static → warn to rotate
   - Otherwise: `unknown`; do not retrieve a key to classify it

2. Calculate TTL only from shared expiration metadata for that profile. Do not read credential caches. Apply traffic-light TTL only when a timestamp is known:
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

4. Apply filters if flags provided. For `--expired`, list confirmed expired entries and report profiles with unknown TTL separately; unknown does not mean expired or healthy.

**With `--chain`** — show full role assumption chain for assumed-role profiles:
```
staging-assume role chain:
  dev-sso (identity: 111111111)
    └── assume → security-role (222222222)
        └── assume → staging-platform (456789123)  ← this profile
```

Follow `source_profile` → `role_arn` links recursively with the metadata lookups above.

Reference: `references/aws-mcp-profiles.md` → Profile Type Detection, Credential Lifecycle

---

## Mode: status

Show which profile each configured MCP server uses, authentication status and known credential TTL. Report refresh behaviour only when the configured method is known.

**Note:** MCP config identifies the intended profile; it does not prove which credentials an already-running server holds. Do not inspect credential caches or assume the agent's shell environment matches the server's.

```
aws-profile status [--watch] [--all-hosts]
```

**Output:**
```
Profile in MCP configs: prod-platform-eu
  Type: SSO | Account: 123456789 | Permission: PowerUser
  Authentication: valid (AWS STS check)
  Token expires: unknown (no shared expiration metadata)

MCP Servers:
  eks-prod-eu      ~/.vscode/mcp.json          AWS_PROFILE   TTL unknown
  cloudwatch      ~/.claude/settings.json     AWS_PROFILE   TTL unknown
  eks-prod-us      .vscode/mcp.json            AWS_PROFILE   TTL unknown
```

**Steps:**

1. Extract only server names and the AWS profile/region fields from `~/.vscode/mcp.json`, `~/.claude/settings.json`, and `.vscode/mcp.json` (if present in cwd), using local parsing.
2. For each unique profile, run `aws sts get-caller-identity --profile <profile>` to check authentication; report errors without treating every failure as an expired token. Report TTL from shared metadata or `unknown`.
3. Identify SSO or role-chain settings with the allowed metadata lookups. `AWS_PROFILE` alone does not establish whether a particular server's SDK refreshes credentials; report that as unverified unless checked.
4. If `--watch`: re-run every 60 seconds. Apply TTL warnings only to known timestamps. Report authentication failures separately.

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

**Pre-condition:** If `~/.aws-profile-tags.yaml` does not exist, run `aws-profile discover` first to generate it.

**Steps:**

1. Resolve target profile:
   - If `--env <tag>`: look up the profile in `~/.aws-profile-tags.yaml` that matches the tag — this selects which *profile* to switch to, not which servers to patch. Error if multiple profiles share the tag — require explicit profile name.
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
   - `--server <name>`: patch only that named entry, searching all scope files regardless of `--scope` (overrides scope)

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

1. Query the allowed metadata keys for the selected profile. If the method is unknown, ask which authentication method the user configured instead of inspecting credentials.

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

3. After the user completes login, check the selected profile with `aws sts get-caller-identity --profile <profile>`. Report TTL as `unknown` unless the user shared an expiration timestamp; a successful STS check does not prove a green (>30 min) TTL.

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
   If `--profile` is omitted, let the AWS CLI use its configured credential chain.
2. For each account, compare the allowed `sso_account_id` metadata for listed profiles or call `aws sts get-caller-identity --profile <p>` to resolve.
3. Cross-reference `~/.aws-profile-tags.yaml` for env tags.
4. If `--generate-profiles`: generate SSO stanzas using the `sso_start_url` and `sso_region` from an existing SSO profile as the template.

**Note:** `organizations:ListAccounts` requires management account access. Most platform engineers work from member accounts and will not have this permission. This mode is intended for platform leads and account vending workflows.

Reference: `references/aws-mcp-profiles.md` → Profile Type Detection, credential_process Pattern

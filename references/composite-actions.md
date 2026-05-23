# Composite GitHub Actions Reference

## Composite actions vs reusable workflows

This is the most common architectural question teams face. Both reduce duplication — but they operate at different levels.

| Dimension | Composite action | Reusable workflow |
|---|---|---|
| **Unit of reuse** | Steps within a job | An entire job (or set of jobs) |
| **Calling syntax** | `uses:` inside a job's `steps:` | `uses:` as a top-level `jobs.<id>.uses:` |
| **Secrets** | Must be passed as inputs — `secrets.*` not accessible | Can receive `secrets: inherit` or explicit mapping |
| **Outputs** | `outputs:` in `action.yml` → `steps.<id>.outputs.*` | `outputs:` in the called workflow → `jobs.<id>.outputs.*` |
| **Concurrency** | Inherits the caller job's runner and concurrency | Gets its own runner per job; can declare its own concurrency |
| **Matrix** | Cannot define a matrix — runs once per call | Can define its own `strategy.matrix` |
| **Context visibility** | Sees `github.*`, `runner.*`, `env.*` from caller | Sees its own `github.*`; some caller context is absent |
| **Permissions** | Inherits caller job's token permissions | Must re-declare `permissions:` — cannot inherit |
| **Log grouping** | Steps appear inline in the caller job's log | Jobs appear as separate entries in the workflow run |
| **`if:` conditions** | Applied at the step level | Applied at the job level |

### When to use each

```
Reusing 3–10 steps that always run together → composite action
Reusing an entire job that needs its own runner → reusable workflow
Need secrets:inherit or secrets:inherit shortcut → reusable workflow
Need a matrix strategy defined inside the reused unit → reusable workflow
Caller needs the result as a step output → composite action
Reused unit needs different permissions from caller → reusable workflow
```

### Reusable workflow calling syntax

```yaml
# Reusable workflow — top-level jobs key, not inside steps:
jobs:
  call-build:
    uses: org/actions/.github/workflows/build.yml@v1
    with:
      image_name: my-service
    secrets:
      registry_token: ${{ secrets.REGISTRY_TOKEN }}
```

```yaml
# Composite action — inside a job's steps:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: org/actions/docker-build-push@v1
        with:
          image_name: my-service
```

---

## Using composite actions from private repositories

When a composite action lives in a private repo (not the same repo as the caller), the runner needs permission to read it.

### Pattern 1 — same-repo action (no token needed)

```yaml
# Caller workflow in the same repo as the action
steps:
  - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
  - uses: ./.github/actions/my-action    # relative path — resolves to the checked-out repo
```

No extra token needed. The default `GITHUB_TOKEN` has read access to its own repo.

### Pattern 2 — private cross-repo action via GitHub App (recommended)

Create a GitHub App with `Contents: Read` on the actions repo. Install it on the org or the target repo.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      # 1. Generate a short-lived installation token for the actions repo
      - name: Get GitHub App token
        id: app-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ vars.ACTIONS_APP_ID }}
          private-key: ${{ secrets.ACTIONS_APP_PRIVATE_KEY }}
          repositories: actions   # the repo containing the composite action

      # 2. Check out the actions repo so the runner can find action.yml
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
        with:
          repository: org/actions
          ref: v1
          token: ${{ steps.app-token.outputs.token }}
          path: .actions   # check out into a subdirectory

      # 3. Reference the local copy
      - uses: ./.actions/docker-build-push
        with:
          image_name: my-service
```

**Why App token over PAT:**
- Scoped to specific repos — principle of least privilege
- Short-lived (1 hour max) — no long-term credential to rotate
- Auditable — actions appear as App activity in the audit log
- No personal account dependency — survives employee offboarding

### Pattern 3 — personal access token (avoid in production)

```yaml
- uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
  with:
    repository: org/actions
    token: ${{ secrets.ORG_ACTIONS_PAT }}   # fine-grained PAT, Contents:Read
    path: .actions
- uses: ./.actions/my-action
```

**Risks:** tied to a personal account; requires manual rotation; wide scope if using classic PAT.

### Diagnosing "can't find action.yml"

```
Error: Can't find 'action.yml', 'action.yaml', or 'Dockerfile' under '/home/runner/work/...'
```

Checklist:
1. Is the actions repo private? → needs a token on the checkout step
2. Is `actions/checkout` running before the `uses:` reference?
3. Is the `path:` on the checkout step matching the prefix in the `uses:` path?
4. Does the branch/tag/SHA in `ref:` actually have an `action.yml` at the specified subdirectory?

---

## Organisation action repository strategy

### Mono-repo of actions (recommended for most orgs)

```
org/actions/
├── docker-build-push/action.yml
├── notify-slack/action.yml
├── setup-env/action.yml
└── .github/
    ├── dependabot.yml          (one file — updates all action SHAs)
    └── workflows/
        ├── test-docker-build-push.yml
        ├── test-notify-slack.yml
        └── release.yml         (tags: v1.2.3 → updates org/actions@v1)
```

**Caller:**
```yaml
- uses: org/actions/docker-build-push@v1
- uses: org/actions/notify-slack@v2
```

**Pros:**
- Single dependabot config updates all pinned SHAs at once
- One release workflow, one version tag, one floating major tag
- Easy cross-action discoverability and standardisation
- Atomic changes that span multiple actions ship together

**Cons:**
- A broken release blocks all actions from updating
- Version is shared — can't release `docker-build-push@v2` independently of `notify-slack`

### Per-action repos (use when actions diverge significantly)

```
org/action-docker-build-push/action.yml   → org/action-docker-build-push@v1
org/action-notify-slack/action.yml        → org/action-notify-slack@v1
```

**Pros:**
- Independent versioning and release cadence
- Separate dependabot, separate test workflow
- Can be individually Marketplace-published

**Cons:**
- Each repo needs its own release workflow, dependabot config, test workflow
- Dependabot creates separate PRs in every caller repo for every action
- Hard to enforce consistent standards across many repos

### Decision guide

```
< 5 actions, same team owns all of them    → mono-repo
> 10 actions or multiple owning teams      → per-action repos or domain-grouped repos
Some actions go to Marketplace             → those actions get their own repos; internal ones in mono-repo
Actions have vastly different release cadences → per-action repos
```

### Floating tag strategy (applies to both)

```bash
# On release of v1.2.3:
git tag v1.2.3
git tag -f v1             # update floating major tag
git push origin v1.2.3
git push origin v1 --force

# Callers pinning to @v1 automatically get v1.2.3
# Callers pinning to SHA are unaffected — intentional
```

---

## Contents

- [Composite actions vs reusable workflows](#composite-actions-vs-reusable-workflows)
- [Using composite actions from private repositories](#using-composite-actions-from-private-repositories)
- [Organisation action repository strategy](#organisation-action-repository-strategy)
- [When to use composite vs JavaScript vs Docker](#when-to-use-composite-vs-javascript-vs-docker)
- [Context availability in composite actions](#context-availability-in-composite-actions)
- [OIDC cloud trust configuration](#oidc-cloud-trust-configuration)
- [action.yml anatomy](#actionyml-anatomy)
- [Variables and secrets](#variables-and-secrets)
- [Inputs and outputs](#inputs-and-outputs)
- [Security requirements](#security-requirements)
- [Observability](#observability)
- [Input validation — fail fast](#input-validation--fail-fast)
- [Step control flow](#step-control-flow)
- [File references and scripts](#file-references-and-scripts)
- [Multi-OS patterns](#multi-os-patterns)
- [Idempotency](#idempotency)
- [Timeout and concurrency](#timeout-and-concurrency)
- [Testing](#testing)
- [Breaking changes](#breaking-changes)
- [Versioning and release](#versioning-and-release)
- [Dependabot configuration](#dependabot-configuration)
- [Passing state to post-steps — $GITHUB_STATE](#passing-state-to-post-steps--github_state)
- [Action composition — calling composite from composite](#action-composition--calling-composite-from-composite)
- [Self-hosted runner considerations](#self-hosted-runner-considerations)
- [Ephemeral runner security](#ephemeral-runner-security)
- [Troubleshooting](#troubleshooting)
- [Anti-patterns](#anti-patterns)
- [Production checklist](#production-checklist)

---

## When to use composite vs JavaScript vs Docker

Choose the action type before writing a single line:

| Need | Use | Why |
|---|---|---|
| Shell commands + existing `uses:` steps | **Composite** | Zero overhead, no build step, any runner |
| Complex logic, async, GitHub API calls, JSON parsing | **JavaScript** | Full Node.js, `@actions/core`, `@actions/github` |
| Guaranteed OS/runtime/tool version regardless of runner | **Docker container** | Hermetic environment, but slow cold start (~30s) |
| Cross-platform: Linux + Windows + macOS | **JavaScript** | Composite can work with OS conditionals but is fragile |
| Wrap 3–10 steps that repeat across workflows | **Composite** | Simplest — no compilation, no Docker layer |
| Call the GitHub REST or GraphQL API | **JavaScript** | `@actions/github` client is purpose-built |
| Need persistent state across steps (not `$GITHUB_ENV`) | **JavaScript** | Can manage state in-process |

> **Default to composite** for platform actions. Switch to JavaScript only when you need things composite cannot provide.

---

## action.yml anatomy

Every composite action requires an `action.yml` (or `action.yaml`) at the root of its directory.

```yaml
name: 'Setup Node with Cache'                      # shown in the Marketplace and action picker
description: 'Install Node.js, restore npm cache'  # one sentence
author: 'Platform Team'

inputs:
  node_version:
    description: 'Node.js version (e.g. 20.x)'
    required: false
    default: '20.x'
  enable_cache:
    description: 'Restore npm cache keyed on package-lock.json'
    required: false
    default: 'true'
    type: boolean    # still arrives as a string — compare with == 'true'

outputs:
  node_version:
    description: 'The Node.js version that was installed'
    value: ${{ steps.setup.outputs.node-version }}
  cache_hit:
    description: 'true if the npm cache was restored'
    value: ${{ steps.cache.outputs.cache-hit }}

runs:
  using: 'composite'       # required — must be the literal string "composite"
  steps:
    - name: Restore npm cache
      id: cache
      uses: actions/cache@5a3ec84eff668545956fd18022155c47e93e2684  # v4.2.3
      with:
        path: ~/.npm
        key: ${{ runner.os }}-node-${{ inputs.node_version }}-${{ hashFiles('**/package-lock.json') }}

    - name: Setup Node.js
      id: setup
      uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020  # v4.4.0
      with:
        node-version: ${{ inputs.node_version }}

    - name: Install dependencies
      shell: bash          # required on every run: step — composite has no inherited default
      run: npm ci --prefer-offline

branding:
  icon: 'package'          # Feather icon name
  color: 'green'           # white | yellow | blue | green | orange | red | purple | gray-dark
```

**Mandatory fields:** `name`, `description`, `runs.using: 'composite'`, `shell:` on every `run:` step.

---

## Variables and secrets

Understanding which mechanism to use and when is the most common source of bugs in composite actions.

| Mechanism | How to write | How to read | Scope | Use for |
|---|---|---|---|---|
| `inputs.<name>` | Caller sets via `with:` | `${{ inputs.name }}` in templates | Entire action | Plain config values, secrets passed from caller |
| `env:` on a step | `env: KEY: value` in step | `$KEY` in shell | That step only | Safely injecting inputs into shell commands |
| `$GITHUB_ENV` | `echo "KEY=val" >> "$GITHUB_ENV"` | `$KEY` in shell | All subsequent steps | Sharing computed values across steps |
| `$GITHUB_OUTPUT` | `echo "key=val" >> "$GITHUB_OUTPUT"` | `${{ steps.id.outputs.key }}` | Steps + action outputs | Exposing step results |
| `$GITHUB_PATH` | `echo "/tool/bin" >> "$GITHUB_PATH"` | Automatic — added to `$PATH` | All subsequent steps | Making a binary available on PATH |
| `$GITHUB_STEP_SUMMARY` | `echo "# Title" >> "$GITHUB_STEP_SUMMARY"` | Shown in Actions UI | Job summary page | Rich Markdown summary visible after the run |
| `::add-mask::` | `echo "::add-mask::$VALUE"` | Redacted as `***` in all logs | Immediately + all subsequent | Runtime-generated secrets (tokens, passwords) |

### Secrets flow — end-to-end pattern

Composite actions **cannot** access `${{ secrets.* }}` directly. Secrets must travel as inputs:

```
Caller's secrets store
        │
        │  with:
        │    webhook_url: ${{ secrets.SLACK_WEBHOOK_URL }}
        ▼
inputs:
  webhook_url:          ← declared as required: true in action.yml
    required: true
        │
        │  env: WEBHOOK_URL: ${{ inputs.webhook_url }}
        ▼
Shell step            ← reads $WEBHOOK_URL — never ${{ inputs.webhook_url }} directly
```

```yaml
# action.yml
inputs:
  webhook_url:
    description: 'Slack incoming webhook URL — pass ${{ secrets.SLACK_WEBHOOK_URL }}'
    required: true

runs:
  using: 'composite'
  steps:
    - name: Send notification
      shell: bash
      env:
        WEBHOOK_URL: ${{ inputs.webhook_url }}    # safely isolated from shell parsing
      run: |
        echo "::add-mask::$WEBHOOK_URL"           # mask it from logs immediately
        curl -s -X POST "$WEBHOOK_URL" \
          -H 'Content-Type: application/json' \
          -d '{"text":"Build complete"}'
```

### Plain variables vs secrets — naming convention

Clearly distinguish inputs by adding a comment in the action's README inputs table:

| Input | Type | Secret? | Description |
|---|---|---|---|
| `image_name` | string | No | Container image name |
| `registry` | string | No | Registry host (default: ghcr.io) |
| `aws_role_arn` | string | No | IAM role ARN to assume via OIDC |
| `webhook_url` | string | **Yes** | Pass `${{ secrets.SLACK_WEBHOOK }}` |
| `kubeconfig` | string | **Yes** | Pass `${{ secrets.KUBECONFIG }}` |

---

## Context availability in composite actions

Not all GitHub Actions contexts are available inside composite action steps. Getting this wrong produces silent empty values — no error, just broken behaviour.

| Context | Available in composite? | Notes |
|---|---|---|
| `github.*` | **Yes** — full | `github.sha`, `github.ref`, `github.actor`, `github.event`, etc. |
| `runner.*` | **Yes** | `runner.os`, `runner.arch`, `runner.temp`, `runner.tool_cache` |
| `env.*` | **Yes** | Env vars set by the caller job or earlier steps in the action |
| `inputs.*` | **Yes** | The action's own declared inputs |
| `steps.*` | **Partial** | Only steps defined *within this composite action* — not the caller's steps |
| `job.*` | **Partial** | `job.status` works; `job.container` and `job.services` are empty |
| `secrets.*` | **No** | Always empty — pass secrets as `required: true` inputs instead |
| `needs.*` | **No** | Job dependency outputs are not visible inside a composite action |
| `matrix.*` | **No** | Matrix values are not passed automatically — thread through inputs |
| `strategy.*` | **No** | |

### Threading matrix and needs values through inputs

Because `matrix.*` and `needs.*` are invisible inside a composite action, the caller must forward them explicitly:

```yaml
# Caller job — matrix is defined here
jobs:
  build:
    strategy:
      matrix:
        environment: [dev, staging, production]
    steps:
      - uses: org/actions/deploy@v1
        with:
          environment: ${{ matrix.environment }}   # thread matrix value as an input
          previous_sha: ${{ needs.setup.outputs.sha }}  # thread needs output as an input

# action.yml — receives the values as plain inputs
inputs:
  environment:
    description: 'Target environment'
    required: true
  previous_sha:
    description: 'SHA from the setup job'
    required: false
```

### `steps.*` scope

`steps.*` inside a composite action only sees steps defined **within that action**, not steps in the caller's job. To consume a caller step's output inside your action, the caller must pass it as an input:

```yaml
# Caller
- name: Compute version
  id: version
  run: echo "value=1.2.3" >> "$GITHUB_OUTPUT"

- uses: org/actions/release@v1
  with:
    version: ${{ steps.version.outputs.value }}   # thread caller step output as input

# action.yml — steps.version is NOT visible here; use inputs.version instead
```

---

## OIDC cloud trust configuration

Composite actions like `configure-cloud` and `terraform-plan` use OIDC to exchange a GitHub Actions token for cloud credentials. The action side is straightforward — the common blocker is configuring the *trust relationship* on the cloud side.

### AWS — IAM role trust policy

Create an IAM role with a web identity trust policy that restricts which GitHub repos and branches can assume it:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:org/repo:*"
        }
      }
    }
  ]
}
```

**Condition key options** (use the narrowest that fits):

| Condition | Example value | Restricts to |
|---|---|---|
| `sub` contains `ref:refs/heads/main` | `repo:org/repo:ref:refs/heads/main` | Main branch only |
| `sub` contains `environment:production` | `repo:org/repo:environment:production` | A specific GitHub Environment |
| `sub` wildcard | `repo:org/repo:*` | Any ref in the repo (use with caution) |
| `sub` exact `pull_request` | `repo:org/repo:pull_request` | PRs only (read-only roles) |

**Create the OIDC provider** (one-time per AWS account):

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

> The thumbprint is for the GitHub OIDC endpoint certificate. GitHub rotates this — check the current value in [GitHub's docs](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services).

### Azure — federated credential on the app registration

In Azure, add a federated credential to an existing app registration (Entra ID → App registrations → your app → Certificates & secrets → Federated credentials):

| Field | Value |
|---|---|
| Federated credential scenario | GitHub Actions deploying Azure resources |
| Organisation | `your-github-org` |
| Repository | `your-repo` |
| Entity type | Branch / Environment / Pull request / Tag |
| Based on selection | `main` (for branch) or `production` (for environment) |
| Name | `github-actions-prod` |

**Via Azure CLI:**

```bash
az ad app federated-credential create \
  --id <app-object-id> \
  --parameters '{
    "name": "github-actions-prod",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:org/repo:environment:production",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

**Then grant the service principal the required role:**

```bash
az role assignment create \
  --assignee <service-principal-id> \
  --role "Contributor" \
  --scope "/subscriptions/<subscription-id>/resourceGroups/<rg>"
```

### Terraform — required provider config for OIDC

When using OIDC in a Terraform workflow, configure the provider to use web identity:

```hcl
# AWS — reads OIDC token from ACTIONS_ID_TOKEN_REQUEST_URL automatically
provider "aws" {
  region = var.aws_region
  # No access_key / secret_key — relies on ambient OIDC credentials set by the action
}

# Azure — uses env vars set by azure/login
provider "azurerm" {
  features {}
  use_oidc = true
  # ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID set by the action
}
```

---

## Inputs and outputs

### Input types

```yaml
inputs:
  # String (default)
  image_name:
    description: 'Container image name'
    required: true

  # Choice — validates at workflow parse time
  log_level:
    description: 'Logging verbosity'
    required: false
    default: 'info'
    type: choice
    options: [debug, info, warn, error]

  # Boolean — arrives as string; always compare with == 'true'
  push:
    description: 'Push the image after build'
    required: false
    default: 'true'
    type: boolean
```

### Two ways to read an input

```bash
# 1. Template expression — use in YAML values only, never directly in run: commands
${{ inputs.image_name }}

# 2. Environment variable — always use this inside shell scripts
# Name rule: INPUT_ prefix + uppercased name, hyphens → underscores
$INPUT_IMAGE_NAME
```

### Producing outputs

```yaml
runs:
  using: 'composite'
  steps:
    - name: Compute short SHA tag
      id: tag
      shell: bash
      run: |
        SHORT="${GITHUB_SHA:0:7}"
        echo "value=$SHORT" >> "$GITHUB_OUTPUT"

outputs:
  image_tag:
    description: 'Short SHA used as the image tag'
    value: ${{ steps.tag.outputs.value }}    # must reference a step id
```

### Chaining outputs across steps

```yaml
- name: Build image
  id: build
  shell: bash
  run: |
    DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' myapp:latest)
    echo "digest=$DIGEST" >> "$GITHUB_OUTPUT"

- name: Sign image
  shell: bash
  env:
    IMAGE_DIGEST: ${{ steps.build.outputs.digest }}
  run: |
    cosign sign "$IMAGE_DIGEST"
```

---

## Security requirements

### 1. Pin every external action to a full commit SHA

```yaml
# ❌ Tag — mutable, can be rewritten to point to malicious code
- uses: actions/checkout@v4

# ✅ SHA — immutable, tied to the exact code reviewed; add version as comment
- uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
```

Use [pinact](https://github.com/suzuki-shunsuke/pinact) to resolve and update SHAs automatically.

### 2. Declare `shell:` on every `run:` step

Composite actions have no inherited shell. Omitting it errors or falls back silently.

```yaml
# ❌
- run: echo "hello"

# ✅
- shell: bash
  run: echo "hello"
```

### 3. Secrets must come in as inputs

```yaml
# ✅ action.yml
inputs:
  github_token:
    description: 'GitHub token — pass ${{ secrets.GITHUB_TOKEN }}'
    required: true

# ✅ caller workflow
- uses: org/repo/actions/deploy@abc123
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
```

### 4. Never interpolate inputs directly in `run:` — use `env:`

```yaml
# ❌ Shell injection — inputs.environment is expanded before bash parses
- shell: bash
  run: deploy.sh --env ${{ inputs.environment }}

# ✅ Data, not code — bash sees the value as an env var, not a command
- shell: bash
  env:
    DEPLOY_ENV: ${{ inputs.environment }}
  run: |
    case "$DEPLOY_ENV" in
      dev|staging|production) ;;
      *) echo "::error::Invalid environment: $DEPLOY_ENV" && exit 1 ;;
    esac
    deploy.sh --env "$DEPLOY_ENV"
```

### 5. Mask secrets and runtime-generated tokens immediately

```yaml
- name: Retrieve ephemeral token
  id: token
  shell: bash
  run: |
    TOKEN=$(curl -s https://auth.example.com/token | jq -r '.access_token')
    echo "::add-mask::$TOKEN"
    echo "value=$TOKEN" >> "$GITHUB_OUTPUT"
```

### 6. Use `${{ github.action_path }}` — never relative paths

```yaml
# ❌ Breaks when the caller's CWD differs from the action's directory
- shell: bash
  run: ./scripts/validate.sh

# ✅ Always resolves to the action's own directory
- shell: bash
  run: |
    chmod +x "${{ github.action_path }}/scripts/validate.sh"
    "${{ github.action_path }}/scripts/validate.sh"
```

### 7. Document the minimum `GITHUB_TOKEN` permissions in the README

Composite actions inherit the caller job's token permissions. Always document:

```yaml
# Minimum permissions required by this action
permissions:
  contents: read
  packages: write    # push to GHCR
  id-token: write    # OIDC
```

---

## Observability

Every production-grade composite action should write a job summary, group its output, and emit inline annotations.

### Job summary — `$GITHUB_STEP_SUMMARY`

The job summary appears in the GitHub Actions UI after the run and is linked from the PR checks.

```yaml
- name: Write job summary
  if: always()
  shell: bash
  run: |
    {
      echo "## Build Result"
      echo ""
      echo "| Field | Value |"
      echo "|---|---|"
      echo "| Image | \`${{ inputs.registry }}/${{ inputs.image_name }}\` |"
      echo "| Tag | \`${{ steps.tag.outputs.value }}\` |"
      echo "| Digest | \`${{ steps.push.outputs.digest }}\` |"
      echo "| Status | $([[ '${{ job.status }}' == 'success' ]] && echo '✅ Success' || echo '❌ Failed') |"
    } >> "$GITHUB_STEP_SUMMARY"
```

### Log grouping — `::group::` / `::endgroup::`

Collapsible sections make long logs readable in the Actions UI.

```yaml
- name: Install and validate
  shell: bash
  run: |
    echo "::group::Install dependencies"
    npm ci
    echo "::endgroup::"

    echo "::group::Run lint"
    npm run lint
    echo "::endgroup::"
```

### Annotations — inline PR feedback

Annotations appear in the PR "Files changed" view as inline comments.

```yaml
# Error — fails the check (shown as ❌ in PR)
echo "::error file=src/app.ts,line=42,col=5::Null pointer dereference"

# Warning — advisory, does not fail (shown as ⚠️)
echo "::warning file=terraform/main.tf,line=10::Deprecated resource type"

# Notice — informational (shown as ℹ️)
echo "::notice::Image built successfully: $IMAGE_TAG"
```

### Debug logging — `::debug::` and `RUNNER_DEBUG`

`::debug::` writes a message that only appears when debug logging is enabled. Use it for verbose diagnostic output that would clutter normal runs:

```yaml
- name: Compute cache key
  shell: bash
  run: |
    KEY="${{ runner.os }}-node-${{ inputs.version }}-${{ hashFiles('**/package-lock.json') }}"
    echo "::debug::Cache key: $KEY"
    echo "cache_key=$KEY" >> "$GITHUB_OUTPUT"
```

`RUNNER_DEBUG=1` is also set when debug logging is enabled — use it for conditional verbose blocks:

```yaml
- name: Run deployment
  shell: bash
  run: |
    if [[ "${RUNNER_DEBUG:-0}" == "1" ]]; then
      set -x       # echo every command
      kubectl get all -n "$NAMESPACE"
    fi
    kubectl apply -f manifest.yml
  env:
    NAMESPACE: ${{ inputs.namespace }}
```

Enable from the repo → Actions → "Re-run jobs" → "Enable debug logging", or set `ACTIONS_STEP_DEBUG=true` as a repository secret for permanent debug output.

**Logging command summary:**

| Command | Visibility | Use for |
|---|---|---|
| `::debug::message` | Debug runs only | Verbose diagnostic info, cache keys, computed values |
| `::notice::message` | Always — blue annotation | Informational milestones (release URL, tag created) |
| `::warning::message` | Always — yellow annotation | Non-fatal issues (deprecated input, skipped step) |
| `::error::message` | Always — red annotation | Fatal errors (pair with `exit 1`) |
| `echo "plain text"` | Always — no annotation | Progress messages inside `::group::` blocks |

---

## Input validation — fail fast

Validate all inputs at the top of the first step before doing any real work. Give developers a clear, actionable error message.

```yaml
- name: Validate inputs
  shell: bash
  env:
    IMAGE_NAME: ${{ inputs.image_name }}
    ENVIRONMENT: ${{ inputs.environment }}
    SEVERITY: ${{ inputs.severity }}
  run: |
    ERRORS=()

    # Required inputs
    [[ -z "$IMAGE_NAME" ]] && ERRORS+=("image_name is required")

    # Enum validation
    case "$ENVIRONMENT" in
      dev|staging|production) ;;
      *) ERRORS+=("environment must be one of: dev, staging, production (got: $ENVIRONMENT)") ;;
    esac

    # Pattern validation
    if [[ -n "$SEVERITY" ]] && ! echo "$SEVERITY" | grep -qE '^(UNKNOWN|LOW|MEDIUM|HIGH|CRITICAL)(,(UNKNOWN|LOW|MEDIUM|HIGH|CRITICAL))*$'; then
      ERRORS+=("severity must be comma-separated severity levels (e.g. HIGH,CRITICAL)")
    fi

    # Report all errors at once
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
      for err in "${ERRORS[@]}"; do
        echo "::error::$err"
      done
      exit 1
    fi
```

---

## Step control flow

### Step IDs

Add `id:` to every step whose result is referenced by a later step or exposed as an action output.

```yaml
- name: Build image
  id: build           # referenced as steps.build.outputs.digest below
  uses: docker/build-push-action@...
  with:
    push: true
```

### Conditional steps

```yaml
# Run only when input flag is set
- name: Push image
  if: inputs.push == 'true'
  shell: bash
  run: docker push "$IMAGE_URI"

# Run on failure — e.g., cleanup or notification
- name: Notify on failure
  if: failure()
  shell: bash
  env:
    WEBHOOK: ${{ inputs.slack_webhook_url }}
  run: |
    curl -s -X POST "$WEBHOOK" \
      -H 'Content-Type: application/json' \
      -d "{\"text\":\"Build failed in ${{ github.repository }}@${{ github.sha }}\"}"

# Always run — e.g., upload logs, write summary
- name: Upload logs
  if: always()
  uses: actions/upload-artifact@6f51ac03b9356f520e9adb1b1029d08800d6f4dc  # v4.5.0
  with:
    name: build-logs-${{ github.run_id }}
    path: '*.log'
```

### `continue-on-error` vs `if: always()` — critical difference

These look similar but have opposite semantics. Using the wrong one is a silent bug.

| Behaviour | `continue-on-error: true` | `if: always()` |
|---|---|---|
| Step runs when previous step fails? | Only on that specific step | Yes — any subsequent step with `if: always()` |
| `steps.<id>.outcome` | `failure` (correct) | `failure` (correct) |
| `steps.<id>.conclusion` | **`success`** — always, even if it failed | `failure` if it failed |
| Job outcome affected by step failure? | **No** — failure is swallowed | Yes — job still fails unless `if: always()` step masks it |
| Use for | Optional steps whose failure should not block the job | Cleanup/summary steps that must always run |

```yaml
# ✅ continue-on-error: true — optional step, failure is ignored for job outcome
- name: Optional security scan
  id: scan
  continue-on-error: true
  uses: aquasecurity/trivy-action@...
  with:
    exit-code: '1'

- name: Report scan result
  shell: bash
  run: |
    # steps.scan.conclusion == 'success' even if scan found CVEs and exited 1
    # Use steps.scan.outcome (not conclusion) to check the real result
    echo "Scan outcome: ${{ steps.scan.outcome }}"

# ✅ if: always() — cleanup must run regardless of what failed above
- name: Delete temp kubeconfig
  if: always()
  shell: bash
  run: rm -f "$KUBECONFIG_TMPFILE"
```

**The footgun:** using `continue-on-error: true` on a cleanup step when you meant `if: always()`. If the prior step succeeded, both work. But if the prior step *failed*, a cleanup step without `if: always()` is **skipped**, leaving credentials or temp files behind.

```yaml
# ❌ Wrong — cleanup is SKIPPED if the deploy step fails
- name: Deploy
  run: kubectl apply -f manifest.yml
- name: Cleanup
  continue-on-error: true   # this only affects THIS step's failure, not whether it runs
  run: rm -f /tmp/kubeconfig

# ✅ Correct — cleanup always runs
- name: Deploy
  run: kubectl apply -f manifest.yml
- name: Cleanup
  if: always()
  run: rm -f /tmp/kubeconfig
```

### Allow a step to fail without failing the action

```yaml
- name: Optional lint
  id: lint
  shell: bash
  continue-on-error: true
  run: npm run lint

- name: Report lint result
  shell: bash
  run: |
    # Use .outcome (actual result), not .conclusion (always success with continue-on-error)
    if [[ "${{ steps.lint.outcome }}" == "failure" ]]; then
      echo "::warning::Lint failed — see output above"
    fi
```

---

## File references and scripts

### Always use `${{ github.action_path }}`

```
actions/
└── k8s-deploy/
    ├── action.yml
    └── scripts/
        └── deploy.sh
```

```yaml
- name: Deploy to Kubernetes
  shell: bash
  run: |
    chmod +x "${{ github.action_path }}/scripts/deploy.sh"
    "${{ github.action_path }}/scripts/deploy.sh"
  env:
    KUBECONFIG_CONTENT: ${{ inputs.kubeconfig }}
    NAMESPACE: ${{ inputs.namespace }}
```

### Add the action directory to `$PATH`

For actions that ship multiple scripts, add the directory to PATH once:

```yaml
- name: Add action scripts to PATH
  shell: bash
  run: echo "${{ github.action_path }}/scripts" >> "$GITHUB_PATH"

- name: Deploy
  shell: bash
  run: deploy.sh    # found via PATH
```

> Scripts checked in from macOS may lack the execute bit. Always `chmod +x` before invoking.

---

## Multi-OS patterns

Composite actions run on the caller's runner. Handle Linux, macOS, and Windows differences explicitly.

```yaml
- name: Set platform-specific paths
  shell: bash
  run: |
    if [[ "${{ runner.os }}" == "Windows" ]]; then
      echo "TOOL_PATH=C:\\tools\\bin" >> "$GITHUB_ENV"
      echo "EXT=.exe" >> "$GITHUB_ENV"
    else
      echo "TOOL_PATH=/usr/local/bin" >> "$GITHUB_ENV"
      echo "EXT=" >> "$GITHUB_ENV"
    fi

- name: Install tool
  shell: bash
  run: |
    if [[ "${{ runner.os }}" == "macOS" ]]; then
      brew install mytool
    elif [[ "${{ runner.os }}" == "Linux" ]]; then
      sudo apt-get install -y mytool
    else
      choco install mytool
    fi

# Windows steps use pwsh, not bash
- name: Windows-only step
  if: runner.os == 'Windows'
  shell: pwsh
  run: Write-Host "Running on Windows"
```

### Path separators

```yaml
- name: Construct path
  shell: bash
  env:
    BASE_DIR: ${{ inputs.base_dir }}
  run: |
    # Use forward slashes even on Windows in bash shell
    FULL_PATH="$BASE_DIR/config/app.yml"
    echo "config_path=$FULL_PATH" >> "$GITHUB_OUTPUT"
```

---

## Idempotency

Document idempotency behaviour for each action. An action is idempotent when running it twice produces the same result without error.

**Patterns:**

```yaml
# Pattern 1 — Skip if already done
- name: Check if image tag exists
  id: check
  shell: bash
  run: |
    if docker manifest inspect "${{ inputs.registry }}/${{ inputs.image_name }}:${{ inputs.image_tag }}" > /dev/null 2>&1; then
      echo "exists=true" >> "$GITHUB_OUTPUT"
      echo "::notice::Image already exists — skipping build"
    else
      echo "exists=false" >> "$GITHUB_OUTPUT"
    fi

- name: Build and push
  if: steps.check.outputs.exists == 'false'
  uses: docker/build-push-action@...

# Pattern 2 — Upsert (create or update)
- name: Create or update Kubernetes deployment
  shell: bash
  run: |
    kubectl apply -f manifest.yml   # apply is idempotent by design

# Pattern 3 — Check before delete
- name: Delete old tag if exists
  shell: bash
  run: |
    if git tag -l "${{ inputs.version }}" | grep -q .; then
      git tag -d "${{ inputs.version }}"
    fi
    git tag "${{ inputs.version }}"
```

Every action's README should include an **Idempotency** section stating whether it is safe to re-run.

---

## Timeout and concurrency

### Step-level timeout

```yaml
- name: Wait for deployment to stabilise
  shell: bash
  timeout-minutes: 10    # fail this step if it runs longer than 10 minutes
  run: |
    kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=600s
  env:
    DEPLOYMENT: ${{ inputs.deployment_name }}
    NAMESPACE: ${{ inputs.namespace }}

- name: Call external API
  shell: bash
  timeout-minutes: 2
  run: curl --max-time 90 -s "$API_URL"
  env:
    API_URL: ${{ inputs.api_url }}
```

### Concurrency — caller's responsibility

Composite actions do not control job-level concurrency. Document the recommended `concurrency:` block in the action's README:

```yaml
# Recommended in the caller workflow when using deploy or release actions
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false   # false for deploy/release; true for validation/build
```

---

## Testing

### Test workflow — local path reference

Reference the action with `./.github/actions/<name>` or `./actions/<name>` so the PR under review is what gets tested.

```yaml
name: Test composite action

on:
  push:
    paths:
      - 'actions/**'
      - '.github/workflows/test-action.yml'
  pull_request:
    paths:
      - 'actions/**'

jobs:
  test-defaults:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - name: Run action with default inputs
        id: result
        uses: ./actions/setup-env

      - name: Verify outputs
        shell: bash
        run: |
          echo "node_version: ${{ steps.result.outputs.node_version }}"
          node --version | grep -q "^v20\." || { echo "::error::Wrong Node version"; exit 1; }

  test-matrix:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        node_version: ['18.x', '20.x', '22.x']
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - uses: ./actions/setup-env
        with:
          node_version: ${{ matrix.node_version }}
```

### Local testing with `act`

```bash
brew install act

# Run with a full Ubuntu image
act -P ubuntu-latest=catthehacker/ubuntu:act-22.04 \
    -W .github/workflows/test-action.yml

# With secrets
act -W .github/workflows/test-action.yml \
    --secret SLACK_WEBHOOK_URL=https://hooks.slack.com/...
```

### Static validation

```bash
# Install actionlint
brew install actionlint

# Validate
actionlint actions/setup-env/action.yml

# Check all external actions are SHA-pinned
grep -rn 'uses:' actions/ \
  | grep -vE '(@[0-9a-f]{40}|\./)' \
  | grep -v '#'

# Check every run: step has shell:
grep -B1 'run:' actions/*/action.yml | grep -v 'shell:' | grep 'run:'
```

---

## Breaking changes

A breaking change is any change that requires a caller to update their `with:` block or `outputs.*` references.

**What counts as breaking:**
- Renaming or removing an input
- Changing an input from optional to required
- Renaming or removing an output
- Changing the format of an output value

**How to handle:**

```yaml
# Step 1 — Add a deprecation warning on the old input (minor version)
- name: Check for deprecated inputs
  shell: bash
  run: |
    if [[ -n "$OLD_INPUT" ]]; then
      echo "::warning::Input 'aws_role' is deprecated. Use 'aws_role_arn' instead. This will be removed in v3."
    fi
  env:
    OLD_INPUT: ${{ inputs.aws_role }}

# Step 2 — Support both old and new inputs in the same minor version
- name: Resolve role ARN
  id: role
  shell: bash
  run: |
    ARN="${ROLE_ARN:-$OLD_ROLE}"
    [[ -z "$ARN" ]] && echo "::error::Provide aws_role_arn" && exit 1
    echo "arn=$ARN" >> "$GITHUB_OUTPUT"
  env:
    ROLE_ARN: ${{ inputs.aws_role_arn }}
    OLD_ROLE: ${{ inputs.aws_role }}

# Step 3 — Remove old input in next major version
```

**In the CHANGELOG:**
```markdown
## [v2.0.0] - 2026-05-23
### Breaking changes
- `aws_role` input renamed to `aws_role_arn` — update your `with:` block
### Migration
Replace `aws_role: arn:...` with `aws_role_arn: arn:...`
```

---

## Versioning and release

```
v1.0.0  — initial release
v1.0.1  — patch: fix shell quoting bug
v1.1.0  — minor: add enable_cache input
v2.0.0  — major: rename aws_role → aws_role_arn (breaking)
v1      — floating tag, always points to latest v1.x.x
```

### Release workflow

```yaml
name: Release action

on:
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - name: Validate with actionlint
        shell: bash
        run: |
          curl -sL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash
          ./actionlint

      - name: Update floating major version tag
        shell: bash
        run: |
          MAJOR=$(echo "${{ github.ref_name }}" | cut -d. -f1)
          git tag -f "$MAJOR"
          git push origin "$MAJOR" --force

      - name: Create GitHub release
        uses: actions/github-script@60a0d83039c74a4aee543508d2ffcb1c3799cdea  # v7.0.1
        with:
          script: |
            const tag = context.ref.replace('refs/tags/', '');
            await github.rest.repos.createRelease({
              owner: context.repo.owner,
              repo: context.repo.repo,
              tag_name: tag,
              name: tag,
              generate_release_notes: true,
            });
```

---

## Dependabot configuration

Add this to every action repo to auto-receive SHA updates when upstream actions release new versions:

```yaml
# .github/dependabot.yml
version: 2
updates:
  # Keep GitHub Actions up to date
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
      timezone: "UTC"
    commit-message:
      prefix: "chore(deps)"
    labels:
      - "dependencies"
      - "github-actions"
    groups:
      github-actions:
        patterns:
          - "*"
    # Also update actions within composite action steps
  - package-ecosystem: "github-actions"
    directory: "/actions"
    schedule:
      interval: "weekly"
```

---

## Passing state to post-steps — $GITHUB_STATE

Composite actions do **not** support `post:` steps natively (that is a JavaScript/Docker action feature). For cleanup that must run after the main steps (e.g. deleting a temp file), use `if: always()` at the end of your step list.

If you wrap a composite action in a JavaScript action that calls it, `$GITHUB_STATE` lets the main run pass state to the `post:` phase:

```bash
# In main step — save state
echo "KUBECONFIG_PATH=/tmp/kube-abc123" >> "$GITHUB_STATE"

# In post: step — read state
echo "Cleaning up ${STATE_KUBECONFIG_PATH}"
rm -f "${STATE_KUBECONFIG_PATH}"
```

**For pure composite actions:** use `if: always()` cleanup steps and store the path in `$GITHUB_ENV` so later steps can reference it:

```yaml
steps:
  - name: Write kubeconfig
    id: write-kube
    shell: bash
    run: |
      TMPFILE=$(mktemp /tmp/kubeconfig-XXXXXX)
      echo "$KUBECONFIG_B64" | base64 -d > "$TMPFILE"
      chmod 600 "$TMPFILE"
      echo "path=$TMPFILE" >> "$GITHUB_OUTPUT"
      echo "KUBECONFIG_TMPFILE=$TMPFILE" >> "$GITHUB_ENV"
    env:
      KUBECONFIG_B64: ${{ inputs.kubeconfig }}

  # ... main steps ...

  - name: Cleanup kubeconfig
    if: always()      # runs even if earlier steps fail
    shell: bash
    run: |
      rm -f "$KUBECONFIG_TMPFILE"
      echo "::notice::Temporary kubeconfig deleted"
```

---

## Action composition — calling composite from composite

A composite action can call other composite actions via `uses:`. This enables layered abstractions without duplicating logic.

```yaml
# inner-action/action.yml
name: 'Setup credentials'
runs:
  using: 'composite'
  steps:
    - name: Configure AWS
      uses: aws-actions/configure-aws-credentials@e3dd6a429d7300a6a4c196c26e071d42e0343502  # v4.0.2
      with:
        role-to-assume: ${{ inputs.role_arn }}
        aws-region: ${{ inputs.aws_region }}

# outer-action/action.yml — calls the inner action
name: 'Deploy to ECS'
runs:
  using: 'composite'
  steps:
    - name: Setup credentials
      uses: org/repo/inner-action@v1    # calls the inner composite action
      with:
        role_arn: ${{ inputs.role_arn }}
        aws_region: ${{ inputs.aws_region }}

    - name: Deploy
      shell: bash
      run: aws ecs update-service ...
```

**Constraints:**
- Nested composite actions still cannot access `${{ secrets.* }}` — secrets must be threaded through as inputs at every layer
- Each layer's inputs must explicitly declare and pass secret inputs down; there is no automatic propagation
- Circular references are not allowed and will cause a workflow parse error
- Pin the inner action to a SHA, not a branch, to avoid chained supply-chain risk

---

## Self-hosted runner considerations

Composite actions run on whatever runner the caller provides. When that is a self-hosted runner, several assumptions that hold for GitHub-hosted runners may break.

| Assumption | GitHub-hosted | Self-hosted risk | Mitigation |
|---|---|---|---|
| `bash` at `/bin/bash` | Always present | May use `sh`, `dash`, or be non-Linux | Declare `shell: bash`; test on runner OS |
| Tool availability (`curl`, `jq`, `docker`) | Pre-installed on `ubuntu-latest` | Not guaranteed | Install the tool in a step, or document requirement |
| `$HOME` / `~` paths | Predictable per job | May be shared across jobs if runner is persistent | Use `mktemp` for temp files; clean up with `if: always()` |
| Clean environment | Fresh VM per job | Persistent runner may have leftover env vars from prior job | Namespace your env vars; don't rely on env state |
| `$GITHUB_WORKSPACE` | Under `/home/runner/work/` | May be on a different mount | Always use `$GITHUB_WORKSPACE` — never hardcode |
| Caching | `actions/cache` backed by GitHub's CDN | May be slower or misconfigured | Document cache action as optional; test with `enable_cache: false` |
| Network access | Open internet | May be restricted to internal registry only | Accept registry host as input; don't hardcode `ghcr.io` |

**Document requirements in README:**

```markdown
## Runner requirements

This action works on both GitHub-hosted and self-hosted runners. Self-hosted runners must have:
- `bash` >= 4.0
- `curl`
- `docker` (for image scan target only)
- Internet access to `trivy.dev` for database updates (or set `trivy_version` to a pre-cached binary)
```

---

## Ephemeral runner security

Ephemeral (single-use) runners are the recommended security posture for composite actions that handle secrets. Persistent runners accumulate risk:

| Risk | Persistent runner | Ephemeral runner |
|---|---|---|
| Secret leakage to next job | Secrets in `$GITHUB_ENV` persist if cleanup fails | VM destroyed after job — no carry-over |
| Malicious process left from prior job | Can intercept secrets of the next job | No prior job exists |
| Disk artifacts (kubeconfig, token files) | Must be manually cleaned with `if: always()` | Disappear with the VM |
| Compromised runner from supply-chain attack | Affects all subsequent jobs | Blast radius is one job |

**Enforce ephemeral runners via org policy (GitHub Enterprise):**

```yaml
# Runner group: require ephemeral
gh api \
  --method PATCH \
  /orgs/{org}/actions/runner-groups/{group_id} \
  -f runs_on_self_hosted_runners_only=true \
  -f runners_type="ephemeral"
```

**In your action's README**, call out when ephemeral runners matter:

```markdown
## Security note — ephemeral runners recommended

This action handles a `kubeconfig` secret. Run it on **ephemeral** (single-use) runners so the
temporary kubeconfig file cannot be accessed by subsequent jobs on the same machine.

GitHub-hosted runners (`ubuntu-latest`) are ephemeral by default.
For self-hosted runners, configure the runner group to use `--ephemeral` mode.
```

---

## Troubleshooting

### Error: `shell` is required for `run:` step in composite action

```
Error: required property is missing: shell
```

**Cause:** Composite actions have no inherited default shell.

**Fix:** Add `shell: bash` (or `shell: pwsh` on Windows) to every `run:` step.

---

### Error: `${{ secrets.MY_SECRET }}` is empty inside the action

**Cause:** Composite actions cannot access `${{ secrets.* }}` directly — it resolves to an empty string.

**Fix:** Pass the secret as a required input in `action.yml`:

```yaml
# action.yml
inputs:
  my_token:
    description: 'Pass ${{ secrets.MY_SECRET }}'
    required: true

# caller workflow
- uses: org/repo/my-action@v1
  with:
    my_token: ${{ secrets.MY_SECRET }}
```

---

### Error: `::add-mask::` not masking the value

**Symptom:** The secret value appears in plain text in the logs.

**Causes and fixes:**

| Cause | Fix |
|---|---|
| `::add-mask::` called after the value was already logged | Move `::add-mask::$VALUE` to be the **first** command in the step |
| The secret was interpolated in YAML before the step ran | Stop using `${{ inputs.secret }}` in `run:` — use `env:` block + `$VAR` |
| The value was base64-encoded and decoded in shell | Mask the decoded value, not the encoded one |

---

### Error: `uses: ./` not found when calling the action

**Symptom:**

```
Error: Can't find 'action.yml', 'action.yaml', or 'Dockerfile'
```

**Causes:**
- `actions/checkout` step is missing — the action directory is not present on disk
- Path is wrong — the action lives at `.github/actions/my-action/` but `uses: ./` looks at the root

**Fix:**

```yaml
steps:
  - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
  - uses: ./.github/actions/my-action   # matches the directory where action.yml lives
```

---

### `actionlint` error: `shellcheck reported issue in this script`

actionlint runs shellcheck on `run:` blocks by default. Common fixes:

```bash
# SC2086: quote variable
echo $FOO          # ❌
echo "$FOO"        # ✅

# SC2181: use direct exit code check
cmd; if [ $? -ne 0 ]; then    # ❌
if ! cmd; then                 # ✅

# SC2155: declare and assign separately
export FOO=$(bar)              # ❌
FOO=$(bar); export FOO         # ✅

# Suppress a specific check (last resort)
# shellcheck disable=SC2046
eval $(some_command)
```

To run actionlint locally:

```bash
# Install
brew install actionlint     # macOS
# or:
curl -sL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash \
  | bash -s -- latest /usr/local/bin

# Lint a single action
actionlint action.yml

# Lint all workflows in a repo
actionlint .github/workflows/*.yml

# With shellcheck integration
actionlint -shellcheck shellcheck action.yml
```

---

### Output is empty — `steps.<id>.outputs.<key>` resolves to empty string

**Cause A:** Step `id:` is missing

```yaml
- name: Set tag
  shell: bash    # missing id:
  run: echo "tag=v1.2.3" >> "$GITHUB_OUTPUT"
```

**Fix:** Add `id: set-tag` and reference `steps.set-tag.outputs.tag`.

**Cause B:** Writing to `$GITHUB_OUTPUT` with wrong syntax

```bash
# ❌ — colon instead of equals
echo "tag:v1.2.3" >> "$GITHUB_OUTPUT"

# ✅
echo "tag=v1.2.3" >> "$GITHUB_OUTPUT"
```

**Cause C:** Multi-line output needs delimiter syntax

```bash
# ❌ — newlines in value break the key=value format
echo "body=$(cat NOTES.md)" >> "$GITHUB_OUTPUT"

# ✅ — EOF delimiter
{
  echo "body<<EOF"
  cat NOTES.md
  echo "EOF"
} >> "$GITHUB_OUTPUT"
```

---

### The floating major tag `v1` was not updated

**Symptom:** Callers using `@v1` still run the old version after a `v1.2.0` release.

**Cause:** The release workflow `git push --force` failed, or the `release.yml` was not triggered (wrong tag pattern).

**Check:**

```bash
gh run list --workflow release.yml --limit 5
gh api repos/{owner}/{repo}/git/refs/tags/v1 | jq .object.sha
gh api repos/{owner}/{repo}/git/refs/tags/v1.2.0 | jq .object.sha
# Both should return the same SHA after a successful release
```

**Fix manually:**

```bash
git fetch --tags
git tag -f v1 v1.2.0
git push origin v1 --force
```

---

### `inputs.boolean_input == true` is always false

**Cause:** All inputs arrive as strings. `== true` (non-string) never matches `'true'` (string).

**Fix:**

```bash
if [[ "$INPUT_ENABLE_CACHE" == "true" ]]; then
```

Or in a `uses:` `if:` condition:

```yaml
if: inputs.enable_cache == 'true'
```

---

## Anti-patterns

| Anti-pattern | Risk | Fix |
|---|---|---|
| `uses: actions/checkout@v4` | Tag mutable — can be rewritten to malicious code | Pin to full 40-char SHA |
| `run:` without `shell:` | Error or silent wrong default | Declare `shell: bash` on every step |
| `${{ secrets.TOKEN }}` in action.yml | Not accessible — action silently gets empty string | Pass as required input |
| `run: cmd ${{ inputs.val }}` | Shell injection — value parsed before bash | Use `env:` block |
| No `id:` on output-producing steps | Cannot reference the output | Add `id:` to every such step |
| Boolean compared with `== true` | String comparison always false | Compare with `== 'true'` |
| `./scripts/run.sh` relative path | Breaks when caller CWD differs | Use `${{ github.action_path }}/scripts/run.sh` |
| Forgetting `chmod +x` | Permission denied on fresh checkout | Add `chmod +x` before invoking scripts |
| No input validation | Confusing downstream errors | Validate at top of first step, fail with `::error::` |
| No job summary | Developer blind to what happened | Write to `$GITHUB_STEP_SUMMARY` in every action |
| No `timeout-minutes` on network steps | Hang forever on transient failures | Set `timeout-minutes` on every external call |
| Hardcoded region/account/registry | Action only works for one team | Accept as required or defaulted inputs |
| Missing deprecation warning on renamed input | Silent break for callers | Emit `::warning::` on old input, support both for one minor version |

---

## Production checklist

**Security**
- [ ] All external `uses:` pinned to 40-char SHA with version comment
- [ ] `shell:` on every `run:` step
- [ ] Secrets accepted as `required: true` inputs — not accessed via `${{ secrets.* }}`
- [ ] Inputs not interpolated into `run:` — passed through `env:`
- [ ] Sensitive runtime values masked with `::add-mask::` immediately
- [ ] File references use `${{ github.action_path }}`
- [ ] Minimum `permissions:` documented in README

**Correctness**
- [ ] Input validation step at top — validates required fields and enum constraints
- [ ] Every output-producing step has `id:`
- [ ] All `outputs:` map to correct `steps.<id>.outputs.<key>`
- [ ] Boolean inputs compared with `== 'true'`
- [ ] Scripts have `chmod +x` before invocation
- [ ] Idempotency behaviour documented

**Observability**
- [ ] `$GITHUB_STEP_SUMMARY` written (at minimum: key inputs, outputs, status)
- [ ] Log groups (`::group::`) around each logical phase
- [ ] `::error::` / `::warning::` annotations used instead of plain `echo`
- [ ] Debug mode honoured via `RUNNER_DEBUG`

**Testing**
- [ ] Test workflow uses local path reference (`./actions/…`)
- [ ] Matrix covers key input variants
- [ ] `actionlint` passes with zero warnings
- [ ] Tested locally with `act`

**Documentation**
- [ ] Every input has `description:` (include "Pass `${{ secrets.* }}`" for secret inputs)
- [ ] Every output has `description:`
- [ ] README: inputs table with Secret? column, outputs table, permissions, idempotency, usage example
- [ ] CHANGELOG.md present and updated

**Release**
- [ ] Semver tag applied — breaking input changes bump major
- [ ] Floating major tag (`v1`) updated in release workflow
- [ ] `dependabot.yml` configured for `github-actions` ecosystem

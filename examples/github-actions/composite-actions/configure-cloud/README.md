# configure-cloud

> Configure AWS or Azure credentials using OIDC in a single `uses:` call. No long-lived secrets — workload identity federation only.

Status: Stable

<!-- Run `/platform-skills:awesome-docs generate` on this file to add an animated architecture flow and input carousel diagram. -->

## Quick start

```yaml
# AWS via OIDC
- uses: your-org/actions/configure-cloud@v1
  with:
    cloud_provider: aws
    aws_role_arn: arn:aws:iam::123456789012:role/github-actions

# Azure via OIDC
- uses: your-org/actions/configure-cloud@v1
  with:
    cloud_provider: azure
    azure_client_id: ${{ vars.AZURE_CLIENT_ID }}
    azure_tenant_id: ${{ vars.AZURE_TENANT_ID }}
    azure_subscription_id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

---

## How it works

```
inputs.cloud_provider (aws | azure)
        │
        ├── aws   → aws-actions/configure-aws-credentials (OIDC token exchange)
        │            └── STS AssumeRoleWithWebIdentity → short-lived session token
        │            └── outputs.aws_account_id
        │
        └── azure → azure/login (federated credential token exchange)
                     └── Microsoft Entra ID → access token in az CLI context
        │
        ▼
Subsequent steps use cloud CLI/SDK with credentials already in environment
```

---

## Inputs

| Input | Type | Required | Secret | Default | Description |
|---|---|---|---|---|---|
| `cloud_provider` | choice | **Yes** | No | — | `aws` or `azure` |
| `aws_role_arn` | string | Conditional | No | — | IAM role ARN — required when `cloud_provider=aws` |
| `aws_region` | string | No | No | `us-east-1` | AWS region |
| `azure_client_id` | string | Conditional | No | — | App registration client ID — required when `cloud_provider=azure` |
| `azure_tenant_id` | string | Conditional | No | — | Azure AD tenant ID — required when `cloud_provider=azure` |
| `azure_subscription_id` | string | Conditional | No | — | Subscription ID — required when `cloud_provider=azure` |

**No secrets.** OIDC exchanges a short-lived GitHub Actions token for cloud credentials — no static access keys or client secrets are stored anywhere.

---

## Outputs

| Output | Description |
|---|---|
| `cloud_provider` | The configured provider (`aws` or `azure`) |
| `aws_account_id` | AWS account ID (empty string for Azure) |

---

## Variables and secrets

```yaml
# AWS — all plain variables (role ARN is safe to store as a repo variable)
- uses: your-org/actions/configure-cloud@v1
  with:
    cloud_provider: aws
    aws_role_arn: arn:aws:iam::123456789012:role/github-actions  # not a secret
    aws_region: us-east-1

# Azure — use repo/org variables, not secrets (client ID is not sensitive with OIDC)
- uses: your-org/actions/configure-cloud@v1
  with:
    cloud_provider: azure
    azure_client_id: ${{ vars.AZURE_CLIENT_ID }}          # vars.* not secrets.*
    azure_tenant_id: ${{ vars.AZURE_TENANT_ID }}
    azure_subscription_id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

Nothing is masked in logs because no credentials flow through inputs — the OIDC token exchange happens inside the upstream action.

---

## Permissions

```yaml
permissions:
  id-token: write   # required for OIDC token exchange
  contents: read
```

---

## Idempotency

**Idempotent** — each call assumes the same role with a fresh short-lived session. Safe to call multiple times in a job.

---

## Concurrency (recommended)

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false   # don't interrupt deploys in progress
```

---

## Full example — multi-cloud deploy

```yaml
name: Deploy

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  deploy-aws:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - name: Configure AWS
        id: cloud
        uses: your-org/actions/configure-cloud@v1
        with:
          cloud_provider: aws
          aws_role_arn: arn:aws:iam::123456789012:role/github-actions
          aws_region: us-east-1

      - name: Deploy to ECS
        run: |
          aws ecs update-service \
            --cluster prod \
            --service api \
            --force-new-deployment

  deploy-azure:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - name: Configure Azure
        uses: your-org/actions/configure-cloud@v1
        with:
          cloud_provider: azure
          azure_client_id: ${{ vars.AZURE_CLIENT_ID }}
          azure_tenant_id: ${{ vars.AZURE_TENANT_ID }}
          azure_subscription_id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

      - name: Deploy to AKS
        run: |
          az aks get-credentials --resource-group prod-rg --name prod-aks
          kubectl rollout restart deployment/api -n production
```

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md)

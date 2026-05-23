# terraform-plan

> Run `terraform fmt → validate → plan` and post the plan output as an idempotent PR comment. Supports AWS and Azure OIDC — no static cloud credentials required.

Status: Stable

<!-- Run `/platform-skills:awesome-docs generate` on this file to add an animated architecture flow and input carousel diagram. -->

## Quick start

```yaml
- uses: your-org/actions/terraform-plan@v1
  with:
    working_directory: terraform/environments/production
    github_token: ${{ secrets.GITHUB_TOKEN }}
    aws_role_arn: arn:aws:iam::123456789012:role/terraform-plan
```

---

## Inputs

| Input | Type | Required | Secret | Default | Description |
|---|---|---|---|---|---|
| `working_directory` | string | **Yes** | No | — | Terraform root module directory |
| `terraform_version` | string | No | No | `1.9.0` | Terraform version to install |
| `github_token` | string | **Yes** | **Yes** | — | Token for posting PR comment |
| `aws_role_arn` | string | No | No | `''` | AWS IAM role ARN for OIDC |
| `aws_region` | string | No | No | `us-east-1` | AWS region |
| `azure_client_id` | string | No | No | `''` | Azure app client ID for OIDC |
| `azure_tenant_id` | string | No | No | `''` | Azure tenant ID |
| `azure_subscription_id` | string | No | No | `''` | Azure subscription ID |
| `var_file` | string | No | No | `''` | Path to `.tfvars` file |
| `comment_on_pr` | boolean | No | No | `true` | Post plan as PR comment |

---

## Outputs

| Output | Description |
|---|---|
| `plan_exitcode` | `0` = no changes, `2` = changes present |
| `has_changes` | `true` if the plan contains infrastructure changes |

---

## Variables and secrets

```
secrets.GITHUB_TOKEN ──► inputs.github_token ──► ::add-mask:: ──► github-script token
secrets.* (none)        OIDC-based cloud auth — no static credentials stored

Cloud auth flow (AWS example):
  id-token: write permission on caller job
        │
        ▼
  GitHub OIDC provider issues JWT
        │
        ▼
  aws-actions/configure-aws-credentials assumes inputs.aws_role_arn
        │  (role ARN is a plain variable — not a secret)
        ▼
  Short-lived AWS credentials in environment
        │
        ▼
  terraform plan  (reads AWS_ACCESS_KEY_ID etc. from environment — never in logs)
```

**What is logged vs what is masked:**

| Value | Logged? |
|---|---|
| `working_directory` | ✅ Yes |
| `aws_role_arn` | ✅ Yes — not a secret, is a resource identifier |
| `github_token` | ❌ No — masked immediately |
| AWS temporary credentials | ❌ No — managed by aws-actions, never echoed |
| `terraform plan` output | ✅ Yes — shown in PR comment and job summary |

---

## Permissions

```yaml
permissions:
  contents: read
  pull-requests: write   # post plan comment
  id-token: write        # OIDC for AWS/Azure
```

---

## Idempotency

**Idempotent** — the PR comment uses a hidden marker `<!-- terraform-plan:<directory> -->` so re-running the workflow updates the existing comment rather than creating a duplicate.

---

## Concurrency (recommended)

```yaml
concurrency:
  group: terraform-plan-${{ github.ref }}
  cancel-in-progress: true
```

---

## Full example

```yaml
name: Terraform plan

on:
  pull_request:
    paths:
      - 'terraform/**'

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  plan:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - uses: your-org/actions/terraform-plan@v1
        with:
          working_directory: terraform/environments/production
          github_token: ${{ secrets.GITHUB_TOKEN }}
          aws_role_arn: ${{ vars.AWS_PLAN_ROLE_ARN }}
          aws_region: us-east-1
          var_file: environments/production.tfvars
```

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md)

# setup-terraform

> Install Terraform and restore cached provider plugins in a single `uses:` call. Pairs naturally with `terraform-plan` for a full fmt → validate → plan pipeline.

Status: Stable

<!-- Run `/platform-skills:awesome-docs generate` on this file to add an animated architecture flow and input carousel diagram. -->

## Quick start

```yaml
- uses: your-org/actions/setup-terraform@v1
  with:
    terraform_version: '1.7.0'
```

---

## How it works

```
inputs.terraform_version
        │
        ▼
Create ~/.terraform.d/plugin-cache + ~/.terraformrc
        │
        ▼
actions/cache → restore provider cache
  key: {os}-terraform-{version}-{hash(.terraform.lock.hcl)}
        │
        ▼
hashicorp/setup-terraform → install binary
        │
        ▼
outputs.terraform_version (exact installed version)
outputs.cache_hit         (true | false)
```

---

## Inputs

| Input | Type | Required | Secret | Default | Description |
|---|---|---|---|---|---|
| `terraform_version` | string | No | No | `1.7.0` | Terraform version to install |
| `working_directory` | string | No | No | `.` | Directory containing `.terraform.lock.hcl` |
| `enable_cache` | boolean | No | No | `true` | Restore provider plugin cache |
| `terraform_wrapper` | boolean | No | No | `true` | Enable wrapper (adds stdout/stderr/exitcode outputs) |

No secrets required — all inputs are plain configuration values.

---

## Outputs

| Output | Description |
|---|---|
| `terraform_version` | Exact installed Terraform version string |
| `cache_hit` | `true` if the provider cache was restored from a prior run |

---

## Variables and secrets

No secrets. All inputs are safe to hardcode or store as repo variables.

```yaml
# Cache key is derived from .terraform.lock.hcl hash — never contains credentials
# Provider plugins are public downloads — no authentication needed for caching
```

---

## Permissions

```yaml
permissions:
  contents: read   # checkout only
```

---

## Idempotency

**Idempotent** — running twice installs the same version and restores (or rebuilds) the same cache. The provider cache restore-keys fall back gracefully when the lock file changes.

---

## Concurrency (recommended)

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true   # cancel stale plan runs on new pushes
```

---

## Full example — Terraform plan pipeline

```yaml
name: Terraform Plan

on:
  pull_request:

permissions:
  contents: read
  pull-requests: write   # post plan as PR comment
  id-token: write        # OIDC for cloud credentials

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - name: Setup Terraform
        id: tf
        uses: your-org/actions/setup-terraform@v1
        with:
          terraform_version: '1.7.0'
          working_directory: infra/

      - name: Configure AWS credentials
        uses: your-org/actions/configure-cloud@v1
        with:
          cloud_provider: aws
          aws_role_arn: arn:aws:iam::123456789012:role/terraform-plan

      - name: Terraform plan
        uses: your-org/actions/terraform-plan@v1
        with:
          working_directory: infra/
          github_token: ${{ secrets.GITHUB_TOKEN }}

      - name: Print cache info
        run: echo "Cache hit: ${{ steps.tf.outputs.cache_hit }}"
```

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md)

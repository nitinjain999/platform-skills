# Terraform Reference

## Contents

- Scope
- Repository structure
- Module conventions
- State and environments
- Validation pipeline

## Scope

Use Terraform for:

- Accounts, subscriptions, networking, IAM, identity federation
- Managed Kubernetes clusters and bootstrap prerequisites
- Shared data stores, DNS, secret managers, registries, and policy wiring

Do not use Terraform for high-churn application runtime configuration that Flux or Argo CD can reconcile more safely inside the cluster.

## Repository structure

Prefer this split:

```text
modules/
  networking/
  kubernetes-cluster/
  identity/
live/
  aws/
    prod/
    staging/
  azure/
    prod/
    staging/
```

- `modules/` contains reusable abstractions with narrow scope.
- `live/` contains environment or tenant compositions.
- Keep examples near modules when publishing shared modules.

## Module conventions

- Keep modules small and composable.
- Make provider configuration live in the caller unless the module is deliberately closed over a provider.
- Standardize tags, naming, and diagnostics outputs.
- Prefer explicit input objects over sprawling variable lists when modeling a cohesive capability.
- Expose outputs needed by downstream automation such as cluster endpoints, identity ids, and secret store references.

## State and environments

- Use remote state with locking.
- Separate state by environment and blast radius, not by convenience alone.
- Keep production isolated from non-production.
- Avoid workspaces as the only environment boundary for large platforms; directory or stack separation is usually clearer.

## Format and lint

### `terraform fmt`

`terraform fmt` rewrites Terraform configuration to canonical HCL style. Run it as a check in CI so formatting drift never reaches a PR review:

```bash
terraform fmt -check -recursive
```

`-check` exits non-zero if any file would be changed. `-recursive` covers all subdirectories. Fix locally with:

```bash
terraform fmt -recursive
```

Enforce in pre-commit using the official hook:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.96.1  # pin to a release tag
    hooks:
      - id: terraform_fmt
```

### `terraform validate`

`terraform validate` checks configuration syntax and internal references without contacting any cloud API. It requires `terraform init` to have run first (providers must be installed).

```bash
terraform init -backend=false   # skip real backend for CI
terraform validate
```

`-backend=false` skips remote state configuration so validate works in CI without credentials. This catches type mismatches, missing required variables, and invalid references before a plan is attempted.

### tflint

`tflint` enforces provider-specific rules that `terraform validate` cannot — deprecated instance types, invalid AMI filters, unsupported argument names per provider version.

Minimal config at repo root:

```hcl
# .tflint.hcl
config {
  call_module_type = "local"
}

plugin "aws" {
  enabled = true
  version = "0.38.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

plugin "azurerm" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
```

Run it per module:

```bash
tflint --init          # download plugins (once)
tflint --recursive     # lint all modules from repo root
```

Key rules to never suppress:

- `terraform_deprecated_index` — catches `list[0]` style that breaks in Terraform 0.13+
- `terraform_unused_declarations` — variables and locals with no references
- `terraform_required_version` — missing `required_version` constraint
- `aws_instance_invalid_type` / `azurerm_virtual_machine_invalid_vm_size` — invalid resource sizes

### Security scanning

Use `tfsec` or `checkov` to catch misconfigurations before plan:

```bash
# tfsec (fast, Terraform-only)
tfsec . --minimum-severity HIGH

# checkov (broader, covers Terraform + other IaC)
checkov -d . --framework terraform --compact --quiet
```

Both tools identify patterns like:
- S3 buckets with public ACLs
- Security groups open to `0.0.0.0/0`
- Storage accounts without encryption
- Missing KMS keys on EKS secrets

Fail CI on HIGH and CRITICAL severity. Review MEDIUM findings in PR but do not block on them until a baseline is established.

### Recommended CI order

```
fmt -check -recursive   →   validate   →   tflint   →   tfsec/checkov   →   plan   →   apply
```

Run format and validate in parallel with lint and security checks — none of them require a remote API call. Gate the plan step until all four pass. Gate apply behind plan approval and protected environment.

## Validation pipeline

Minimum CI for Terraform changes:

1. `fmt` and `validate` — syntax, style, reference integrity
2. `tflint` — provider-specific rule enforcement
3. Security and policy checks — `tfsec` or `checkov` on HIGH+
4. `plan` with reviewable output
5. Controlled `apply` through protected environments

If the task involves module quality, add tests or example validation. If the task involves platform rollout, focus on safe composition, state isolation, and promotion gates before writing module internals.

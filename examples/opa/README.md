Status: Stable

# OPA / Conftest Examples

Production-ready Rego policies with unit tests, Regal lint config, and Conftest integration.

## Examples

| Example | Type | Description |
|---------|------|-------------|
| [conftest/](conftest/) | Conftest + Terraform | S3 encryption and ACL policies with full test suite |

## Usage

```bash
# Install tools
brew install conftest
brew install styrainc/packages/regal

# 1. Check formatting
conftest fmt ./conftest/policies/*.rego --check

# 2. Lint with Regal
regal lint ./conftest/policies

# 3. Run unit tests
conftest verify --policy ./conftest/policies

# 4. Run integration test against sample Terraform
conftest test --policy ./conftest/policies --namespace terraform.s3 ./conftest/tests/main.tf
```

## See Also

- [references/opa.md](../../references/opa.md) — Rego v1 syntax, rule types, input shapes, testing, Conftest CLI, Regal, GitHub Actions integration
- `/platform-skills:opa` — generate policies, write tests, run validation pipeline, explain or debug Rego

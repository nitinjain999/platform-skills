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

## Validation pipeline

Minimum CI for Terraform changes:

1. `fmt` and `validate`
2. Linting and static analysis
3. Security and policy checks
4. `plan` with reviewable output
5. Controlled `apply` through protected environments

If the task involves module quality, add tests or example validation. If the task involves platform rollout, focus on safe composition, state isolation, and promotion gates before writing module internals.

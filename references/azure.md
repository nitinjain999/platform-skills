# Azure Reference

## Contents

- Foundation scope
- Subscription and identity model
- AKS platform patterns
- Terraform and CI guidance

## Foundation scope

For Azure platform work, start from:

- Management group hierarchy
- Subscription segmentation
- Azure Policy and RBAC model
- Shared network and connectivity patterns

Prefer clear separation of subscriptions by environment or workload boundary instead of a flat single-subscription model.

## Subscription and identity model

- Use Entra ID-backed groups and role assignments for humans.
- Use GitHub Actions OIDC federation to avoid long-lived service principal secrets.
- Use workload identity for in-cluster components that need Azure APIs.

## AKS platform patterns

- Provision AKS, networking, managed identities, and shared services with Terraform.
- Reconcile cluster add-ons and workloads with Flux or Argo CD after bootstrap.
- Keep platform add-ons versioned and promoted through Git, not portal changes.

## Terraform and CI guidance

- Make subscription and tenant targeting explicit in code and workflow naming.
- Enforce policy, tagging, and diagnostics consistently across subscriptions.
- Keep role assignments narrow and auditable.
- Use protected environments for applies to production subscriptions.

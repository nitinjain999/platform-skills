# AWS Reference

## Contents

- Foundation scope
- Account and identity model
- EKS platform patterns
- Terraform and CI guidance

## Foundation scope

For AWS platform work, start from:

- Organization and account boundaries
- IAM and federation model
- Networking baseline
- Central logging, audit, and security services

Prefer multi-account design over a single shared account for serious environments.

## Account and identity model

- Separate production and non-production accounts.
- Use IAM Identity Center or equivalent SSO for humans.
- Use GitHub Actions OIDC for CI federation into AWS roles.
- Use IRSA or workload identity equivalents for pods that need AWS APIs.

## EKS platform patterns

- Provision cluster foundations, node groups, networking, and IAM with Terraform.
- Install cluster add-ons such as ingress, cert-manager, external-dns, and observability with Flux or Argo CD.
- Keep shared controllers in dedicated namespaces with explicit ownership and upgrade paths.

## Terraform and CI guidance

- Standardize provider configuration and tagging.
- Limit role permissions used by CI to the environment and action required.
- Review `plan` output and security checks before apply.
- Surface account, region, and workspace context clearly in workflows to avoid applying to the wrong target.

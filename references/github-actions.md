# GitHub Actions Reference

## Contents

- Scope
- Workflow design
- Reusable patterns
- Security controls
- Promotion orchestration

## Scope

Use GitHub Actions for:

- Pull request validation
- Terraform plan and apply orchestration
- Container build and publish
- Version bump or release automation
- Promotion workflows across environments

Do not let workflow files become the only place where platform architecture is defined.

## Workflow design

- Prefer reusable workflows and composite actions over copy-pasted job graphs.
- Keep jobs small and named by intent.
- Use required checks and branch protection to make platform policy enforceable.
- Expose target environment, region, or cluster in workflow inputs and logs.

## Reusable patterns

- `validate`: formatting, linting, policy, unit checks
- `plan`: Terraform plan or Kubernetes manifest render checks
- `build`: image or artifact packaging
- `promote`: controlled update of version pins or overlays
- `deploy`: guarded apply or merge-to-reconcile flow

## Security controls

- Use OIDC federation for AWS and Azure authentication.
- Limit token permissions per workflow.
- Prefer environment protection rules for production operations.
- Keep secrets centralized and minimize repository-level long-lived credentials.

## Promotion orchestration

- Promote by updating immutable versions, not by rebuilding different artifacts per environment.
- If Flux or Argo CD is in use, have Actions update Git and let the reconciler deploy.
- If Terraform is in use, separate `plan` from `apply` and require approval for production.

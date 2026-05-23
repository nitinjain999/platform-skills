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
- Pin all external `uses:` to a full commit SHA — tags are mutable and can be rewritten.

## Promotion orchestration

- Promote by updating immutable versions, not by rebuilding different artifacts per environment.
- If Flux or Argo CD is in use, have Actions update Git and let the reconciler deploy.
- If Terraform is in use, separate `plan` from `apply` and require approval for production.

## Composite actions

Composite actions package a sequence of steps into a single reusable `uses:` call. They are the preferred pattern for step-level DRY across workflows.

**Key rules:**
- `shell:` is required on every `run:` step — composite actions have no inherited default.
- Secrets cannot be accessed directly — pass as `required: true` inputs.
- Pin all external `uses:` to a full 40-character SHA.
- Never interpolate `${{ inputs.* }}` directly in `run:` — pass through `env:` to prevent shell injection.
- Use `${{ github.action_path }}` to reference files bundled with the action.
- Write `$GITHUB_STEP_SUMMARY` in every action for a rich job summary visible in the Actions UI.

**Full reference:** [references/composite-actions.md](composite-actions.md)

**Slash command:** `/platform-skills:composite-actions generate` — guided interview → full repo scaffold → optional PR

**Working examples:**
- `examples/github-actions/composite-actions/docker-build-push/` — GHCR push, OIDC, multi-platform, job summary
- `examples/github-actions/composite-actions/notify-slack/` — Slack webhook, `::add-mask::`, secrets flow
- `examples/github-actions/composite-actions/k8s-deploy/` — kubectl, kubeconfig secret, cleanup post-step
- `examples/github-actions/composite-actions/terraform-plan/` — Terraform plan, OIDC, idempotent PR comment
- `examples/github-actions/composite-actions/security-scan/` — Trivy, severity gate, SARIF, annotations
- `examples/github-actions/composite-actions/release-tag/` — semver bump, `$GITHUB_OUTPUT` chaining, changelog
- `examples/github-actions/composite-actions/pr-comment/` — `github-script`, upsert pattern, token scoping

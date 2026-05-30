# Demo: GitHub Actions Supply Chain

> Status: Stable

A GitHub Actions workflow with four supply chain vulnerabilities. Platform-skills catches them all before the workflow is merged.

## What's wrong with bad.yml

| Finding | Severity | Risk |
|---|---|---|
| `actions/checkout@main` — unpinned action | Critical | Tag can be moved to malicious commit; SolarWinds-style attack |
| `permissions: write-all` | Critical | Compromised step gets write access to entire repo |
| `aws-access-key-id` in secrets — long-lived keys | High | Leaked key = permanent AWS access until manually rotated |
| `actions/setup-node@main` — unpinned | High | Same supply chain risk as checkout |
| `aws-actions/configure-aws-credentials@main` — unpinned | High | Same supply chain risk |

## What changed in fixed.yml

- All actions pinned to commit SHA — immune to tag-move attacks
- `permissions: write-all` replaced with `id-token: write` + `contents: read` — minimal surface
- Long-lived AWS secrets replaced with OIDC `role-to-assume` — no stored credentials
- Top-level `permissions: contents: read` as safe default for all jobs

## Prerequisites for fixed.yml

1. Create an IAM role with a trust policy allowing the GitHub OIDC provider
2. Set `vars.AWS_DEPLOY_ROLE_ARN` and `vars.S3_BUCKET` as GitHub Actions variables (not secrets)

IAM trust policy snippet:
```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "repo:ORG/REPO:ref:refs/heads/main"
    }
  }
}
```

## Try it yourself

```text
Use $platform-skills to review this GitHub Actions workflow for supply chain security:
pinned actions, OIDC, least-privilege permissions, and secret handling.
```

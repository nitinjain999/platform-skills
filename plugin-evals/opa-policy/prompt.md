---
description: "Ported from evals/opa-policy. Rego deny rule for wildcard IAM actions plus conftest test and CI placement."
tags: [opa, smoke]
max_turns: 12
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
---

A security audit found that several Terraform-managed AWS IAM policies use `"Action": "*"`. You need to prevent this from reaching production.

Write an OPA/Rego policy that:

1. Blocks any `aws_iam_policy` resource where any statement contains `"Action": "*"` or `"Action": ["*"]`.
2. Uses proper METADATA annotation (title, description, entrypoint).
3. Uses `import rego.v1`.
4. Produces a clear `deny` message naming the offending resource.

Also provide:
- A `conftest` test file (`policy_test.rego`) with one passing and one failing test case.
- The exact `conftest test` command to run it in CI.
- Where in the GitHub Actions pipeline this check should run relative to `terraform plan`.

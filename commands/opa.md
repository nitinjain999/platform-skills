---
name: opa
description: Generate, test, validate, explain, and debug OPA (Open Policy Agent) Rego policies and Conftest configurations. Covers deny/warn/violation rules, unit tests, regal linting, conftest fmt, namespace design, input shape analysis, and GitHub Actions integration. Use when asked to "write a policy", "test a rego file", "validate policies", "explain this rego", or "why is my policy not firing".
argument-hint: "[generate|test|validate|explain|debug] [policy description or file path]"
---

Write, test, validate, explain, and debug OPA Rego policies with Conftest.

## Mode: generate

Write a production-ready Rego policy from a description.

Steps:
1. Ask for: target resource type (Terraform HCL, Kubernetes manifest, GitHub Actions workflow, Dockerfile, JSON/YAML), the rule logic (what to deny or warn on), and whether a named namespace is needed
2. Parse what Conftest sees — use `conftest parse <file>` to show the input shape if the user has a file, then write rules that match that shape exactly
3. Generate the policy file:
   - Start with a `# METADATA` block: `title`, `description`, `authors`, `entrypoint: true`
   - Declare `package <namespace>` — use `main` only when a single policy set applies; use a named package (`package terraform.iam`, `package k8s.pods`) for multi-domain repos
   - Add `import rego.v1` — required for modern Rego syntax
   - Use `deny` for hard failures, `warn` for advisory violations, `violation` for OPA framework integrations (Gatekeeper, Conftest policy sets)
   - Generate a descriptive `msg` that includes the offending resource name/value and a remediation hint
   - Use `some` for iteration, `in` for membership, `startswith`/`contains` for string matching
4. Show the Conftest command to test the policy against sample input
5. Output the CI step — always emit the exact runnable command inline in the response (do not just describe it):
   ```yaml
   - run: terraform validate
   - run: conftest test --policy ./policies ./main.tf
   - run: terraform plan -out=tfplan.binary
   ```
   conftest runs **after `terraform validate`** and **before `terraform plan`** as a blocking gate — if conftest fails, plan must not run

Reference: `references/opa.md` → Rule Types, Input Shape, Rego v1 Syntax

## Mode: test

Write `_test.rego` unit tests for a given policy.

Steps:
1. Read the policy to understand: package name, rule names, input shape
2. Generate a test file named `<policy>_test.rego` in the same directory:
   - Package: `package <namespace>_test` (e.g. `package terraform.iam_test`)
   - Add `import rego.v1`
   - Import the policy under test: `import data.<namespace>`
3. For each `deny`/`warn`/`violation` rule, write:
   - A **positive test** (rule fires): name prefixed `test_deny_` / `test_warn_`; assert `count(<rule>) == 1` or `count(<rule>) > 0`
   - A **negative test** (rule does not fire): name prefixed `test_allow_`; assert `count(<rule>) == 0`
4. Write a helper function that builds the input fixture for each case — keep fixtures minimal and focused on the attributes the rule actually checks
5. Run tests: `conftest verify --policy <dir>`

Reference: `references/opa.md` → Unit Tests

## Mode: validate

Run the full policy validation pipeline against a directory.

Steps:
1. **Format check**: `conftest fmt <dir>/*.rego --check` — fails if any file is not canonically formatted
2. **Auto-format** (if check fails): `conftest fmt <dir>/*.rego` — rewrites in place
3. **Lint**: `regal lint <dir>` — reports style and correctness violations; fix each finding before continuing
4. **Unit tests**: `conftest verify --policy <dir>` — all `*_test.rego` files must pass
5. **Integration test** (if test data is available): `conftest test --policy <dir> <input-files>`
6. Report: PASS or list each failing step with the exact error and the fix

Reference: `references/opa.md` → Validation Pipeline, Regal

## Mode: explain

Translate an existing Rego policy into plain English.

Steps:
1. Read the policy file — identify: package, rule names, types (deny/warn/violation), and the conditions
2. For each rule, explain in plain language:
   - **What it checks**: the resource type and attribute being evaluated
   - **What triggers it**: the condition that causes a deny/warn
   - **What the message says**: what a developer will see when this fires
   - **What is excluded**: any allow-list or exception conditions
3. Show the input shape the rule expects — map each `input.<field>` to the resource attribute it reads
4. Note any dependencies on `data.*` (external allow-lists or config)

Reference: `references/opa.md` → Input Shape, Rego v1 Syntax

## Mode: debug

Diagnose why a policy is not firing as expected.

Steps:
1. Collect: policy file, input file or `conftest parse <file>` output, and the `conftest test` or `conftest verify` output
2. Check in order:
   - **Namespace mismatch**: is the package name matching `--namespace` or `--all-namespaces`?
   - **Rule name**: does the rule start with `deny`, `warn`, or `violation`? Other names are silently ignored by Conftest
   - **Input shape mismatch**: run `conftest parse <input-file>` and compare each `input.<path>` in the rule against the actual parsed structure
   - **Partial vs complete rule**: is the rule a set comprehension (`deny[msg]`) or a boolean? Conftest expects set comprehensions for message output
   - **`import rego.v1` missing**: without it, `if`, `in`, `contains` may not work as expected
   - **`some` missing**: iterating without `some` can cause unexpected behaviour in Rego v0 compatibility mode
3. State the most likely root cause with the exact line to fix
4. Show the corrected rule and how to verify it fires: `conftest test --policy <dir> <input>`

Reference: `references/opa.md` → Troubleshooting

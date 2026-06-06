---
name: opa
description: Generate, test, validate, explain, and debug OPA (Open Policy Agent) Rego policies and Conftest configurations. Covers deny/warn/violation rules, unit tests, regal linting, conftest fmt, namespace design, input shape analysis, and GitHub Actions integration. Use when asked to "write a policy", "test a rego file", "validate policies", "explain this rego", or "why is my policy not firing".
argument-hint: "[generate|test|validate|explain|debug] [policy description or file path]"
---

Write, test, validate, explain, and debug OPA Rego policies with Conftest.

---

## Interactive Wizard (fires when no arguments are provided)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. generate — write a new production-ready Rego policy
  2. test     — write _test.rego unit tests for an existing policy
  3. validate — run the full pipeline (fmt, lint, tests) against a directory
  4. explain  — translate an existing Rego policy into plain English
  5. debug    — diagnose why a policy is not firing as expected

Enter 1–5 or mode name:
```

**Q2 — Context** (after mode selected, one at a time):
- **generate**: `Describe the policy — target resource type (Terraform/Kubernetes/GHA/Dockerfile) and what to deny or warn on:`
- **test**: `Paste the Rego policy to write tests for:`
- **validate**: `Provide the directory path containing your .rego files:`
- **explain**: `Paste the Rego policy to explain:`
- **debug**: `Describe the symptom — is the policy not firing, producing no output, or throwing an error? Paste the conftest output:`

Then proceed into the relevant mode below.

---

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
5. State CI placement: conftest runs **after `terraform validate`** and **before `terraform plan`** as a blocking gate — failing conftest must prevent plan from running

**Validation:** Test the policy against both a passing and a failing resource before deploying to CI:
```bash
# Should produce no output (policy passes)
conftest test --policy <dir> <passing-resource.yaml>

# Should produce a deny/warn message (policy fires)
conftest test --policy <dir> <failing-resource.yaml>
```
Both must behave as expected. A policy that never fires on a failing resource is not enforcing anything.

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

**Validation:** All tests must pass with zero skipped:
```bash
conftest verify --policy <dir>
# Expected: PASS - X tests, 0 failures, 0 skipped
# Skipped tests mean test fixtures are incomplete — fix before merging
```

## Mode: validate

Run the full policy validation pipeline against a directory.

Steps:
1. **Format check**: `conftest fmt <dir>/*.rego --check` — fails if any file is not canonically formatted
2. **Auto-format** (if check fails): `conftest fmt <dir>/*.rego` — rewrites in place
3. **Lint**: `regal lint <dir>` — reports style and correctness violations; fix each finding before continuing
4. **Unit tests**: `conftest verify --policy <dir>` — all `*_test.rego` files must pass
5. **Integration test** (if test data is available): `conftest test --policy <dir> <input-files>`
6. Report: PASS or list each failing step with the exact error and the fix

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

## Mode: debug

Diagnose why a policy is not firing as expected.

Steps:
1. Collect: policy file, input file, and the `conftest test` or `conftest verify` output
2. Check input shape — extract only the paths the policy reads:
   ```bash
   # Extract every input.<path> reference from the policy
   grep -oE 'input\.[a-zA-Z0-9_.[\]]+' <policy-file> | sort -u
   # Build a targeted jq filter from those paths and run it
   conftest parse <input-file> | jq '{field1: .<path1>, field2: .<path2>, ...}'
   ```
   Compare each extracted path against the parsed output. A missing or mismatched key is the most common cause of silent policy failures.
3. Check in order:
   - **Namespace mismatch**: is the package name matching `--namespace` or `--all-namespaces`?
   - **Rule name**: does the rule start with `deny`, `warn`, or `violation`? Other names are silently ignored by Conftest
   - **Input shape mismatch**: identified above in step 2
   - **Partial vs complete rule**: is the rule a set comprehension (`deny[msg]`) or a boolean? Conftest expects set comprehensions for message output
   - **`import rego.v1` missing**: without it, `if`, `in`, `contains` may not work as expected
   - **`some` missing**: iterating without `some` can cause unexpected behaviour in Rego v0 compatibility mode
4. State the most likely root cause with the exact line to fix
5. Show the corrected rule and how to verify it fires: `conftest test --policy <dir> <input>`

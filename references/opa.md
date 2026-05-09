# OPA / Conftest Reference

Covers Rego v1 syntax, rule types, package namespacing, input shapes, unit testing, Conftest CLI, Regal linting, formatting, GitHub Actions integration, and troubleshooting.

---

## Rego v1 Syntax

Always include `import rego.v1` at the top of every policy file. This enables modern syntax (`if`, `contains`, `in`, `every`) and disables Rego v0 quirks.

```rego
# METADATA
# title: Deny public S3 buckets
# description: S3 buckets must not be publicly accessible
# authors:
# - Platform Team <platform@example.com>
# entrypoint: true
package terraform.s3

import rego.v1
```

### Core constructs

```rego
# Iteration with some
deny contains msg if {
    some resource_name
    resource := input.resource.aws_s3_bucket[resource_name]
    resource.acl == "public-read"
    msg := sprintf("S3 bucket '%s' must not have public-read ACL", [resource_name])
}

# Set membership with in
allowed_regions := {"eu-central-1", "eu-west-1"}

deny contains msg if {
    some name
    resource := input.resource.aws_instance[name]
    not resource.region in allowed_regions
    msg := sprintf("EC2 instance '%s' must be in an allowed region", [name])
}

# String helpers
deny contains msg if {
    some name
    image := input.resource.aws_ecr_repository[name]
    not startswith(image.name, "prod-")
    msg := sprintf("ECR repository '%s' name must start with 'prod-'", [name])
}

# Negation — not (AWS provider >= 5: encryption is a separate resource)
deny contains msg if {
    some name
    _ = input.resource.aws_s3_bucket[name]
    not _has_enc_resource(name)
    msg := sprintf("S3 bucket '%s' must have an aws_s3_bucket_server_side_encryption_configuration resource", [name])
}

_has_enc_resource(bucket_name) if {
    some enc_name
    enc := input.resource.aws_s3_bucket_server_side_encryption_configuration[enc_name]
    enc.bucket == bucket_name
}

# Existential check — deny if any ingress rule is fully open
deny contains msg if {
    some name
    group := input.resource.aws_security_group[name]
    some rule in group.ingress
    rule.from_port == 0
    rule.to_port == 65535
    msg := sprintf("Security group '%s' has an overly permissive ingress rule", [name])
}
```

---

## Rule Types

| Rule | Conftest behaviour | When to use |
|------|--------------------|-------------|
| `deny` | Fails the check (exit code 1) | Hard requirements — must not be violated |
| `warn` | Prints warning but passes | Advisory — should be fixed but not blocking |
| `violation` | Fails (used by Gatekeeper / OPA policy sets) | Framework integrations |

Rules must be named starting with `deny`, `warn`, or `violation` — Conftest silently ignores any other rule name.

Use set comprehensions (`deny contains msg if { ... }`) rather than booleans so Conftest can report the message string.

---

## METADATA Block

Every policy file should have a METADATA block immediately before the package declaration:

```rego
# METADATA
# title: Short human-readable title
# description: One-sentence description of what this policy enforces
# authors:
# - Team Name <email@example.com>
# organizations:
# - Your Org
# entrypoint: true
package my.namespace
```

`entrypoint: true` marks the package as an OPA bundle entrypoint for tools like `opa build` and Regal's `no-defined-entrypoint` rule. Conftest discovers policies by package name and rule names (`deny`/`warn`/`violation`) — not by this flag. Include it for lint compliance and bundle compatibility.

---

## Package Namespacing

- `package main` — default namespace; used when running `conftest test` without `--namespace`
- Named packages — use for multi-domain repos to avoid collisions

```rego
package terraform.iam      # --namespace terraform.iam
package k8s.pods           # --namespace k8s.pods
package github.repository  # --namespace github.repository
```

Run a specific namespace:
```bash
conftest test --policy ./policies --namespace terraform.iam plan.json
```

Run all namespaces:
```bash
conftest test --policy ./policies --all-namespaces plan.json
```

---

## Input Shape

Conftest parses config files into a JSON input object. The shape depends on the file type.

### Terraform HCL

```hcl
# main.tf
resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-app-data"
  acl    = "private"
}
```

Parsed as:
```json
{
  "resource": {
    "aws_s3_bucket": {
      "my_bucket": {
        "bucket": "my-app-data",
        "acl": "private"
      }
    }
  }
}
```

Access in Rego:
```rego
input.resource.aws_s3_bucket[name].acl
```

### Terraform Plan JSON

```bash
terraform plan -out=tfplan.binary
terraform show -json tfplan.binary > tfplan.json
conftest test --policy ./policies tfplan.json
```

The plan JSON has a different shape — use `input.resource_changes[_]`:
```rego
deny contains msg if {
    some change in input.resource_changes
    change.type == "aws_s3_bucket"
    change.change.after.acl == "public-read"
    msg := sprintf("S3 bucket '%s' must not have public-read ACL", [change.name])
}
```

### Kubernetes YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
        - name: app
          image: my-app:latest
```

Parsed as:
```json
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": { "name": "my-app" },
  "spec": {
    "template": {
      "spec": {
        "containers": [{ "name": "app", "image": "my-app:latest" }]
      }
    }
  }
}
```

### Inspect actual input

Always check the actual parsed input before writing rules:

```bash
conftest parse main.tf
conftest parse deployment.yaml
conftest parse tfplan.json
```

---

## Writing Policies

### Full example — Terraform IAM policy

```rego
# METADATA
# title: IAM policy least privilege
# description: IAM policies must not use wildcard actions or resources
# authors:
# - Platform Team <platform@example.com>
# entrypoint: true
package terraform.iam

import rego.v1

deny contains msg if {
    some name
    policy := input.resource.aws_iam_policy[name]
    some statement in policy.policy.Statement
    statement.Effect == "Allow"
    statement.Action == "*"
    msg := sprintf("IAM policy '%s' must not use wildcard Action '*'", [name])
}

deny contains msg if {
    some name
    policy := input.resource.aws_iam_policy[name]
    some statement in policy.policy.Statement
    statement.Effect == "Allow"
    statement.Resource == "*"
    statement.Action != "*"
    msg := sprintf("IAM policy '%s' must not use wildcard Resource '*'", [name])
}

warn contains msg if {
    some name
    role := input.resource.aws_iam_role[name]
    not role.description
    msg := sprintf("IAM role '%s' should have a description", [name])
}
```

### Full example — Kubernetes pod security

```rego
# METADATA
# title: Pod security baseline
# description: Pods must run as non-root with read-only root filesystem
# authors:
# - Platform Team <platform@example.com>
# entrypoint: true
package k8s.pods

import rego.v1

deny contains msg if {
    input.kind == "Deployment"
    some container in input.spec.template.spec.containers
    not container.securityContext.runAsNonRoot
    msg := sprintf("Container '%s' must set runAsNonRoot: true", [container.name])
}

deny contains msg if {
    input.kind == "Deployment"
    some container in input.spec.template.spec.containers
    not container.securityContext.readOnlyRootFilesystem
    msg := sprintf("Container '%s' must set readOnlyRootFilesystem: true", [container.name])
}

deny contains msg if {
    input.kind == "Deployment"
    some container in input.spec.template.spec.containers
    container.image == _
    endswith(container.image, ":latest")
    msg := sprintf("Container '%s' must not use ':latest' image tag", [container.name])
}
```

---

## Unit Tests

Test files must be named `<policy>_test.rego` and placed in the same directory.

```rego
# METADATA
# title: Tests for IAM policy least privilege
package terraform.iam_test

import data.terraform.iam
import rego.v1

# --- deny wildcard action ---

test_deny_wildcard_action if {
    input := {
        "resource": {
            "aws_iam_policy": {
                "my_policy": {
                    "policy": {
                        "Statement": [{"Effect": "Allow", "Action": "*", "Resource": "arn:aws:s3:::*"}]
                    }
                }
            }
        }
    }
    count(iam.deny) == 1 with input as input
}

test_allow_scoped_action if {
    input := {
        "resource": {
            "aws_iam_policy": {
                "my_policy": {
                    "policy": {
                        "Statement": [{"Effect": "Allow", "Action": "s3:GetObject", "Resource": "arn:aws:s3:::my-bucket/*"}]
                    }
                }
            }
        }
    }
    count(iam.deny) == 0 with input as input
}

# Helper function for building fixtures
make_policy(action, resource) := {
    "resource": {
        "aws_iam_policy": {
            "test_policy": {
                "policy": {
                    "Statement": [{"Effect": "Allow", "Action": action, "Resource": resource}]
                }
            }
        }
    }
}

test_deny_wildcard_resource if {
    count(iam.deny) == 1 with input as make_policy("s3:GetObject", "*")
}
```

Run tests:
```bash
conftest verify --policy ./policies
```

---

## Validation Pipeline

Run these in order — fix each before proceeding to the next.

### 1. Format check

```bash
# Check — non-zero exit if any file is unformatted
conftest fmt ./policies/*.rego --check

# Auto-fix — rewrites files in place
conftest fmt ./policies/*.rego
```

### 2. Regal lint

```bash
# Install
brew install styrainc/packages/regal   # macOS
# or
curl -L -o regal "https://github.com/StyraInc/regal/releases/latest/download/regal_$(uname -s)_$(uname -m)"
chmod +x regal && sudo mv regal /usr/local/bin/

# Lint all .rego files
regal lint ./policies
```

Configure Regal with `.regal/config.yaml`:

```yaml
# .regal/config.yaml
rules:
  idiomatic:
    no-defined-entrypoint:
      level: error
  style:
    line-length:
      level: warning
      max-line-length: 120
    prefer-snake-case:
      level: warning
  bugs:
    rule-named-if:
      level: error
    unused-variable:
      level: error
```

### 3. Unit tests

```bash
conftest verify --policy ./policies
```

### 4. Integration test against real input

```bash
# HCL files
conftest test --policy ./policies ./terraform/*.tf

# Terraform plan
conftest test --policy ./policies ./tfplan.json

# Kubernetes manifests
conftest test --policy ./policies ./k8s/*.yaml --all-namespaces

# From a remote git repo (pulls policies then tests)
conftest test \
  --update "git::https://github.com/your-org/opa-policies.git//terraform" \
  --all-namespaces \
  ./terraform/*.tf
```

---

## GitHub Actions Integration

```yaml
name: Policy validation

on:
  pull_request:

jobs:
  opa:
    name: OPA / Conftest
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1

      - name: Install Conftest
        run: |
          VERSION=$(curl -s https://api.github.com/repos/open-policy-agent/conftest/releases/latest | jq -r .tag_name)
          curl -Lo conftest.tar.gz "https://github.com/open-policy-agent/conftest/releases/download/${VERSION}/conftest_${VERSION#v}_Linux_x86_64.tar.gz"
          tar xzf conftest.tar.gz conftest
          sudo mv conftest /usr/local/bin/

      - name: Install Regal
        run: |
          VERSION=$(curl -s https://api.github.com/repos/StyraInc/regal/releases/latest | jq -r .tag_name)
          curl -Lo regal "https://github.com/StyraInc/regal/releases/download/${VERSION}/regal_Linux_x86_64"
          chmod +x regal && sudo mv regal /usr/local/bin/

      - name: Check formatting
        run: conftest fmt ./policies --check

      - name: Lint with Regal
        run: regal lint ./policies

      - name: Run unit tests
        run: conftest verify --policy ./policies

      - name: Run integration tests
        run: conftest test --policy ./policies --all-namespaces ./tests/**/*.tf ./tests/**/*.yaml
```

---

## Shared Data (allow-lists)

Use `data.*` for allow-lists shared across policies — store in a JSON or YAML file alongside the policies.

```json
// policies/data/allowed_regions.json
{
  "allowed_regions": ["eu-central-1", "eu-west-1", "us-east-1"]
}
```

```rego
import rego.v1

deny contains msg if {
    some name
    instance := input.resource.aws_instance[name]
    not instance.region in data.allowed_regions
    msg := sprintf("Instance '%s' is not in an allowed region", [name])
}
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Policy produces no output, input matches | Rule not named `deny`/`warn`/`violation` | Rename rule to start with `deny`, `warn`, or `violation` |
| `conftest test` passes but shouldn't | Namespace mismatch | Run with `--all-namespaces` or add `--namespace <package>` |
| `undefined ref: input.X` | Input shape wrong | Run `conftest parse <file>` and check actual field path |
| Rule fires on everything | Missing `some` for iteration | Add `some <name>` before iterating over `input.resource[name]` |
| `import rego.v1` causes error | Old Conftest version | Upgrade to Conftest >= 0.46.0 |
| `conftest verify` finds no tests | Test file not `_test.rego` | Rename to `<policy>_test.rego` |
| Regal: `no-defined-entrypoint` | Missing `# entrypoint: true` in METADATA | Add METADATA block with `entrypoint: true` |
| Boolean rule always true/false | Using boolean instead of set comprehension | Change `deny if { ... }` to `deny contains msg if { ... msg := "..." }` |
| `conftest fmt --check` fails | File not canonically formatted | Run `conftest fmt ./policies/*.rego` to auto-fix |

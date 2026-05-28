---
name: renovate
description: Generate renovate.json covering all dependency file types used in a repo, or emit a GitHub Actions workflow that validates renovate.json on every PR that touches it.
argument-hint: "[generate|workflow]"
---

You are a senior platform engineer specialising in dependency update automation with Renovate.

The input is: $ARGUMENTS

Parse the first word as the mode:
- `generate` — scan this repo and create renovate.json
- `workflow` — emit a GitHub Actions workflow that validates renovate.json on PR

Reference: `references/renovate.md`

---

## Interactive Wizard (fires when $ARGUMENTS is empty)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. generate  — scan this repo and create renovate.json covering all detected dep file types
  2. workflow  — generate a GitHub Actions workflow that validates renovate.json on every PR

Enter 1–2 or mode name:
```

Then proceed into the relevant mode below.

---

## Mode: generate

Scan the repo working tree for dependency file types, then emit a `renovate.json` that covers exactly those managers — no more, no less.

### Step 1 — Detect ecosystems

Scan for files matching these patterns. Exclude `.git/`, `node_modules/`, `vendor/`, `.terraform/`, `charts/`.

| File pattern | Manager | Key rule |
|---|---|---|
| `.github/workflows/*.yml` | `github-actions` | Pin action digests |
| `*.tf`, `*.tfvars` | `terraform` | Providers + modules |
| `Chart.yaml`, `requirements.yaml` | `helmv3` | Helm chart deps |
| `go.mod` | `gomod` | Go modules |
| `package.json`, `package-lock.json`, `yarn.lock` | `npm` | Node packages |
| `requirements*.txt`, `Pipfile`, `pyproject.toml` | `pip` | Python packages |
| `Dockerfile`, `docker-compose*.yml` | `docker` | Container images |
| `Cargo.toml` | `cargo` | Rust crates |
| Kubernetes manifests (`kind: Deployment/StatefulSet/DaemonSet`) | `kubernetes` | Image tags |

Print a coverage table before emitting output:

```
Detected dependency file types:
✅ github-actions  → .github/workflows/ (N files)
✅ terraform       → examples/**/*.tf (N files)
✅ helmv3          → examples/**/Chart.yaml (N files)
⚠️  npm            → package.json (1 file) — not covered in current renovate.json
ℹ️  cargo          → no Cargo.toml found — skipped
```

### Step 2 — Emit renovate.json

Generate a `renovate.json` containing only the managers detected in Step 1.

**Always include this base:**

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    ":dependencyDashboard",
    ":semanticCommits",
    ":separateMajorReleases"
  ],
  "dependencyDashboard": true,
  "dependencyDashboardTitle": "Renovate Dependency Dashboard",
  "timezone": "<detect from `git config --global core.timezone`; ask if undetectable>",
  "schedule": ["before 6am on monday"],
  "labels": ["dependencies", "renovate"],
  "prConcurrentLimit": 5,
  "prCreation": "not-pending",
  "rebaseWhen": "conflicted",
  "semanticCommits": "enabled",
  "vulnerabilityAlerts": {
    "enabled": true,
    "labels": ["security"]
  },
  "osvVulnerabilityAlerts": true,
  "ignorePaths": [
    "**/node_modules/**",
    "**/vendor/**",
    "**/.terraform/**",
    "**/charts/**"
  ]
}
```

**Per-detected-manager `packageRules` (include only detected managers):**

`github-actions`:
```json
{
  "description": "GitHub Actions — pin to commit SHA for supply chain security",
  "matchManagers": ["github-actions"],
  "pinDigests": true,
  "automerge": false,
  "groupName": "GitHub Actions",
  "schedule": ["before 6am on monday"]
}
```

`terraform`:
```json
{
  "description": "Terraform providers — automerge minor/patch",
  "matchManagers": ["terraform"],
  "matchDepTypes": ["required_provider"],
  "groupName": "Terraform providers",
  "automerge": true,
  "automergeType": "pr",
  "minimumReleaseAge": "3 days",
  "matchUpdateTypes": ["minor", "patch"]
},
{
  "description": "Terraform modules — review major versions manually",
  "matchManagers": ["terraform"],
  "matchDepTypes": ["module"],
  "automerge": false,
  "groupName": "Terraform modules"
}
```

`helmv3`:
```json
{
  "description": "Helm charts — automerge patch only",
  "matchManagers": ["helmv3"],
  "automerge": true,
  "automergeType": "pr",
  "minimumReleaseAge": "3 days",
  "matchUpdateTypes": ["patch"]
}
```

`gomod`:
```json
{
  "description": "Go modules — automerge minor/patch",
  "matchManagers": ["gomod"],
  "automerge": true,
  "automergeType": "pr",
  "minimumReleaseAge": "3 days",
  "matchUpdateTypes": ["minor", "patch"],
  "groupName": "Go modules"
}
```

`npm`:
```json
{
  "description": "npm packages — automerge minor/patch",
  "matchManagers": ["npm"],
  "automerge": true,
  "automergeType": "pr",
  "minimumReleaseAge": "3 days",
  "matchUpdateTypes": ["minor", "patch"],
  "groupName": "npm packages"
}
```

`pip`:
```json
{
  "description": "Python packages — automerge minor/patch",
  "matchManagers": ["pip_requirements", "pip-compile", "pipenv", "poetry"],
  "automerge": true,
  "automergeType": "pr",
  "minimumReleaseAge": "3 days",
  "matchUpdateTypes": ["minor", "patch"],
  "groupName": "Python packages"
}
```

`docker`:
```json
{
  "description": "Container images — review all updates",
  "matchManagers": ["docker-compose", "dockerfile"],
  "automerge": false,
  "groupName": "Container images"
}
```

`kubernetes`:
```json
{
  "description": "Kubernetes container images — review all updates",
  "matchManagers": ["kubernetes"],
  "automerge": false,
  "groupName": "Kubernetes images"
}
```

`cargo`:
```json
{
  "description": "Rust crates — automerge minor/patch",
  "matchManagers": ["cargo"],
  "automerge": true,
  "automergeType": "pr",
  "minimumReleaseAge": "3 days",
  "matchUpdateTypes": ["minor", "patch"],
  "groupName": "Rust crates"
}
```

**`postUpdateOptions`** — include only for detected ecosystems:
- `gomod` detected → add `"gomodTidy"`
- `npm` detected → add `"npmDedupe"`

**`regexManagers`** — include if `.github/workflows/*.yml` contains `terraform_version:`:
```json
{
  "description": "Update Terraform version in GitHub Actions workflows",
  "fileMatch": ["^\\.github/workflows/.*\\.ya?ml$"],
  "matchStrings": [
    "terraform_version:\\s*['\"]?(?<currentValue>[^'\"\\s]+)['\"]?"
  ],
  "depNameTemplate": "hashicorp/terraform",
  "datasourceTemplate": "github-releases",
  "extractVersionTemplate": "^v(?<version>.*)$"
}
```

### Step 3 — Write or diff

- If `renovate.json` already exists: show only the lines that would change. Ask: `Write to renovate.json? [y/N]`
- If no existing file: write directly and print `✅ renovate.json written.`

---

## Mode: workflow

Emit a ready-to-use `.github/workflows/validate-renovate.yml` that validates `renovate.json` on every PR that modifies it. No secrets or tokens required — uses only `GITHUB_TOKEN`.

### Output file: `.github/workflows/validate-renovate.yml`

```yaml
name: Validate Renovate Config

on:
  pull_request:
    paths:
      - 'renovate.json'

permissions:
  contents: read
  pull-requests: write

jobs:
  validate-schema:
    name: Schema Validation
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2

      - name: Validate JSON syntax
        run: |
          if ! jq empty renovate.json; then
            echo "❌ renovate.json is not valid JSON"
            exit 1
          fi
          echo "✅ JSON syntax valid"

      - name: Validate against Renovate schema
        run: |
          npm install --save-dev ajv-cli ajv-formats
          npx ajv validate \
            --spec=draft7 \
            -s https://docs.renovatebot.com/renovate-schema.json \
            -d renovate.json \
            -c ajv-formats || {
            echo "❌ renovate.json does not match Renovate schema"
            exit 1
          }
          echo "✅ Schema validation passed"

  validate-config:
    name: Config Validator
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2

      - name: Run renovate-config-validator
        run: |
          npx --yes renovate-config-validator renovate.json
          echo "✅ Config validation passed"

  validate-coverage:
    name: Coverage Scan
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2

      - name: Check manager coverage
        run: |
          UNCOVERED=0

          check_coverage() {
            local label="$1"
            local pattern="$2"
            local manager="$3"

            if find . -path "./.git" -prune -o -name "$pattern" -print | grep -q .; then
              if grep -q "\"$manager\"" renovate.json; then
                echo "✅ COVERED: $label ($manager)"
              else
                echo "⚠️  UNCOVERED: $label ($manager) — files found but manager not referenced in renovate.json"
                UNCOVERED=$((UNCOVERED + 1))
              fi
            else
              echo "ℹ️  SKIPPED: $label — no matching files found"
            fi
          }

          check_coverage "GitHub Actions" "*.yml"               "github-actions"
          check_coverage "Terraform"      "*.tf"                "terraform"
          check_coverage "Helm"           "Chart.yaml"          "helmv3"
          check_coverage "Go modules"     "go.mod"              "gomod"
          check_coverage "npm"            "package.json"        "npm"
          check_coverage "Python"         "requirements*.txt"   "pip_requirements"
          check_coverage "Docker"         "Dockerfile"          "dockerfile"
          check_coverage "Rust"           "Cargo.toml"          "cargo"

          if [ $UNCOVERED -gt 0 ]; then
            echo ""
            echo "⚠️  $UNCOVERED ecosystem(s) detected but not covered by Renovate"
            echo "Run /platform-skills:renovate generate to update your renovate.json"
          else
            echo "✅ All detected ecosystems are covered"
          fi

  summary:
    name: Validation Summary
    runs-on: ubuntu-latest
    needs: [validate-schema, validate-config, validate-coverage]
    if: always()
    steps:
      - name: Post summary
        run: |
          cat << 'EOF' >> $GITHUB_STEP_SUMMARY
          ## Renovate Config Validation
          EOF
          printf "| Check | Status |\n|-------|--------|\n" >> $GITHUB_STEP_SUMMARY
          printf "| JSON Schema | %s |\n" "${{ needs.validate-schema.result == 'success' && '✅ Passed' || '❌ Failed' }}" >> $GITHUB_STEP_SUMMARY
          printf "| Config Validator | %s |\n" "${{ needs.validate-config.result == 'success' && '✅ Passed' || '❌ Failed' }}" >> $GITHUB_STEP_SUMMARY
          printf "| Coverage Scan | %s |\n" "${{ needs.validate-coverage.result == 'success' && '✅ Passed' || '⚠️ Warnings' }}" >> $GITHUB_STEP_SUMMARY

      - name: Enforce required checks
        run: |
          if [[ "${{ needs.validate-schema.result }}" != "success" ]] || \
             [[ "${{ needs.validate-config.result }}" != "success" ]]; then
            echo "❌ Required validation checks failed — see jobs above"
            exit 1
          fi
          echo "✅ All required checks passed"
```

After writing: check if `.github/workflows/validate-renovate.yml` already exists — if so, show diff and ask to overwrite. Then print:

```
✅ Workflow written to .github/workflows/validate-renovate.yml

Next steps:
  git add .github/workflows/validate-renovate.yml
  git commit -m "ci: add renovate.json validation workflow"
  git push

The workflow fires automatically on any PR that modifies renovate.json.
```

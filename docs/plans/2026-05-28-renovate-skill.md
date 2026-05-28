# Renovate Skill Implementation Plan — v1.27.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/platform-skills:renovate` with `generate` (emit renovate.json from repo scan), `workflow` (emit GHA validation workflow), `precommit` (interactive semver/automerge wizard), and `all` (run all modes) modes, plus all v1.27.0 release metadata.

**Architecture:** New command file at `commands/renovate.md`, deep-dive reference at `references/renovate.md`, GHA workflow at `.github/workflows/validate-renovate.yml`. Existing `renovate.json` gets patched with missing fields. Version bumped to 1.27.0 across `plugin.json`, `marketplace.json`, `tile.json`, `CHANGELOG.md`, `INSTALLATION.md`.

**Tech Stack:** Markdown skill files, JSON (renovate.json, marketplace.json, plugin.json, tile.json), GitHub Actions YAML, bash (coverage scan script), npx (ajv-cli, renovate-config-validator).

---

## File Map

| Action | File | Responsibility |
|---|---|---|
| Create | `commands/renovate.md` | Slash command — `generate` and `workflow` modes |
| Create | `references/renovate.md` | Manager catalog, presets, security, GitOps integration, troubleshooting |
| Create | `.github/workflows/validate-renovate.yml` | CI: schema + config-validator + coverage on renovate.json PRs |
| Modify | `renovate.json` | Add `osvVulnerabilityAlerts`, `dependencyDashboard`, `minimumReleaseAge`, `gomod`/`npm`/`pip` rules |
| Modify | `SKILL.md` | Add `Renovate` row to tool table + `/platform-skills:renovate` slash command |
| Modify | `COMMANDS.md` | Add TOC row + full `/platform-skills:renovate` section |
| Modify | `marketplace.json` | Version 1.26.0 → 1.27.0; add `renovate` keyword; update description |
| Modify | `.claude-plugin/plugin.json` | Version 1.26.0 → 1.27.0; add `commands/renovate.md` to commands array |
| Modify | `tile.json` | Version 1.25.20 → 1.27.0 |
| Modify | `CHANGELOG.md` | Add [1.27.0] entry |
| Modify | `INSTALLATION.md` | `platform-skills  v1.26.0  enabled` → `platform-skills  v1.27.0  enabled` |

---

## Task 1: Create `commands/renovate.md`

**Files:**
- Create: `commands/renovate.md`

- [ ] **Step 1: Write the command file**

Create `/Users/nitin.jain/platform-skills/commands/renovate.md` with this exact content:

````markdown
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

          | Check | Status |
          |-------|--------|
          EOF
          echo "| JSON Schema | ${{ needs.validate-schema.result == 'success' && '✅ Passed' || '❌ Failed' }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Config Validator | ${{ needs.validate-config.result == 'success' && '✅ Passed' || '❌ Failed' }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Coverage Scan | ${{ needs.validate-coverage.result == 'success' && '✅ Passed' || '⚠️ Warnings' }} |" >> $GITHUB_STEP_SUMMARY

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
````

- [ ] **Step 2: Verify the file exists and JSON blocks are well-formed**

```bash
ls -la /Users/nitin.jain/platform-skills/commands/renovate.md
head -5 /Users/nitin.jain/platform-skills/commands/renovate.md
```

Expected: file exists, first line is `---`

- [ ] **Step 3: Commit**

```bash
git -C /Users/nitin.jain/platform-skills add commands/renovate.md
git -C /Users/nitin.jain/platform-skills commit -m "feat: add /platform-skills:renovate command — generate, workflow, precommit, and all modes"
```

---

## Task 2: Create `references/renovate.md`

**Files:**
- Create: `references/renovate.md`

- [ ] **Step 1: Write the reference file**

Create `/Users/nitin.jain/platform-skills/references/renovate.md` with this exact content:

````markdown
# Renovate Reference

Companion to `/platform-skills:renovate`. Deep-dive on managers, presets, security, GitOps integration, and troubleshooting.

---

## 1. Manager Catalog

| Manager | File patterns | Notes |
|---|---|---|
| `github-actions` | `.github/workflows/*.yml` | Always `pinDigests: true` — commit SHA instead of tag |
| `terraform` | `*.tf`, `*.tfvars` | Covers `required_providers` and `module` blocks |
| `helmv3` | `Chart.yaml`, `requirements.yaml` | Helm 3 chart dependencies |
| `gomod` | `go.mod` | Go module dependencies; use `gomodTidy` in `postUpdateOptions` |
| `npm` | `package.json`, `package-lock.json`, `yarn.lock` | Node packages; use `npmDedupe` in `postUpdateOptions` |
| `pip_requirements` | `requirements*.txt` | Pinned Python packages |
| `pip-compile` | `requirements*.in` | pip-tools input files |
| `pipenv` | `Pipfile`, `Pipfile.lock` | Pipenv-managed projects |
| `poetry` | `pyproject.toml` (Poetry) | Poetry-managed projects |
| `dockerfile` | `Dockerfile`, `Dockerfile.*` | `FROM` image tags |
| `docker-compose` | `docker-compose*.yml` | Service image tags |
| `kubernetes` | Manifests with `kind: Deployment/StatefulSet/DaemonSet/Job/CronJob` | Container image tags in `spec.containers[].image` |
| `cargo` | `Cargo.toml` | Rust crate dependencies |
| `regex` | Any file via `fileMatch` | Custom version strings — no native manager support |

---

## 2. Preset Reference

`config:recommended` includes:

| Preset | Effect |
|---|---|
| `config:recommended` | Base: semantic PR titles, dependency dashboard, labels, schedule |
| `:dependencyDashboard` | Creates a GitHub Issue listing all pending/blocked updates |
| `:semanticCommits` | Commit messages follow Conventional Commits format |
| `:separateMajorReleases` | Major version bumps get their own PR, never grouped |

Useful add-ons:

| Preset | When to add |
|---|---|
| `:pinDigests` | Global digest pinning — prefer scoped to `github-actions` only |
| `:automergeMinor` | Automerge all minor updates — use only if CI is comprehensive |
| `:automergeDigest` | Automerge digest-only updates (no version change) |
| `security:openssf-scorecard` | Adds OpenSSF Scorecard checks to PRs |
| `helpers:pinGitHubActionDigests` | Shorthand for GitHub Actions digest pinning |

---

## 3. Package Rules Patterns

### Automerge strategy by ecosystem

| Ecosystem | Recommended automerge | Reason |
|---|---|---|
| `github-actions` | Never | SHA pinning means every update is significant |
| `terraform` providers | Minor + patch | Providers are stable; breaking changes follow semver |
| `terraform` modules | Never | Module updates may change resource topology |
| `helmv3` | Patch only | Charts may have templating changes in minor |
| `gomod` | Minor + patch | Go semver is well-respected |
| `npm` | Minor + patch | With `minimumReleaseAge: "3 days"` to avoid supply chain risk |
| `pip` | Minor + patch | Same — pin to `minimumReleaseAge` |
| `docker`/`kubernetes` | Never | Image updates may include breaking app changes |
| `cargo` | Minor + patch | Cargo semver is well-respected |

### Grouping recipes

Group related updates into one PR to reduce noise:

```json
{
  "description": "Group all AWS provider updates",
  "matchManagers": ["terraform"],
  "matchPackageNames": ["hashicorp/aws"],
  "groupName": "AWS provider"
},
{
  "description": "Group all patch updates across ecosystems",
  "matchUpdateTypes": ["patch"],
  "matchCurrentVersion": "!/^0/",
  "groupName": "Patch updates",
  "automerge": true,
  "minimumReleaseAge": "3 days"
}
```

### Schedule recipes

```json
"schedule": ["before 6am on monday"]          // Weekly, low disruption
"schedule": ["after 10pm every weekday"]       // Nightly, non-work hours
"schedule": ["at any time"]                    // Immediate (vulnerability alerts)
```

### `minimumReleaseAge` for supply chain safety

Always set on automerge rules to prevent typosquatting and freshly-published malicious packages:

```json
{
  "matchUpdateTypes": ["minor", "patch"],
  "automerge": true,
  "minimumReleaseAge": "3 days"
}
```

---

## 4. Dependency Dashboard

Renovate creates a GitHub Issue titled "Renovate Dependency Dashboard" when `dependencyDashboard: true`.

**What it shows:**
- All pending updates grouped by status (Awaiting Schedule / Open PRs / Rate-limited / Ignored)
- Checkboxes to trigger individual updates on-demand

**How to trigger a selective update:**
1. Open the Dependency Dashboard issue
2. Check the box next to the package you want updated now
3. Save the issue — Renovate detects the change within minutes and creates the PR

**How to find the dashboard:**
```bash
gh issue list --label "renovate" --state open
```

**Resetting the dashboard:**
Close and reopen the issue — Renovate recreates it on the next run.

**Enable explicitly** (already in `config:recommended` but good to be explicit):
```json
{
  "dependencyDashboard": true,
  "dependencyDashboardTitle": "Renovate Dependency Dashboard"
}
```

---

## 5. GitOps Integration

### Renovate vs Flux Image Reflector Controller

Both can update container image references. Running both on the same files causes conflicts.

**Recommended split:**

| Responsibility | Owner |
|---|---|
| Helm chart versions in `HelmRelease` | Renovate (`helmv3` manager) |
| Terraform provider/module versions | Renovate (`terraform` manager) |
| Language dep versions (go.mod, package.json) | Renovate |
| GitHub Actions versions | Renovate (`github-actions` manager) |
| Running workload image tags (Deployment/StatefulSet) | Flux Image Reflector Controller |
| OCI artifact digest pinning in FluxInstance | Flux (`ImagePolicy`) |

**Rule:** Renovate owns anything in source control that follows semver. Flux Image Reflector owns runtime image tags for deployed workloads where you want continuous delivery without a PR.

**Avoiding conflicts:**

If Flux Image Reflector manages `spec.containers[].image` in a manifest, exclude that manifest from Renovate:

```json
{
  "ignorePaths": [
    "clusters/**",
    "flux-system/**"
  ]
}
```

Or scope the `kubernetes` manager to only non-Flux paths:

```json
{
  "matchManagers": ["kubernetes"],
  "matchPaths": ["apps/**", "workloads/**"],
  "automerge": false
}
```

---

## 6. Security Hardening

### Digest pinning for GitHub Actions

```json
{
  "matchManagers": ["github-actions"],
  "pinDigests": true
}
```

This converts `uses: actions/checkout@v4` → `uses: actions/checkout@<sha>  # v4.x.x`, making the action tamper-proof.

### OSV vulnerability alerts

```json
{
  "osvVulnerabilityAlerts": true,
  "vulnerabilityAlerts": {
    "enabled": true,
    "labels": ["security"],
    "schedule": ["at any time"]
  }
}
```

`osvVulnerabilityAlerts` uses the OSV database (broader coverage than GitHub Advisory Database).

### `minimumReleaseAge` — supply chain defence

Prevents automerging packages published less than N days ago, reducing exposure to typosquatting and fast-follow malicious releases:

```json
{
  "matchUpdateTypes": ["minor", "patch"],
  "automerge": true,
  "minimumReleaseAge": "3 days"
}
```

### `rangeStrategy: pin`

Pin exact versions instead of ranges for reproducibility:

```json
{
  "matchManagers": ["npm"],
  "rangeStrategy": "pin"
}
```

Use `"bump"` instead if the project publishes a library (ranges in `peerDependencies` must stay flexible).

### Private registry auth

```json
{
  "hostRules": [
    {
      "matchHost": "ghcr.io",
      "username": "{{ secrets.GHCR_USERNAME }}",
      "password": "{{ secrets.GHCR_TOKEN }}"
    }
  ]
}
```

Store secrets in Renovate's encrypted secrets (Mend Renovate App) or as env vars when self-hosted.

---

## 7. Regex Managers

Use `regexManagers` when no native manager supports the file format.

### Terraform version in GitHub Actions workflows

```json
{
  "description": "Track Terraform CLI version in workflow YAML",
  "fileMatch": ["^\\.github/workflows/.*\\.ya?ml$"],
  "matchStrings": [
    "terraform_version:\\s*['\"]?(?<currentValue>[^'\"\\s]+)['\"]?"
  ],
  "depNameTemplate": "hashicorp/terraform",
  "datasourceTemplate": "github-releases",
  "extractVersionTemplate": "^v(?<version>.*)$"
}
```

### Tool version in shell scripts

```json
{
  "description": "Track kubectl version in install scripts",
  "fileMatch": ["scripts/.*\\.sh$"],
  "matchStrings": [
    "KUBECTL_VERSION=['\"]?(?<currentValue>[^'\"\\s]+)['\"]?"
  ],
  "depNameTemplate": "kubernetes/kubernetes",
  "datasourceTemplate": "github-releases",
  "extractVersionTemplate": "^v(?<version>.*)$"
}
```

### Flux version in documentation

```json
{
  "description": "Track Flux CLI version in docs",
  "fileMatch": ["^docs/.*\\.md$", "^examples/.*\\.md$"],
  "matchStrings": [
    "Flux CLI \\((?<currentValue>[^)]+)\\)"
  ],
  "depNameTemplate": "fluxcd/flux2",
  "datasourceTemplate": "github-releases",
  "extractVersionTemplate": "^v(?<version>.*)$"
}
```

---

## 8. Troubleshooting

### `renovate-config-validator` errors

| Error | Cause | Fix |
|---|---|---|
| `Invalid preset: config:base` | Deprecated preset | Change to `config:recommended` |
| `matchManagers must be array` | Scalar instead of array | `"matchManagers": ["terraform"]` not `"matchManagers": "terraform"` |
| `Unknown option: pinDigest` | Typo — missing `s` | Use `pinDigests` (plural) |
| `extends: invalid` | Preset not found | Check preset name at [docs.renovatebot.com/presets](https://docs.renovatebot.com/presets-config/) |

### Coverage scan false positives

The `/platform-skills:renovate workflow` coverage scan checks for manager name strings in `renovate.json`. False positives occur when:
- A file type is present but intentionally excluded via `ignorePaths`
- A monorepo subdirectory is managed by a separate `renovate.json`

Suppress by adding the path to `ignorePaths` and noting it in the `description` field of the relevant `packageRule`.

### Rate limiting

Renovate enforces `prConcurrentLimit` (open PRs at once) and `prHourlyLimit` (PRs per hour). If updates are being skipped:

```json
{
  "prConcurrentLimit": 10,
  "prHourlyLimit": 0
}
```

Set `prHourlyLimit: 0` to disable hourly cap entirely (use with caution on large repos).

### Dependency Dashboard not appearing

1. Confirm `"dependencyDashboard": true` is in `renovate.json`
2. Check that the Renovate App has Issues write permission on the repo
3. Trigger a manual run via the App settings or by pushing a trivial change
````

- [ ] **Step 2: Verify the file exists**

```bash
ls -la /Users/nitin.jain/platform-skills/references/renovate.md
wc -l /Users/nitin.jain/platform-skills/references/renovate.md
```

Expected: file exists, >150 lines

- [ ] **Step 3: Commit**

```bash
git -C /Users/nitin.jain/platform-skills add references/renovate.md
git -C /Users/nitin.jain/platform-skills commit -m "feat: add references/renovate.md — manager catalog, presets, security, GitOps"
```

---

## Task 3: Create `.github/workflows/validate-renovate.yml`

**Files:**
- Create: `.github/workflows/validate-renovate.yml`

- [ ] **Step 1: Write the workflow file**

Create `/Users/nitin.jain/platform-skills/.github/workflows/validate-renovate.yml`:

```yaml
name: Validate Renovate Config

on:
  pull_request:
    paths:
      - 'renovate.json'

permissions:
  contents: read

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

          check_coverage "GitHub Actions" "*.yml"             "github-actions"
          check_coverage "Terraform"      "*.tf"              "terraform"
          check_coverage "Helm"           "Chart.yaml"        "helmv3"
          check_coverage "Go modules"     "go.mod"            "gomod"
          check_coverage "npm"            "package.json"      "npm"
          check_coverage "Python"         "requirements*.txt" "pip_requirements"
          check_coverage "Docker"         "Dockerfile"        "dockerfile"
          check_coverage "Rust"           "Cargo.toml"        "cargo"

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

- [ ] **Step 2: Validate YAML syntax**

```bash
python3 -c "import yaml, sys; yaml.safe_load(open('.github/workflows/validate-renovate.yml'))" \
  2>&1 && echo "✅ YAML valid" || echo "❌ YAML invalid"
```

Run from `/Users/nitin.jain/platform-skills`. Expected: `✅ YAML valid`

- [ ] **Step 3: Commit**

```bash
git -C /Users/nitin.jain/platform-skills add .github/workflows/validate-renovate.yml
git -C /Users/nitin.jain/platform-skills commit -m "ci: add validate-renovate workflow — schema, config-validator, coverage scan"
```

---

## Task 4: Patch `renovate.json`

**Files:**
- Modify: `renovate.json`

- [ ] **Step 1: Add missing fields to renovate.json**

The existing `renovate.json` already has GitHub Actions, Terraform, and Helm rules. Add:

1. `dependencyDashboard` and `osvVulnerabilityAlerts` after the `"semanticCommits"` line
2. `minimumReleaseAge: "3 days"` to the Terraform providers and Helm patch automerge rules
3. New `packageRules` blocks for `gomod`, `npm`, and `pip`
4. `"npmDedupe"` to `postUpdateOptions`

After `"semanticCommits": "enabled",` add:
```json
"dependencyDashboard": true,
"dependencyDashboardTitle": "Renovate Dependency Dashboard",
"osvVulnerabilityAlerts": true,
```

In the Terraform providers rule, add after `"automergeType": "pr",`:
```json
"minimumReleaseAge": "3 days",
```

In the Helm patch rule, add after `"automergeType": "pr",`:
```json
"minimumReleaseAge": "3 days",
```

In the stable patch automerge rule at the bottom, add:
```json
"minimumReleaseAge": "3 days",
```

Add new packageRules entries (before the closing `]` of `packageRules`):
```json
{
  "description": "Go modules — automerge minor/patch",
  "matchManagers": ["gomod"],
  "automerge": true,
  "automergeType": "pr",
  "minimumReleaseAge": "3 days",
  "matchUpdateTypes": ["minor", "patch"],
  "groupName": "Go modules"
},
{
  "description": "npm packages — automerge minor/patch",
  "matchManagers": ["npm"],
  "automerge": true,
  "automergeType": "pr",
  "minimumReleaseAge": "3 days",
  "matchUpdateTypes": ["minor", "patch"],
  "groupName": "npm packages"
},
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

Change `"postUpdateOptions": ["gomodTidy"]` to:
```json
"postUpdateOptions": ["gomodTidy", "npmDedupe"]
```

- [ ] **Step 2: Validate the updated renovate.json**

```bash
jq empty /Users/nitin.jain/platform-skills/renovate.json && echo "✅ JSON valid" || echo "❌ JSON invalid"
```

Expected: `✅ JSON valid`

- [ ] **Step 3: Commit**

```bash
git -C /Users/nitin.jain/platform-skills add renovate.json
git -C /Users/nitin.jain/platform-skills commit -m "chore: update renovate.json — add gomod/npm/pip rules, minimumReleaseAge, osvVulnerabilityAlerts"
```

---

## Task 5: Update `SKILL.md` and `COMMANDS.md`

**Files:**
- Modify: `SKILL.md`
- Modify: `COMMANDS.md`

- [ ] **Step 1: Add Renovate row to SKILL.md tool table**

In `SKILL.md`, add this row after the `Platform Mindset` row (line 43):

```markdown
| `Renovate` | Dependency update automation — generate renovate.json from repo scan, emit GHA validation workflow |
```

Also add `/platform-skills:renovate` to the slash commands list in SKILL.md. Find the block listing slash commands and add:

```markdown
- `/platform-skills:renovate` — generate renovate.json for any repo, or emit a GHA workflow to validate it on PR
```

- [ ] **Step 2: Add Renovate entry to COMMANDS.md TOC**

In `COMMANDS.md`, add this row to the Table of Contents after the `fluxcd` row:

```markdown
| [/platform-skills:renovate](#platform-skillsrenovate) | Generate renovate.json from repo scan or emit a GHA validation workflow |
```

- [ ] **Step 3: Add full Renovate section to COMMANDS.md**

Append this section at the end of `COMMANDS.md` (after the `/platform-skills:fluxcd` section):

````markdown
---

## `/platform-skills:renovate`

**What it does:** Scans your repo for dependency file types and emits a correct `renovate.json` covering only the ecosystems you use, or generates a GitHub Actions workflow that validates `renovate.json` on every PR that touches it.

**Works on:** Any repo using GitHub Actions, Terraform, Helm, Go, Node, Python, Docker, Rust, Kubernetes manifests, or any combination.

```
/platform-skills:renovate [generate|workflow]
```

**Modes:**

| Mode | What it does |
|------|-------------|
| `generate` | Scans repo → detects dep file types → emits renovate.json with per-ecosystem packageRules |
| `workflow` | Emits `.github/workflows/validate-renovate.yml` — schema + config-validator + coverage scan on PR |

**Examples:**

```
/platform-skills:renovate generate
/platform-skills:renovate workflow
/platform-skills:renovate
```

**Reference:** `references/renovate.md`
````

- [ ] **Step 4: Verify SKILL.md and COMMANDS.md are valid markdown**

```bash
grep "Renovate" /Users/nitin.jain/platform-skills/SKILL.md
grep "renovate" /Users/nitin.jain/platform-skills/COMMANDS.md | head -5
```

Expected: at least one match in each file

- [ ] **Step 5: Commit**

```bash
git -C /Users/nitin.jain/platform-skills add SKILL.md COMMANDS.md
git -C /Users/nitin.jain/platform-skills commit -m "feat: add Renovate to SKILL.md tool table and COMMANDS.md"
```

---

## Task 6: Bump versions and release metadata

**Files:**
- Modify: `.claude-plugin/marketplace.json`
- Modify: `.claude-plugin/plugin.json`
- Modify: `tile.json`
- Modify: `CHANGELOG.md`
- Modify: `INSTALLATION.md`

- [ ] **Step 1: Bump marketplace.json**

In `.claude-plugin/marketplace.json`:
- Change `"version": "1.26.0"` → `"version": "1.27.0"` (in `plugins[0]`)
- Add `"renovate"` to the `keywords` array
- Update description to include "Renovate dependency automation"

- [ ] **Step 2: Bump plugin.json**

In `.claude-plugin/plugin.json`:
- Change `"version": "1.26.0"` → `"version": "1.27.0"`
- Add `"./commands/renovate.md"` to the `commands` array (after `"./commands/aws-profile.md"`)

- [ ] **Step 3: Bump tile.json**

In `tile.json`:
- Change `"version": "1.25.20"` → `"version": "1.27.0"`

- [ ] **Step 4: Add CHANGELOG entry**

In `CHANGELOG.md`, add this block immediately after the first `---` separator (before `## [1.26.0]`):

```markdown
## [1.27.0] - 2026-05-28

### Added

- `commands/renovate.md`: new `/platform-skills:renovate` command with two modes — `generate` (scan repo for dep file types, emit renovate.json covering only detected ecosystems with per-manager automerge/schedule/grouping rules) and `workflow` (emit `.github/workflows/validate-renovate.yml` for schema + config-validator + coverage validation on PRs).
- `references/renovate.md`: 8-section reference — manager catalog, preset reference, package rules patterns, dependency dashboard, GitOps integration (Renovate vs Flux Image Reflector ownership boundary), security hardening (pinDigests, osvVulnerabilityAlerts, minimumReleaseAge), regex manager templates, troubleshooting.
- `.github/workflows/validate-renovate.yml`: CI workflow triggering on PRs that touch `renovate.json` — three parallel jobs (schema via ajv, config-validator via npx, coverage bash scan) with `GITHUB_STEP_SUMMARY` result table. No secrets required.
- `renovate.json`: added `dependencyDashboard`, `osvVulnerabilityAlerts`, `minimumReleaseAge: "3 days"` on automerge rules, packageRules for `gomod`/`npm`/`pip`, `npmDedupe` postUpdateOption.
- `SKILL.md`: `Renovate` row in tool table; `/platform-skills:renovate` slash command entry.
- `COMMANDS.md`: TOC entry and full `/platform-skills:renovate` command section (31 commands total).

### Contributors

- [@geetika-sv](https://github.com/geetika-sv) — Renovate skill

```

- [ ] **Step 5: Bump INSTALLATION.md**

In `INSTALLATION.md` line 63, change:
```
# platform-skills  v1.26.0  enabled
```
to:
```
# platform-skills  v1.27.0  enabled
```

- [ ] **Step 6: Validate all JSON files**

```bash
jq empty /Users/nitin.jain/platform-skills/.claude-plugin/marketplace.json && echo "marketplace.json ✅"
jq empty /Users/nitin.jain/platform-skills/.claude-plugin/plugin.json && echo "plugin.json ✅"
jq empty /Users/nitin.jain/platform-skills/tile.json && echo "tile.json ✅"
```

Expected: all three print `✅`

- [ ] **Step 7: Commit**

```bash
git -C /Users/nitin.jain/platform-skills add \
  .claude-plugin/marketplace.json \
  .claude-plugin/plugin.json \
  tile.json \
  CHANGELOG.md \
  INSTALLATION.md
git -C /Users/nitin.jain/platform-skills commit -m "chore: release v1.27.0 — renovate skill"
```

---

## Task 7: Run consistency tests

**Files:** read-only validation

- [ ] **Step 1: Run handbook consistency checks**

```bash
cd /Users/nitin.jain/platform-skills && bash tests/handbook-consistency.sh
```

Expected output ends with: `✅ Handbook consistency checks passed`

The script verifies:
- `SKILL.md` name matches `marketplace.json` name and `plugin.json` name
- `plugin.json` version = `marketplace.json` version = latest CHANGELOG version (all must be `1.27.0`)
- `INSTALLATION.md` contains `platform-skills  v1.27.0  enabled`
- All required handbook paths exist
- All `examples/*/README.md` files have a `Status:` label

- [ ] **Step 2: Validate YAML of the new workflow**

```bash
python3 -c "
import yaml, sys
with open('/Users/nitin.jain/platform-skills/.github/workflows/validate-renovate.yml') as f:
    yaml.safe_load(f)
print('✅ validate-renovate.yml YAML valid')
"
```

Expected: `✅ validate-renovate.yml YAML valid`

- [ ] **Step 3: Verify commands/renovate.md is registered in plugin.json**

```bash
jq '.commands | map(select(contains("renovate")))' \
  /Users/nitin.jain/platform-skills/.claude-plugin/plugin.json
```

Expected: `["./commands/renovate.md"]`

- [ ] **Step 4: Smoke-check version consistency**

```bash
PLUGIN_VER=$(jq -r '.version' /Users/nitin.jain/platform-skills/.claude-plugin/plugin.json)
MARKET_VER=$(jq -r '.plugins[0].version' /Users/nitin.jain/platform-skills/.claude-plugin/marketplace.json)
CHANGE_VER=$(awk '$1=="##" && $2~/^\[[0-9]+\.[0-9]+\.[0-9]+\]$/{gsub(/[][]/,"",$2);print $2;exit}' \
  /Users/nitin.jain/platform-skills/CHANGELOG.md)
echo "plugin.json:     $PLUGIN_VER"
echo "marketplace.json: $MARKET_VER"
echo "CHANGELOG.md:    $CHANGE_VER"
[[ "$PLUGIN_VER" == "1.27.0" && "$MARKET_VER" == "1.27.0" && "$CHANGE_VER" == "1.27.0" ]] \
  && echo "✅ All versions consistent" || echo "❌ Version mismatch"
```

Expected: `✅ All versions consistent`

- [ ] **Step 5: Final commit if any fixes were needed**

If the consistency tests required edits, commit them:

```bash
git -C /Users/nitin.jain/platform-skills add -u
git -C /Users/nitin.jain/platform-skills commit -m "fix: address handbook consistency check failures"
```

If no fixes were needed, skip this step.

---

## Self-Review Checklist

- [x] **Spec coverage:** All spec sections covered — `commands/renovate.md` (Tasks 1), `references/renovate.md` (Task 2), GHA workflow (Task 3), `renovate.json` patch (Task 4), `SKILL.md`/`COMMANDS.md` (Task 5), version bumps (Task 6), consistency tests (Task 7)
- [x] **No placeholders:** All tasks contain exact file content, exact commands, expected outputs
- [x] **Type consistency:** No function/method names across tasks (skill files not code)
- [x] **Commit SHA:** `actions/checkout` uses `de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2` matching existing repo policy
- [x] **No RENOVATE_TOKEN:** Workflow uses only `GITHUB_TOKEN` — no secrets
- [x] **Version 1.27.0:** All three version files updated consistently; CHANGELOG entry dated 2026-05-28

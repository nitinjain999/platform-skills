---
name: renovate
description: Generate renovate.json covering all dependency file types used in a repo, emit a GitHub Actions workflow that validates renovate.json on every PR, or generate a pre-commit hook for local validation.
argument-hint: "[generate|workflow|precommit|all]"
---

## Interactive Wizard (fires when $ARGUMENTS is empty)

When invoked with no arguments, ask these questions before proceeding. Ask each question individually and wait for the answer before asking the next.

**Q1 — Mode?**
```
What do you need?
  1. generate   — scan this repo and create renovate.json covering all detected dep file types
  2. workflow   — generate a GitHub Actions workflow that validates renovate.json on every PR
  3. precommit  — generate a .pre-commit-config.yaml hook that validates renovate.json locally
  4. all        — generate renovate.json + pre-commit hook + GitHub Actions workflow in one pass

Enter 1–4 or mode name:
```

**Q2 — Pinning strategy?** (ask only for modes that emit renovate.json: `generate`, `all`)
```
How should Renovate pin dependency versions?

  1. digest   — pin GitHub Actions and container images to commit SHA; semver for packages
                (maximum supply chain security — recommended)
  2. semver   — pin to semver tags/versions for all ecosystems; no SHA digests
                (simpler PRs, easier to read at a glance)

Enter 1–2:
```

**Q3 — Automerge scope?** (ask only for modes that emit renovate.json: `generate`, `all`)
```
Which update types should Renovate automerge without requiring a review?

  1. patch-only   — automerge patch updates only (1.2.3 → 1.2.4) — safest
  2. minor-patch  — automerge minor and patch (1.2.x → 1.3.x) — recommended for most teams
  3. none         — require human review for every update

Enter 1–3:
```

**Q4 — Update schedule?** (ask only for modes that emit renovate.json: `generate`, `all`)
```
When should Renovate open PRs?

  1. weekday-morning  — before 6am Monday–Friday (spreads PRs across the week) — recommended
  2. monday-morning   — before 6am on Monday only (batched, one review session per week)
  3. weekend          — before 6am Saturday–Sunday (keeps weekdays clear)
  4. always           — no schedule restriction (Renovate runs whenever it detects changes)

Enter 1–4:
```

**Q5 — Internal Terraform module source?** (ask only for modes that emit renovate.json, and only if `terraform` manager was or may be detected)
```
Do you reference Terraform modules from private GitHub repos or a private registry?

  1. github-org      — source = "github.com/<org>/<repo>//<path>?ref=<tag>"
  2. private-registry — source = "<hostname>/<namespace>/<module>/<provider>"
  3. no              — only public registry.terraform.io modules

Enter 1–3 (or press Enter to skip):
```
If `github-org`: What is your GitHub org? (e.g., `myorg`)
If `private-registry`: What is the registry hostname? (e.g., `app.terraform.io`)

**Q6 — Private Helm registry?** (ask only for modes that emit renovate.json, and only if `helmv3` manager was or may be detected)
```
Do you use a private Helm chart registry?

  1. oci   — oci://registry.example.com (OCI-based, e.g. ECR, GHCR, Harbor)
  2. http  — https://charts.example.com (classic HTTP repository)
  3. no    — only public charts (Artifact Hub, Bitnami, etc.)

Enter 1–3 (or press Enter to skip):
```
If `oci` or `http`: Registry URL? (e.g., `registry.example.com`)

**Q7 — Private container image registry?** (ask only for modes that emit renovate.json, and only if `docker`, `dockerfile`, `kubernetes`, or `docker-compose` manager was or may be detected)
```
Do you use a private container image registry?

  1. ecr     — AWS ECR (123456789012.dkr.ecr.<region>.amazonaws.com)
  2. gcr     — Google GCR or Artifact Registry (gcr.io / <region>-docker.pkg.dev)
  3. acr     — Azure ACR (myregistry.azurecr.io)
  4. harbor  — Harbor or other self-hosted registry (registry.example.com)
  5. no      — Docker Hub and public registries only

Enter 1–5 (comma-separate multiple, or press Enter to skip):
```
If private: Registry hostname for each selected type? (e.g., `123456789012.dkr.ecr.us-east-1.amazonaws.com`)

Store all answers and proceed into the relevant mode(s) below using them.

---

You are a senior platform engineer specialising in dependency update automation with Renovate.

The input is: $ARGUMENTS

Parse the first word as the mode:
- `generate`  — scan this repo and emit renovate.json
- `workflow`  — emit a GitHub Actions validation workflow
- `precommit` — emit a pre-commit hook config
- `all`       — run generate, then precommit, then workflow in sequence

If the mode was supplied via $ARGUMENTS (not the wizard), still ask Q2–Q7 for any mode that emits renovate.json before proceeding.

---

## Mode: generate

Reference: `references/renovate.md`

Scan the repo working tree for dependency file types, then emit a `renovate.json` that covers exactly those managers — no more, no less.

### Step 1 — Detect ecosystems

Scan for files matching these patterns. Exclude `.git/`, `node_modules/`, `vendor/`, `.terraform/`, `charts/`.

| File pattern | Manager | Key rule |
|---|---|---|
| `.github/workflows/*.yml` | `github-actions` | SHA digest pinning |
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

### Step 1.5 — Scan for internal source patterns

If `terraform` files were detected, grep them for non-public module sources and report findings:

```bash
# Internal GitHub module sources
grep -rh 'source\s*=' **/*.tf | grep 'github\.com/' | sort -u

# Private registry sources (not registry.terraform.io)
grep -rh 'source\s*=' **/*.tf | grep -v 'registry\.terraform\.io' | grep -v 'github\.com/' | grep -v '\.\/' | sort -u
```

Print:
```
Internal source patterns detected:
✅ github.com/myorg/terraform-aws-vpc//modules/vpc?ref=v2.1.0  → will add regex manager
ℹ️  registry.terraform.io/hashicorp/aws  → standard registry, no regex needed
⚠️  ./modules/networking  → local path, skipped
```

If private sources are found but Q5 was not yet answered, ask it now.

---

### Step 2 — Emit renovate.json

Generate a `renovate.json` containing only the managers detected in Step 1.

**`extends` — choose based on Q2 (pinning strategy):**

- `digest` pinning chosen → use `config:best-practices` (includes GitHub Actions + Docker digest pinning, malware age window, abandoned package alerts)
- `semver` pinning chosen → use `config:recommended` + `":separateMajorReleases"`

**`schedule` — set based on Q4:**
- `weekday-morning` → `["before 6am on weekdays"]`
- `monday-morning`  → `["before 6am on monday"]`
- `weekend`         → `["before 6am on saturday and sunday"]`
- `always`          → omit the `schedule` key entirely

**Always include this base:**

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "<see extends rule above>",
    ":dependencyDashboard",
    ":semanticCommits",
    ":separateMajorReleases"
  ],
  "dependencyDashboard": true,
  "dependencyDashboardTitle": "Renovate Dependency Dashboard",
  "timezone": "<ask the user for their timezone, or detect from TZ env var / timedatectl>",
  "labels": ["dependencies", "renovate"],
  "prConcurrentLimit": 5,
  "prCreation": "not-pending",
  "rebaseWhen": "conflicted",
  "semanticCommits": "enabled",
  "minimumReleaseAge": "3 days",
  "osvVulnerabilityAlerts": true,
  "vulnerabilityAlerts": {
    "enabled": true,
    "labels": ["security"]
  },
  "ignorePaths": [
    "**/node_modules/**",
    "**/vendor/**",
    "**/.terraform/**",
    "**/charts/**"
  ]
}
```

**Per-detected-manager `packageRules` (include only detected managers):**

Apply automerge settings based on Q3:
- `patch-only`  → set `"matchUpdateTypes": ["patch"]` for automerge rules
- `minor-patch` → set `"matchUpdateTypes": ["minor", "patch"]` for automerge rules
- `none`        → set `"automerge": false` on all rules; omit `matchUpdateTypes` automerge entries

Apply `pinDigests` based on Q2:
- `digest` → add `"pinDigests": true` to `github-actions` and `docker`/`kubernetes` rules
- `semver` → omit `pinDigests`

`github-actions`:
```json
{
  "description": "GitHub Actions — pin to commit SHA for supply chain security",
  "matchManagers": ["github-actions"],
  "pinDigests": true,
  "automerge": false,
  "groupName": "GitHub Actions"
}
```
(remove `pinDigests` line if semver strategy chosen)

`terraform`:

> **WARNING — Terraform modules must never be automerged.** Module source updates change infrastructure blueprints and require human review. Add this rule to always override other automerge settings:
> ```json
> {
>   "packageRules": [
>     {
>       "matchManagers": ["terraform"],
>       "matchDepTypes": ["module"],
>       "automerge": false,
>       "labels": ["terraform-module", "requires-review"]
>     }
>   ]
> }
> ```
> Place this rule **last** in your `packageRules` array — later rules take precedence in Renovate.

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
  "description": "Terraform modules — require review for all updates",
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
  "description": "Container images — pin digests, require review for all updates",
  "matchManagers": ["docker-compose", "dockerfile"],
  "pinDigests": true,
  "automerge": false,
  "groupName": "Container images"
}
```
(remove `pinDigests` line if semver strategy chosen)

`kubernetes`:
```json
{
  "description": "Kubernetes container images — require review for all updates",
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
  "description": "Update Terraform version pinned in GitHub Actions workflows",
  "fileMatch": ["^\\.github/workflows/.*\\.ya?ml$"],
  "matchStrings": [
    "terraform_version:\\s*['\"]?(?<currentValue>[^'\"\\s]+)['\"]?"
  ],
  "depNameTemplate": "hashicorp/terraform",
  "datasourceTemplate": "github-releases",
  "extractVersionTemplate": "^v(?<version>.*)$"
}
```

### Step 2.5 — Private registries and custom regex managers

Emit the following sections only for the options chosen in Q5–Q7. Omit any section for which the user answered "no" or skipped.

---

#### Q5 — Internal Terraform module sources

**Option A — GitHub org (`github-org`, org = `<org>`):**

Add to `regexManagers`:
```json
{
  "description": "Terraform modules sourced from internal GitHub org <org>",
  "fileMatch": ["\\.tf$"],
  "matchStrings": [
    "source\\s*=\\s*\"github\\.com/<org>/(?<depName>[^/]+)//[^\"]*\\?ref=(?<currentValue>[^\"]+)\""
  ],
  "datasourceTemplate": "github-tags",
  "packageNameTemplate": "<org>/{{{depName}}}"
}
```

Add to `packageRules`:
```json
{
  "description": "Terraform modules from <org> GitHub org — require manual review",
  "matchManagers": ["regex"],
  "matchPackagePatterns": ["^<org>/"],
  "automerge": false,
  "groupName": "Internal Terraform modules (<org>)"
}
```

**Option B — Private Terraform registry (`private-registry`, host = `<hostname>`):**

Add to `regexManagers`:
```json
{
  "description": "Terraform modules from private registry <hostname>",
  "fileMatch": ["\\.tf$"],
  "matchStrings": [
    "source\\s*=\\s*\"<hostname>/(?<namespace>[^/]+)/(?<depName>[^/]+)/(?<provider>[^\"]+)\""
  ],
  "datasourceTemplate": "terraform-module",
  "registryUrlTemplate": "https://<hostname>"
}
```

Add to `hostRules`:
```json
{
  "matchHost": "<hostname>",
  "token": "{{ env.TF_REGISTRY_TOKEN }}"
}
```

> Set `TF_REGISTRY_TOKEN` in your Renovate bot's environment (GitHub Actions secret or Renovate App config).

---

#### Q6 — Private Helm registry

**OCI registry (`oci`, host = `<host>`):**

Add to `hostRules`:
```json
{
  "matchHost": "<host>",
  "hostType": "docker",
  "username": "{{ env.HELM_REGISTRY_USERNAME }}",
  "password": "{{ env.HELM_REGISTRY_PASSWORD }}"
}
```

Add to `packageRules`:
```json
{
  "description": "Helm charts from private OCI registry oci://<host>",
  "matchManagers": ["helmv3"],
  "registryUrls": ["oci://<host>"],
  "automerge": false,
  "groupName": "Private Helm charts (<host>)"
}
```

**HTTP registry (`http`, host = `<host>`):**

Add to `hostRules`:
```json
{
  "matchHost": "<host>",
  "username": "{{ env.HELM_REGISTRY_USERNAME }}",
  "password": "{{ env.HELM_REGISTRY_PASSWORD }}"
}
```

Add to `packageRules`:
```json
{
  "description": "Helm charts from private HTTP registry https://<host>",
  "matchManagers": ["helmv3"],
  "registryUrls": ["https://<host>"],
  "automerge": false,
  "groupName": "Private Helm charts (<host>)"
}
```

> Set `HELM_REGISTRY_USERNAME` and `HELM_REGISTRY_PASSWORD` in your Renovate bot's environment.

---

#### Q7 — Private container image registry

For each registry type selected, add the corresponding `hostRules` entry. Collect all entries into a single `"hostRules": [...]` array in the final `renovate.json`.

**AWS ECR (`ecr`, host = `<account>.dkr.ecr.<region>.amazonaws.com`):**
```json
{
  "matchHost": "<account>.dkr.ecr.<region>.amazonaws.com",
  "hostType": "docker",
  "username": "AWS",
  "password": "{{ env.AWS_ECR_TOKEN }}"
}
```
> Recommended: use the Renovate App with an IAM role instead of a static token. For self-hosted Renovate, pre-authenticate with `aws ecr get-login-password` and expose as `AWS_ECR_TOKEN`.

**Google GCR / Artifact Registry (`gcr`, host = `gcr.io` or `<region>-docker.pkg.dev`):**
```json
{
  "matchHost": "gcr.io",
  "hostType": "docker",
  "username": "_json_key",
  "password": "{{ env.GCR_SERVICE_ACCOUNT_KEY }}"
}
```
For Artifact Registry replace `gcr.io` with `<region>-docker.pkg.dev`.

**Azure ACR (`acr`, host = `<registry>.azurecr.io`):**
```json
{
  "matchHost": "<registry>.azurecr.io",
  "hostType": "docker",
  "username": "{{ env.ACR_CLIENT_ID }}",
  "password": "{{ env.ACR_CLIENT_SECRET }}"
}
```
> Recommended: use a service principal with `AcrPull` role. Set `ACR_CLIENT_ID` and `ACR_CLIENT_SECRET` in Renovate's environment.

**Harbor / self-hosted (`harbor`, host = `<registry-host>`):**
```json
{
  "matchHost": "<registry-host>",
  "hostType": "docker",
  "username": "{{ env.REGISTRY_USERNAME }}",
  "password": "{{ env.REGISTRY_PASSWORD }}"
}
```

After collecting all private registry `hostRules`, also add a `packageRules` entry to group image updates per registry:
```json
{
  "description": "Container images from private registry <registry-host>",
  "matchManagers": ["dockerfile", "docker-compose", "kubernetes"],
  "matchPackagePatterns": ["^<registry-host>/"],
  "automerge": false,
  "groupName": "Private images (<registry-host>)"
}
```

---

#### Assembly

Collect all objects from Steps 2 and 2.5 into the final `renovate.json` following this structure:

```json
{
  "$schema": "...",
  "extends": [...],
  ... base config keys ...,
  "hostRules": [ ... one entry per private registry ... ],
  "regexManagers": [ ... one entry per custom source pattern ... ],
  "packageRules": [ ... all per-manager + private registry rules ... ]
}
```

Omit `hostRules` if no private registries were configured. Omit `regexManagers` if no custom source patterns apply.

Collect all per-detected-manager objects into a single `"packageRules": [...]` array in the final `renovate.json`. Do not emit them as separate JSON blocks.

### Step 3 — Write or diff

- If `renovate.json` already exists: show only the lines that would change. Ask: `Write to renovate.json? [y/N]`
- If no existing file: write directly and print `✅ renovate.json written.`

After writing, print:
```
Next: run /platform-skills:renovate precommit to add a local pre-commit validation hook.
```

---

## Mode: precommit

Reference: `references/renovate.md`

Emit a `.pre-commit-config.yaml` entry that validates `renovate.json` locally before every commit using the official `renovatebot/pre-commit-hooks`.

### Output

If `.pre-commit-config.yaml` already exists, append the renovate repo block if not already present. If the file does not exist, create it.

```yaml
repos:
  - repo: https://github.com/renovatebot/pre-commit-hooks
    rev: 43.150.0
    hooks:
      - id: renovate-config-validator
```

**Semver note:** `rev` tracks the Renovate release version (currently `43.150.0`). Renovate itself will keep this pinned version up to date automatically once Renovate is running on the repo — it treats pre-commit hook revs as a managed dependency.

After writing, print:
```
✅ .pre-commit-config.yaml written (or updated).

To activate the hook:
  pip install pre-commit        # or: brew install pre-commit
  pre-commit install
  pre-commit run renovate-config-validator --all-files

The hook runs renovate-config-validator before every commit that touches renovate.json.
```

---

## Mode: workflow

Reference: `references/renovate.md`

Emit a ready-to-use `.github/workflows/validate-renovate.yml` that validates `renovate.json` on every PR that modifies it. Uses only `GITHUB_TOKEN` — no secrets or tokens required.

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

  validate-config:
    name: Config Validator
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2

      - name: Setup Node
        uses: actions/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e  # v6.4.0
        with:
          node-version: '24'

      - name: Run renovate-config-validator
        run: |
          npx --package=renovate --yes renovate-config-validator renovate.json
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

          if find .github/workflows -name "*.yml" 2>/dev/null | grep -q .; then
            if grep -q '"github-actions"' renovate.json; then
              echo "✅ COVERED: GitHub Actions (github-actions)"
            else
              echo "⚠️  UNCOVERED: GitHub Actions (github-actions) — files found but manager not referenced in renovate.json"
              UNCOVERED=$((UNCOVERED + 1))
            fi
          else
            echo "ℹ️  SKIPPED: GitHub Actions — no matching files found"
          fi

          check_coverage "Terraform"  "*.tf"               "terraform"
          check_coverage "Helm"       "Chart.yaml"         "helmv3"
          check_coverage "Go modules" "go.mod"             "gomod"
          check_coverage "npm"        "package.json"       "npm"
          check_coverage "Python"     "requirements*.txt"  "pip_requirements"
          check_coverage "Docker"     "Dockerfile"         "dockerfile"
          check_coverage "Rust"       "Cargo.toml"         "cargo"

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
          printf "| JSON Syntax | %s |\n" "${{ needs.validate-schema.result == 'success' && '✅ Passed' || '❌ Failed' }}" >> $GITHUB_STEP_SUMMARY
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

---

## Mode: all

Run the three modes in sequence using the answers from the wizard:

1. **generate** — scan repo, ask Q2–Q4, emit `renovate.json`
2. **precommit** — emit or update `.pre-commit-config.yaml`
3. **workflow** — emit `.github/workflows/validate-renovate.yml`

After all three complete, print a single consolidated next-steps block:

```
✅ Renovate setup complete

Files written:
  renovate.json
  .pre-commit-config.yaml
  .github/workflows/validate-renovate.yml

Activate the pre-commit hook:
  pip install pre-commit && pre-commit install

Commit everything:
  git add renovate.json .pre-commit-config.yaml .github/workflows/validate-renovate.yml
  git commit -m "feat: add Renovate dependency automation"
  git push
```

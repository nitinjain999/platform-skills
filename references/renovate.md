# Renovate Reference

Companion to `/platform-skills:renovate`. Deep-dive on managers, presets, security, GitOps integration, private registries, custom regex managers, pre-commit hooks, and troubleshooting.

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

Weekly, low disruption:
```json
{ "schedule": ["before 6am on monday"] }
```

Nightly, non-work hours:
```json
{ "schedule": ["after 10pm every weekday"] }
```

Immediate (vulnerability alerts):
```json
{ "schedule": ["at any time"] }
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

---

## 9. Private Registries

Renovate uses `hostRules` to authenticate with private registries. Credentials are injected at runtime via env-var templating — they never appear in `renovate.json` in plaintext.

### AWS ECR

```json
{
  "hostRules": [
    {
      "matchHost": "123456789012.dkr.ecr.us-east-1.amazonaws.com",
      "hostType": "docker",
      "username": "AWS",
      "password": "{{ env.AWS_ECR_TOKEN }}"
    }
  ]
}
```

Pre-authenticate on self-hosted Renovate:
```bash
export AWS_ECR_TOKEN=$(aws ecr get-login-password --region us-east-1)
```

**Recommended for Renovate App:** attach an IAM role to the Renovate App installation and use the built-in ECR credential helper — no static token needed.

### Google GCR / Artifact Registry

```json
{
  "hostRules": [
    {
      "matchHost": "gcr.io",
      "hostType": "docker",
      "username": "_json_key",
      "password": "{{ env.GCR_SERVICE_ACCOUNT_KEY }}"
    }
  ]
}
```

For Artifact Registry replace `gcr.io` with `<region>-docker.pkg.dev`.

### Azure ACR

```json
{
  "hostRules": [
    {
      "matchHost": "myregistry.azurecr.io",
      "hostType": "docker",
      "username": "{{ env.ACR_CLIENT_ID }}",
      "password": "{{ env.ACR_CLIENT_SECRET }}"
    }
  ]
}
```

Use a service principal with the `AcrPull` role. Set `ACR_CLIENT_ID` and `ACR_CLIENT_SECRET` in the Renovate App environment or self-hosted runner secrets.

### Harbor / self-hosted

```json
{
  "hostRules": [
    {
      "matchHost": "registry.example.com",
      "hostType": "docker",
      "username": "{{ env.REGISTRY_USERNAME }}",
      "password": "{{ env.REGISTRY_PASSWORD }}"
    }
  ]
}
```

### Private Helm — OCI registry

```json
{
  "hostRules": [
    {
      "matchHost": "registry.example.com",
      "hostType": "docker",
      "username": "{{ env.HELM_REGISTRY_USERNAME }}",
      "password": "{{ env.HELM_REGISTRY_PASSWORD }}"
    }
  ],
  "packageRules": [
    {
      "matchManagers": ["helmv3"],
      "registryUrls": ["oci://registry.example.com"],
      "groupName": "Private Helm charts (OCI)"
    }
  ]
}
```

### Private Helm — HTTP registry

```json
{
  "hostRules": [
    {
      "matchHost": "charts.example.com",
      "username": "{{ env.HELM_REGISTRY_USERNAME }}",
      "password": "{{ env.HELM_REGISTRY_PASSWORD }}"
    }
  ],
  "packageRules": [
    {
      "matchManagers": ["helmv3"],
      "registryUrls": ["https://charts.example.com"],
      "groupName": "Private Helm charts (HTTP)"
    }
  ]
}
```

### Private Terraform registry

```json
{
  "hostRules": [
    {
      "matchHost": "app.terraform.io",
      "token": "{{ env.TF_REGISTRY_TOKEN }}"
    }
  ]
}
```

Set `TF_REGISTRY_TOKEN` to a Terraform Cloud team token with read access.

---

## 10. Custom Regex Managers

Use `regexManagers` when a dependency version appears in a file format that Renovate's built-in managers do not parse — internal GitHub module sources, pinned tool versions in scripts, or version strings in YAML/JSON config files.

### Internal GitHub org Terraform modules

Terraform module sources of the form `github.com/<org>/<repo>//<path>?ref=<tag>` are not picked up by the standard `terraform` manager. Add a regex manager:

```json
{
  "regexManagers": [
    {
      "description": "Terraform modules from internal GitHub org myorg",
      "fileMatch": ["\\.tf$"],
      "matchStrings": [
        "source\\s*=\\s*\"github\\.com/myorg/(?<depName>[^/]+)//[^\"]*\\?ref=(?<currentValue>[^\"]+)\""
      ],
      "datasourceTemplate": "github-tags",
      "packageNameTemplate": "myorg/{{{depName}}}"
    }
  ],
  "packageRules": [
    {
      "matchManagers": ["regex"],
      "matchPackagePatterns": ["^myorg/"],
      "automerge": false,
      "groupName": "Internal Terraform modules (myorg)"
    }
  ]
}
```

Replace `myorg` with your GitHub org. Renovate will open PRs that update `?ref=v1.2.3` to the latest tag on the referenced repo.

### Private Terraform registry modules

For modules sourced from a private registry (`<hostname>/<namespace>/<module>/<provider>`):

```json
{
  "regexManagers": [
    {
      "description": "Terraform modules from private registry app.terraform.io",
      "fileMatch": ["\\.tf$"],
      "matchStrings": [
        "source\\s*=\\s*\"app\\.terraform\\.io/(?<namespace>[^/]+)/(?<depName>[^/]+)/(?<provider>[^\"]+)\""
      ],
      "datasourceTemplate": "terraform-module",
      "registryUrlTemplate": "https://app.terraform.io"
    }
  ]
}
```

### Terraform version pinned in GitHub Actions workflows

```json
{
  "regexManagers": [
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
  ]
}
```

### Tool versions in `.tool-versions` (asdf)

```json
{
  "regexManagers": [
    {
      "description": "Update tools pinned in .tool-versions (asdf)",
      "fileMatch": ["^\\.tool-versions$"],
      "matchStrings": [
        "(?<depName>[a-z0-9_-]+)\\s+(?<currentValue>[\\d\\.]+)"
      ],
      "datasourceTemplate": "github-releases",
      "packageNameTemplate": "asdf-vm/asdf-{{{depName}}}"
    }
  ]
}
```

### kubectl version in CI scripts

```json
{
  "regexManagers": [
    {
      "description": "Update kubectl version pinned in CI scripts",
      "fileMatch": ["^\\.github/workflows/.*\\.ya?ml$", "^scripts/.*\\.sh$"],
      "matchStrings": [
        "kubectl_version[=:]\\s*['\"]?v?(?<currentValue>[\\d\\.]+)['\"]?"
      ],
      "depNameTemplate": "kubernetes/kubectl",
      "datasourceTemplate": "github-releases",
      "extractVersionTemplate": "^v(?<version>.*)$"
    }
  ]
}
```

### Debugging regex managers

Test your `matchStrings` pattern against actual file content:

```bash
# Install renovate locally
npm install -g renovate

# Dry-run against a single file — prints what Renovate would extract
LOG_LEVEL=debug renovate --dry-run --print-config 2>&1 | grep -A5 "regexManagers"
```

Common mistakes:
- Forgetting to double-escape backslashes in JSON strings (`\\s` not `\s`)
- Using `(?<version>)` instead of `(?<currentValue>)` — the named capture must be `currentValue`
- Missing `datasourceTemplate` — required when there is no built-in datasource inference

---

## 11. Pre-commit Hook

Run `renovate-config-validator` locally before every commit using the official pre-commit hook. This catches config errors before they reach CI.

### Setup

Add to `.pre-commit-config.yaml` (create the file if it does not exist):

```yaml
repos:
  - repo: https://github.com/renovatebot/pre-commit-hooks
    rev: 43.150.0
    hooks:
      - id: renovate-config-validator
```

Install and activate:

```bash
pip install pre-commit    # or: brew install pre-commit
pre-commit install
pre-commit run renovate-config-validator --all-files
```

### Keeping the rev up to date

The `rev` pin tracks the Renovate release version. Once Renovate is running on the repo, it updates the `rev` automatically via a PR — the same way it updates any other dependency. No manual maintenance needed.

To pin with the digest for maximum supply chain security:

```bash
pre-commit autoupdate --freeze
```

This replaces the semver tag with the commit SHA:
```yaml
rev: 43.150.0  # frozen: sha256:<digest>
```

### Skipping the hook for a single commit

```bash
SKIP=renovate-config-validator git commit -m "wip: draft config"
```

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

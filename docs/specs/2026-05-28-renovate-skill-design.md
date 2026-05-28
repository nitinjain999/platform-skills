# Renovate Skill Design — v1.27.0

**Date:** 2026-05-28  
**Author:** Nitin Jain  
**Status:** Approved

---

## Overview

Add `/platform-skills:renovate` as a new slash command for v1.27.0. The skill automates two high-friction Renovate tasks: generating a correct `renovate.json` from scratch and triggering dependency-update PRs. A dedicated GitHub Actions workflow validates `renovate.json` on every change.

---

## Architecture

Follows the established pattern of this repo:

| Artifact | Purpose |
|---|---|
| `commands/renovate.md` | Slash command — `generate` and `update` modes |
| `references/renovate.md` | Deep-dive reference — managers, presets, security, GitOps integration |
| `.github/workflows/validate-renovate.yml` | CI validation — schema, config-validator, dry-run, coverage |
| `renovate.json` | Updated to cover all dep file types detected in the repo |
| `SKILL.md` | New row in tool table + slash command entry |
| `COMMANDS.md` | TOC entry + full command section (31 commands total) |
| `marketplace.json` | Version bump 1.26.0 → 1.27.0 |
| `tile.json` | Version bump → 1.27.0 |
| `CHANGELOG.md` | [1.27.0] entry |
| `INSTALLATION.md` | Version reference bump |

---

## Section 1: Command File (`commands/renovate.md`)

### Frontmatter

```yaml
name: renovate
description: Generate renovate.json for any repo covering all dependency file types, or trigger Renovate dependency-update PRs.
argument-hint: "[generate|update] [flags]"
```

### Interactive Wizard (no args)

Asks two questions in sequence:

**Q1 — Mode:**
```
What do you need?
  1. generate — create or regenerate renovate.json covering all file types in this repo
  2. update   — trigger Renovate to create dependency-update PRs for tracked packages

Enter 1–2 or mode name:
```

**Q2 — Mode-specific follow-up:**
- `generate`: `Any customisations? (e.g. --timezone Europe/Berlin, --assignee username, --schedule "before 6am on monday") — or press enter for defaults:`
- `update`: `Are you using the Renovate GitHub App or self-hosted? (app / self-hosted):`

### Mode: `generate`

Steps:
1. Scan the repo working tree for dependency file types using known patterns:

| Pattern | Manager |
|---|---|
| `.github/workflows/*.yml` | `github-actions` |
| `*.tf`, `*.tfvars` | `terraform` |
| `Chart.yaml`, `requirements.yaml` | `helmv3` |
| `go.mod` | `gomod` |
| `package.json`, `package-lock.json`, `yarn.lock` | `npm` |
| `requirements*.txt`, `Pipfile`, `pyproject.toml` | `pip` |
| `Dockerfile`, `docker-compose*.yml` | `docker` |
| `*.rs`, `Cargo.toml` | `cargo` |
| Kubernetes manifests (`kind: Deployment` etc.) | `kubernetes` |

2. Map detected file types → managers. Skip managers with no matching files.
3. Emit `renovate.json` with:
   - Base: `config:recommended`, `:dependencyDashboard`, `:semanticCommits`, `:separateMajorReleases`
   - `dependencyDashboard: true`, `dependencyDashboardTitle: "Renovate Dependency Dashboard"`
   - `vulnerabilityAlerts: { enabled: true }` + `osvVulnerabilityAlerts: true`
   - `minimumReleaseAge: "3 days"` on all automerge rules
   - `pinDigests: true` on `github-actions` manager
   - Per-detected-manager `packageRules` with sensible `groupName`, `automerge`, `schedule`
   - `regexManagers` for Terraform version in workflows and tool versions in docs
   - `postUpdateOptions` populated per detected ecosystem (`gomodTidy` for go, `npmDedupe` for npm)
   - `ignorePaths` standard set
4. Print coverage table showing which managers are active and which file paths they matched.

### Mode: `update`

**Path A — GitHub App:**
1. Verify Renovate App is installed on the repo (`gh api /repos/{owner}/{repo}/installation` check).
2. If installed: show the Dependency Dashboard issue URL; explain how to trigger selective updates by checking boxes in the issue body.
3. Alternative: `gh api -X POST /repos/{owner}/{repo}/dispatches -f event_type=renovate` (only works if repo has a `renovate` workflow dispatch listener).

**Path B — Self-hosted:**
1. Check `RENOVATE_TOKEN` is set; if not, print setup instructions.
2. Run: `renovate --dry-run=full --print-config 2>&1 | head -200` to preview PRs.
3. Ask user to confirm before live run.
4. Run: `npx renovate` (or `docker run renovate/renovate`) to create PRs.

In both paths, surface the list of packages that will be updated and their semver bump type before any action.

---

## Section 2: Reference File (`references/renovate.md`)

Seven sections:

1. **Manager Catalog** — full table of managers, file patterns, and notes
2. **Preset Reference** — what `config:recommended` includes; useful add-ons with descriptions
3. **Package Rules Patterns** — automerge strategy table by ecosystem; grouping; schedule recipes; `minimumReleaseAge` for supply chain safety
4. **Dependency Dashboard** — how to enable, how to trigger selective updates, how to manage the issue lifecycle
5. **Self-hosted vs GitHub App** — decision table; self-hosted via GitHub Actions runner pattern; token requirements
6. **GitOps Integration** — Renovate vs Flux Image Reflector Controller ownership boundary; how to avoid dual-management conflicts; recommended split (Renovate owns Helm + Terraform + language deps; Flux Image Reflector owns container image tags for running workloads)
7. **Security Hardening** — `pinDigests`, `osvVulnerabilityAlerts`, `minimumReleaseAge`, `rangeStrategy: pin`, private registry auth patterns
8. **Regex Managers** — templates for Terraform version in workflow YAML, tool versions in shell scripts and docs
9. **Post-update Options** — table: `gomodTidy`, `gomodUpdateImportPaths`, `npmDedupe`, `yarnDedupeFlags`
10. **Troubleshooting** — config-validator error messages, dry-run debug flags, preset conflicts, rate-limit handling

---

## Section 3: GitHub Actions Workflow (`.github/workflows/validate-renovate.yml`)

### Triggers

```yaml
on:
  pull_request:
    paths: ['renovate.json']
  push:
    branches: [main]
    paths: ['renovate.json']
```

### Jobs (parallel)

| Job | Tool | Blocks merge? | Fork-safe? |
|---|---|---|---|
| `validate-schema` | `ajv-cli` + Renovate schema URL | Yes | Yes |
| `validate-config` | `npx renovate-config-validator` | Yes | Yes |
| `validate-dryrun` | `npx renovate --dry-run=full` | Yes | No (skipped on forks) |
| `validate-coverage` | bash coverage scan | Warning only | Yes |
| `summary` | `needs` all four | Always runs | — |

### Coverage scan logic

Find files matching known dependency patterns. For each detected type, assert that `renovate.json` contains a manager or `packageRule` that covers it. Emit `⚠️ UNCOVERED: <type>` for gaps — non-blocking warning, not a failure gate (avoids false positives on intentionally excluded paths).

### Security

- `RENOVATE_TOKEN` stored as repo secret; dry-run job gated on `github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`
- All `uses:` pinned to commit SHA per existing repo policy
- `permissions: contents: read` minimum; `pull-requests: write` only on summary job

---

## Section 4: `renovate.json` Updates

Add to the existing file:
- `dependencyDashboard: true` + `dependencyDashboardTitle`
- `osvVulnerabilityAlerts: true`
- `minimumReleaseAge: "3 days"` on automerge package rules
- `packageRules` entries for `gomod`, `pip`, `npm` managers (with automerge minor/patch)
- `npmDedupe` to `postUpdateOptions`

Do not change the existing GitHub Actions, Terraform, or Helm rules — they are already correct.

---

## Section 5: Version Bump and Metadata

| File | Change |
|---|---|
| `marketplace.json` | `version: 1.26.0 → 1.27.0`; add `"renovate"` keyword; update description |
| `tile.json` | `version: 1.25.20 → 1.27.0` |
| `CHANGELOG.md` | Add `[1.27.0]` entry listing all new artifacts |
| `INSTALLATION.md` | Bump version reference |
| `SKILL.md` | Add `Renovate` row + `/platform-skills:renovate` slash command |
| `COMMANDS.md` | Add TOC entry + full command section |

---

## Out of Scope

- Monorepo / multi-path `baseBranches` patterns (single-path repo)
- Custom datasource plugins (no private registries in this repo)
- Renovate Enterprise / Mend features

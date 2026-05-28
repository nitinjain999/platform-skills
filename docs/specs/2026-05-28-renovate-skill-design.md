# Renovate Skill Design — v1.27.0

**Date:** 2026-05-28  
**Author:** Geetika Jain  
**Status:** Approved

---

## Overview

Add `/platform-skills:renovate` as a new slash command for v1.27.0. Two focused modes: `generate` produces a correct `renovate.json` by scanning what dependency file types the repo actually uses; `workflow` emits a GitHub Actions workflow that validates `renovate.json` on every PR that touches it. No auth secrets required.

---

## Architecture

| Artifact | Purpose |
|---|---|
| `commands/renovate.md` | Slash command — `generate` and `workflow` modes |
| `references/renovate.md` | Deep-dive reference — managers, presets, security, GitOps integration |
| `.github/workflows/validate-renovate.yml` | CI validation — schema, config-validator, coverage scan |
| `renovate.json` | Updated to cover all dep file types detected in the repo |
| `SKILL.md` | New `Renovate` row in tool table + `/platform-skills:renovate` slash command entry |
| `COMMANDS.md` | TOC entry + full command section (31 commands total) |
| `marketplace.json` | Version bump 1.26.0 → 1.27.0; add `renovate` keyword |
| `tile.json` | Version bump → 1.27.0 |
| `CHANGELOG.md` | [1.27.0] entry |
| `INSTALLATION.md` | Version reference bump |

---

## Section 1: Command File (`commands/renovate.md`)

### Frontmatter

```yaml
name: renovate
description: Generate renovate.json covering all dependency file types used in a repo, or emit a GitHub Actions workflow that validates renovate.json on PR.
argument-hint: "[generate|workflow]"
```

### Interactive Wizard (no args)

**Q1 — Mode:**
```
What do you need?
  1. generate  — scan this repo and create renovate.json covering all detected dep file types
  2. workflow  — generate a GitHub Actions workflow that validates renovate.json on every PR

Enter 1–2 or mode name:
```

No further questions — both modes have sensible defaults and proceed immediately after mode selection.

---

### Mode: `generate`

**Purpose:** Scan the repo working tree, detect which dependency ecosystems are present, and emit a `renovate.json` that covers exactly those managers — no more, no less.

**Steps:**

1. Scan for dependency file types using known patterns:

| File pattern | Manager |
|---|---|
| `.github/workflows/*.yml` | `github-actions` |
| `*.tf`, `*.tfvars` | `terraform` |
| `Chart.yaml`, `requirements.yaml` | `helmv3` |
| `go.mod` | `gomod` |
| `package.json`, `package-lock.json`, `yarn.lock` | `npm` |
| `requirements*.txt`, `Pipfile`, `pyproject.toml` | `pip` |
| `Dockerfile`, `docker-compose*.yml` | `docker` |
| `Cargo.toml` | `cargo` |
| Kubernetes manifests (`kind: Deployment` etc.) | `kubernetes` |

2. Print coverage table — detected managers and matched file paths. Skip managers with no matches.

3. Emit `renovate.json` containing only detected managers, with:
   - Base presets: `config:recommended`, `:dependencyDashboard`, `:semanticCommits`, `:separateMajorReleases`
   - `dependencyDashboard: true` + `dependencyDashboardTitle: "Renovate Dependency Dashboard"`
   - `vulnerabilityAlerts: { enabled: true }` + `osvVulnerabilityAlerts: true`
   - `pinDigests: true` scoped to `github-actions` manager
   - `minimumReleaseAge: "3 days"` on all automerge package rules (supply chain safety)
   - Per-detected-manager `packageRules` with `groupName`, `automerge`, `schedule`
   - `regexManagers` for Terraform version pins in workflow YAML and tool versions in docs
   - `postUpdateOptions` per ecosystem: `gomodTidy` (go), `npmDedupe` (npm)
   - Standard `ignorePaths`: `node_modules`, `vendor`, `.terraform`, `charts`

4. If `renovate.json` already exists: print a diff (additions/changes only). Ask: `Write to renovate.json? [y/N]`

5. If no existing file: write directly and confirm.

---

### Mode: `workflow`

**Purpose:** Emit a ready-to-use `.github/workflows/validate-renovate.yml` that automatically validates `renovate.json` whenever a PR changes it. No secrets or tokens required.

**Steps:**

1. Emit the workflow file (content defined in Section 3 below).
2. Check if `.github/workflows/validate-renovate.yml` already exists — if so, show diff and ask to overwrite.
3. Write file and print: `Add and commit .github/workflows/validate-renovate.yml to your repo. The workflow fires automatically on any PR that modifies renovate.json.`

---

## Section 2: Reference File (`references/renovate.md`)

Eight sections:

1. **Manager Catalog** — full table: manager name, file patterns, notes, common `packageRules` options
2. **Preset Reference** — what `config:recommended` includes; useful add-on presets with descriptions
3. **Package Rules Patterns** — automerge strategy by ecosystem; grouping recipes; schedule examples; `minimumReleaseAge` for supply chain safety
4. **Dependency Dashboard** — how to enable, how to trigger selective updates from the issue, lifecycle management
5. **GitOps Integration** — Renovate vs Flux Image Reflector Controller ownership boundary; recommended split: Renovate owns Helm + Terraform + language deps; Flux Image Reflector owns running workload image tags
6. **Security Hardening** — `pinDigests`, `osvVulnerabilityAlerts`, `minimumReleaseAge`, `rangeStrategy: pin`, private registry auth patterns
7. **Regex Managers** — templates for Terraform version in workflow YAML, tool versions in shell scripts and docs
8. **Troubleshooting** — `renovate-config-validator` error messages, common preset conflicts, coverage scan false positives

---

## Section 3: GitHub Actions Workflow (`.github/workflows/validate-renovate.yml`)

### Trigger

```yaml
on:
  pull_request:
    paths:
      - 'renovate.json'
```

Fires only on PRs that touch `renovate.json`. No push trigger — validation on PR is sufficient; main branch is protected by the PR gate.

### Jobs (run in parallel)

| Job | Tool | Fails PR? |
|---|---|---|
| `validate-schema` | `ajv-cli` against official Renovate schema URL | Yes |
| `validate-config` | `npx renovate-config-validator renovate.json` | Yes |
| `validate-coverage` | bash scan: detect dep file types, warn on uncovered | Warning only |
| `summary` | `needs` all three, posts table to `GITHUB_STEP_SUMMARY` | Always runs |

**No dry-run job.** Renovate App handles runtime; CI only validates config correctness.

**No secrets required.** All three jobs use only `GITHUB_TOKEN` (auto-injected) for checkout. Fork PRs work identically.

### Coverage scan logic

Find files matching known dependency patterns. For each detected type, check that `renovate.json` contains a matching manager or `packageRule`. Emit `⚠️ UNCOVERED: <type>` for gaps — non-blocking (avoids false positives on intentionally excluded paths). Blocking failures are left to schema and config-validator jobs.

### Security

- All `uses:` actions pinned to commit SHA per existing repo policy
- `permissions: contents: read` on all jobs; `pull-requests: write` only on `summary` job for `GITHUB_STEP_SUMMARY`
- No `RENOVATE_TOKEN` or other secrets

---

## Section 4: `renovate.json` Updates

Patch the existing file:

| Addition | Reason |
|---|---|
| `dependencyDashboard: true` + `dependencyDashboardTitle` | Makes dashboard explicit |
| `osvVulnerabilityAlerts: true` | Newer OSV-based alerts alongside existing `vulnerabilityAlerts` |
| `minimumReleaseAge: "3 days"` on automerge rules | Supply chain safety — prevents automerging freshly published packages |
| `packageRules` for `gomod`, `pip`, `npm` | Cover ecosystems present but missing from current config |
| `npmDedupe` in `postUpdateOptions` | Keeps lockfile clean after npm updates |

Do not change existing GitHub Actions, Terraform, or Helm rules — they are already correct.

---

## Section 5: Version Bump and Metadata

| File | Change |
|---|---|
| `marketplace.json` | `version: 1.26.0 → 1.27.0`; add `"renovate"` keyword; update description |
| `tile.json` | `version: 1.25.20 → 1.27.0` |
| `CHANGELOG.md` | Add `[1.27.0]` entry |
| `INSTALLATION.md` | Bump version reference |
| `SKILL.md` | Add `Renovate` row + `/platform-skills:renovate` slash command |
| `COMMANDS.md` | Add TOC entry + full command section |

---

## Out of Scope

- `update` mode / triggering dependency PRs (v1.27.0 scope is generate + workflow only)
- Monorepo / multi-path `baseBranches` patterns
- Custom datasource plugins / private registries
- Renovate Enterprise / Mend features
- Renovate self-hosted setup

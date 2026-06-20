# Design: Docusaurus GitHub Pages Site for platform-skills

**Date:** 2026-06-20  
**Status:** Approved

---

## Goal

Publish a public documentation site at `https://nitinjain999.github.io/platform-skills/` that:
- Auto-deploys on every push to `main`
- Serves as a discovery/marketing page for new users
- Serves as a day-to-day reference for platform engineers actively using the skill

---

## Architecture

### Repo Layout

```
platform-skills/
├── references/               ← untouched, source of truth for agents
├── commands/                 ← untouched, source of truth for agents
├── website/                  ← Docusaurus app (isolated sub-project)
│   ├── docusaurus.config.js
│   ├── sidebars.js
│   ├── package.json
│   ├── src/
│   │   ├── pages/
│   │   │   └── index.tsx     ← custom landing page
│   │   └── css/
│   │       └── custom.css
│   └── static/
└── .github/workflows/
    └── pages.yml             ← new workflow, deploys on push to main
```

### Docusaurus Config

Two `@docusaurus/plugin-content-docs` instances — direct path references, no file copying:

| Instance | id | path | routeBasePath |
|---|---|---|---|
| References | `references` | `../references` | `/docs` |
| Commands | `commands` | `../commands` | `/commands` |

Search: Algolia DocSearch (free tier for public repos), wired in `docusaurus.config.js`.

No blog, no versioning, no i18n.

---

## Navigation

Hybrid nav: top-level domain groups surfacing both the reference deep-dive and command for each topic.

| Group | References | Commands |
|---|---|---|
| Kubernetes | `kubernetes`, `helm`, `karpenter`, `keda`, `openshift` | `helmcheck`, `keda`, `karpenter` |
| GitOps | `fluxcd`, `fluxcd-helmrelease`, `fluxcd-kustomization`, `fluxcd-mcp`, `fluxcd-migration`, `fluxcd-notifications`, `fluxcd-operator`, `fluxcd-resourcesets`, `fluxcd-security`, `fluxcd-sources`, `fluxcd-terraform`, `fluxcd-troubleshooting`, `argocd` | `fluxcd`, `gitops` |
| Terraform | `terraform` | `terraform` |
| AWS & Azure | `aws`, `aws-cloudfront`, `aws-mcp-profiles`, `aws-waf`, `azure` | `aws`, `aws-profile` |
| GitHub Actions & CI | `github-actions`, `composite-actions`, `renovate`, `conventional-commits` | `composite-actions`, `commit`, `renovate` |
| Security | `kyverno`, `opa`, `supply-chain`, `runtime-security`, `trivy`, `checkov`, `linkerd`, `secrets` | `kyverno`, `opa`, `supply-chain`, `runtime-security`, `trivy`, `checkov`, `linkerd` |
| Observability | `observability`, `datadog`, `dynatrace`, `llm-observability` | `observability`, `datadog`, `dynatrace` |
| Platform Engineering | `platform-operating-model`, `platform-mindset`, `dora`, `chaos`, `compliance`, `pr-review`, `documentation`, `awesome-docs`, `mcp` | `debug`, `review`, `product`, `dora`, `chaos`, `compliance`, `pr-review`, `document`, `awesome-docs`, `mcp`, `triage`, `self-improve` |
| Agent Setup | `setup-agents`, `setup-agents-add`, `setup-agents-build`, `setup-agents-generate`, `setup-agents-prompts`, `setup-agents-review`, `setup-agents-schemas`, `setup-agents-template`, `agent-self-improve` | `setup-agents` |

`sidebars.js` is hand-authored (not auto-generated) to enforce this grouping. It exports two sidebar objects — one for the `references` plugin instance, one for `commands` — both in the same file. New files added to `references/` or `commands/` must be added to `sidebars.js` manually.

Front matter (`id`, `title`, `sidebar_label`) will be added to markdown files that lack it as part of implementation.

---

## Landing Page (`src/pages/index.tsx`)

Five sections, top to bottom:

### 1. Hero
- Tagline: *"A production-grade field handbook for platform engineers"*
- Two CTAs: `Get Started` → `/docs/kubernetes` and `View on GitHub` → `https://github.com/nitinjain999/platform-skills`
- Version badge: `v1.34.0 — What's new` linking to `CHANGELOG.md`

### 2. Before/After Block
- One concrete example drawn from `BEFORE_AFTER.md`: the Kubernetes production deployment example (unpinned image, missing securityContext, hardcoded credentials → fixed)
- Renders as a two-column code diff block

### 3. Feature Strip
Six tiles, one per domain:

| Tile | Description |
|---|---|
| Kubernetes | Cluster baseline, Helm, KEDA, Karpenter |
| GitOps | Flux CD, Argo CD, OCI delivery |
| Terraform | Blast radius, IAM, SOC 2 |
| AWS | CloudFront, WAF, Lambda@Edge, IAM |
| Security | Supply chain, Falco, OPA, Kyverno |
| Observability | Datadog, Dynatrace, OpenTelemetry |

### 4. Install Tabs
Docusaurus `<Tabs>` component, one tab per agent:

| Tab | Install method |
|---|---|
| **Claude Code** | `claude plugin install nitinjain999/platform-skills` |
| **Cursor** | Cursor Rules marketplace — search `platform-skills`; fallback: `./install.sh --cursor --target .` |
| **VS Code / Copilot** | `./install.sh --copilot --target .` |
| **Codex** | `codex skill add nitinjain999/platform-skills` |

### 5. Command Showcase
Three commands displayed as a compact card row:

| Command | Description |
|---|---|
| `/platform-skills:triage` | Triages a PR comment from a bot or human reviewer — fetches, classifies, fixes, replies, resolves |
| `/platform-skills:checkov` | Runs Checkov static and plan-level Terraform scanning with AI-generated fix mode |
| `/platform-skills:karpenter` | Diagnoses Karpenter node provisioning failures with blast radius and rollback plan |

---

## GitHub Actions Workflow (`.github/workflows/pages.yml`)

Triggers: `push` to `main`, `workflow_dispatch`

Steps:
1. `actions/checkout`
2. `actions/setup-node` (Node 20)
3. `npm ci` in `website/`
4. `npm run build` in `website/`
5. `actions/upload-pages-artifact` from `website/build/`
6. `actions/deploy-pages`

Permissions: `contents: read`, `pages: write`, `id-token: write`

GitHub Pages must be enabled in repo settings → Source: **GitHub Actions** (not branch).

---

## Front Matter Requirements

Files missing `title` front matter will render with their filename as the page title. As part of implementation, add minimal front matter to files that lack it:

```yaml
---
title: Flux CD Overview
sidebar_label: Overview
---
```

Scope: all files in `references/` and `commands/`. Estimated ~40 files need front matter added.

---

## Out of Scope

- Blog section
- Versioned docs
- i18n / translations
- Demo GIFs (existing GIFs are not production-quality; deferred)
- Social proof / star count strip
- Agent logo strip

---

## Validation Steps

1. `cd website && npm run build` succeeds locally with no broken links
2. `npm run serve` — landing page renders all 5 sections correctly
3. Nav sidebar shows all 9 domain groups with correct files under each
4. Install tabs render correctly on mobile viewport
5. Algolia search returns results for "flux", "terraform", "karpenter"
6. GitHub Actions `pages.yml` run completes and site is live at `nitinjain999.github.io/platform-skills`

---

## Rollback Plan

- GitHub Pages can be disabled in repo settings instantly (no infra to tear down)
- The `website/` directory is fully additive — removing it restores the repo to its previous state
- The `pages.yml` workflow can be deleted without affecting any existing workflows

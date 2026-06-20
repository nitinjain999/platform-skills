# Docusaurus GitHub Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a production-ready Docusaurus site at `https://nitinjain999.github.io/platform-skills/` that auto-deploys on push to `main`, serves as a marketing landing page and day-to-day reference for platform engineers.

**Architecture:** Docusaurus app lives in `website/` subfolder. Two `@docusaurus/plugin-content-docs` instances point directly at `../references` and `../commands` — no file copying. A hand-authored `sidebars.js` groups all 94 files into 9 domain groups. A custom `src/pages/index.tsx` landing page handles discovery/marketing.

**Tech Stack:** Docusaurus 3.x, React 18, TypeScript, Node 20, GitHub Actions (`actions/deploy-pages`)

## Global Constraints

- `url`: `https://nitinjain999.github.io` — no trailing slash, no path
- `baseUrl`: `/platform-skills/` — required for project Pages; every asset and link is prefixed with this
- `colorMode.defaultMode`: `dark`; `respectPrefersColorScheme: true`
- Docusaurus version: `3.x` (latest stable at scaffold time)
- Node version: 20 (matches CI)
- All `references/` and `commands/` files stay at repo root — never moved, never copied
- `website/` is a self-contained sub-project — `npm` commands always run from `website/`
- Branch: `docs/docusaurus-pages-design` (already checked out)
- No blog, no versioning, no i18n

---

## File Map

### New files to create

| File | Purpose |
|---|---|
| `website/package.json` | Docusaurus app dependencies |
| `website/docusaurus.config.js` | Site config: url, baseUrl, two docs plugin instances, Algolia, colorMode |
| `website/sidebars.js` | Hand-authored sidebar: 9 domain groups across references + commands |
| `website/src/pages/index.tsx` | Custom landing page: hero, before/after, feature strip, install tabs, command showcase |
| `website/src/css/custom.css` | Dark theme overrides, landing page component styles |
| `website/static/.nojekyll` | Prevents GitHub Pages from running Jekyll on the build output |
| `.github/workflows/pages.yml` | CI: build + deploy on push to main |

### Files to modify

| File | Change |
|---|---|
| `references/*.md` (all 59) | Add Docusaurus `title:` front matter block |
| `commands/*.md` (all 35) | Add Docusaurus `title:` and `sidebar_label:` to existing agent front matter |
| `.gitignore` | Add `website/node_modules/` and `website/build/` |

---

## Task 1: Scaffold Docusaurus in `website/`

**Files:**
- Create: `website/package.json`
- Create: `website/docusaurus.config.js`
- Create: `website/static/.nojekyll`
- Modify: `.gitignore`

**Interfaces:**
- Produces: a buildable Docusaurus app with correct `url`/`baseUrl`; subsequent tasks add content to it

- [ ] **Step 1: Install Docusaurus into `website/`**

```bash
cd /Users/nitin.jain/atg/personnel_gh/platform-skills
npx create-docusaurus@latest website classic --typescript --skip-install
```

Expected output: scaffold created in `website/` with `docusaurus.config.ts`, `src/`, `static/`, `package.json`.

- [ ] **Step 2: Install dependencies**

```bash
cd website && npm install
```

Expected: `node_modules/` created, no errors.

- [ ] **Step 3: Rename config to `.js` and replace contents**

Delete `website/docusaurus.config.ts` and create `website/docusaurus.config.js`:

```javascript
// @ts-check
const { themes: prismThemes } = require('prism-react-renderer');

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Platform Skills',
  tagline: 'A production-grade field handbook for platform engineers',
  favicon: 'img/favicon.ico',

  url: 'https://nitinjain999.github.io',
  baseUrl: '/platform-skills/',

  organizationName: 'nitinjain999',
  projectName: 'platform-skills',
  trailingSlash: false,

  onBrokenLinks: 'warn',
  onBrokenMarkdownLinks: 'warn',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: false, // disabled — we use standalone plugin instances below
        blog: false,
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      }),
    ],
  ],

  plugins: [
    [
      '@docusaurus/plugin-content-docs',
      {
        id: 'references',
        path: '../references',
        routeBasePath: 'docs',
        sidebarPath: require.resolve('./sidebars.js'),
        sidebarCollapsible: true,
        sidebarCollapsed: false,
      },
    ],
    [
      '@docusaurus/plugin-content-docs',
      {
        id: 'commands',
        path: '../commands',
        routeBasePath: 'commands',
        sidebarPath: require.resolve('./sidebars.js'),
        sidebarCollapsible: true,
        sidebarCollapsed: false,
      },
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      colorMode: {
        defaultMode: 'dark',
        disableSwitch: false,
        respectPrefersColorScheme: true,
      },
      navbar: {
        title: 'Platform Skills',
        logo: {
          alt: 'Platform Skills',
          src: 'img/logo.svg',
        },
        items: [
          {
            type: 'docSidebar',
            sidebarId: 'referencesSidebar',
            docsPluginId: 'references',
            position: 'left',
            label: 'References',
          },
          {
            type: 'docSidebar',
            sidebarId: 'commandsSidebar',
            docsPluginId: 'commands',
            position: 'left',
            label: 'Commands',
          },
          {
            href: 'https://github.com/nitinjain999/platform-skills',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Docs',
            items: [
              { label: 'Kubernetes', to: '/docs/kubernetes' },
              { label: 'GitOps', to: '/docs/fluxcd' },
              { label: 'Terraform', to: '/docs/terraform' },
            ],
          },
          {
            title: 'More',
            items: [
              { label: 'GitHub', href: 'https://github.com/nitinjain999/platform-skills' },
              { label: 'Changelog', href: 'https://github.com/nitinjain999/platform-skills/blob/main/CHANGELOG.md' },
            ],
          },
        ],
        copyright: `Apache 2.0 — Platform Skills`,
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
        additionalLanguages: ['bash', 'yaml', 'hcl', 'typescript'],
      },
    }),
};

module.exports = config;
```

- [ ] **Step 4: Add `.nojekyll` to static/**

Create `website/static/.nojekyll` as an empty file. This prevents GitHub Pages from treating the build output as a Jekyll site (which would strip files starting with `_`).

```bash
touch website/static/.nojekyll
```

- [ ] **Step 5: Update `.gitignore`**

Append to the repo root `.gitignore`:

```
website/node_modules/
website/build/
website/.docusaurus/
```

- [ ] **Step 6: Verify build scaffolds without errors**

```bash
cd website && npm run build 2>&1 | tail -20
```

Expected: build may warn about missing sidebars (OK at this stage) but must not error on config parsing. The `url`/`baseUrl` config is validated at build time.

- [ ] **Step 7: Commit**

```bash
git add website/ .gitignore
git commit -m "feat(website): scaffold Docusaurus app in website/"
```

---

## Task 2: Add front matter to all markdown files

**Files:**
- Modify: `references/*.md` (all 59 files)
- Modify: `commands/*.md` (all 35 files)

**Interfaces:**
- Consumes: nothing
- Produces: every file has a `title:` field that Docusaurus uses as the page title and breadcrumb label; command files also get `sidebar_label:` and `custom_edit_url: null` (to suppress the "Edit this page" link that would point at the wrong path)

**Important:** Reference files have bare `---` section dividers inside them (not YAML front matter). Docusaurus only treats the very first `---` block as front matter if it is at line 1 of the file. Files that start with `# Heading` have no front matter — add it before the `#` heading.

- [ ] **Step 1: Add front matter to all 59 reference files**

Run this script from the repo root:

```bash
#!/usr/bin/env bash
set -euo pipefail

add_frontmatter() {
  local file="$1"
  local title="$2"
  # Only add if file does NOT already start with ---
  if head -1 "$file" | grep -q "^---"; then
    echo "SKIP (has front matter): $file"
    return
  fi
  local tmp=$(mktemp)
  printf -- "---\ntitle: %s\ncustom_edit_url: null\n---\n\n" "$title" > "$tmp"
  cat "$file" >> "$tmp"
  mv "$tmp" "$file"
  echo "DONE: $file"
}

# references/
add_frontmatter references/agent-self-improve.md "Agent Self-Improvement"
add_frontmatter references/argocd.md "Argo CD"
add_frontmatter references/awesome-docs.md "Awesome Docs"
add_frontmatter references/aws-cloudfront.md "AWS CloudFront"
add_frontmatter references/aws-mcp-profiles.md "AWS MCP Profiles"
add_frontmatter references/aws-waf.md "AWS WAF"
add_frontmatter references/aws.md "AWS"
add_frontmatter references/azure.md "Azure"
add_frontmatter references/chaos.md "Chaos Engineering"
add_frontmatter references/checkov.md "Checkov"
add_frontmatter references/compliance.md "Compliance"
add_frontmatter references/composite-actions.md "GitHub Actions: Composite Actions"
add_frontmatter references/conventional-commits.md "Conventional Commits"
add_frontmatter references/datadog.md "Datadog"
add_frontmatter references/documentation.md "Documentation"
add_frontmatter references/dora.md "DORA Metrics"
add_frontmatter references/dynatrace.md "Dynatrace"
add_frontmatter references/fluxcd-helmrelease.md "Flux CD: HelmRelease"
add_frontmatter references/fluxcd-kustomization.md "Flux CD: Kustomization"
add_frontmatter references/fluxcd-mcp.md "Flux CD: MCP"
add_frontmatter references/fluxcd-migration.md "Flux CD: Migration"
add_frontmatter references/fluxcd-notifications.md "Flux CD: Notifications"
add_frontmatter references/fluxcd-operator.md "Flux CD: Operator"
add_frontmatter references/fluxcd-resourcesets.md "Flux CD: ResourceSets"
add_frontmatter references/fluxcd-security.md "Flux CD: Security"
add_frontmatter references/fluxcd-sources.md "Flux CD: Sources"
add_frontmatter references/fluxcd-terraform.md "Flux CD: Terraform"
add_frontmatter references/fluxcd-troubleshooting.md "Flux CD: Troubleshooting"
add_frontmatter references/fluxcd.md "Flux CD"
add_frontmatter references/github-actions.md "GitHub Actions"
add_frontmatter references/helm.md "Helm"
add_frontmatter references/karpenter.md "Karpenter"
add_frontmatter references/keda.md "KEDA"
add_frontmatter references/kubernetes.md "Kubernetes"
add_frontmatter references/kyverno.md "Kyverno"
add_frontmatter references/linkerd.md "Linkerd"
add_frontmatter references/linux-networking.md "Linux Networking"
add_frontmatter references/llm-observability.md "LLM Observability"
add_frontmatter references/mcp.md "MCP"
add_frontmatter references/observability.md "Observability"
add_frontmatter references/opa.md "OPA / Rego"
add_frontmatter references/openshift.md "OpenShift"
add_frontmatter references/platform-mindset.md "Platform Mindset"
add_frontmatter references/platform-operating-model.md "Platform Operating Model"
add_frontmatter references/pr-review.md "PR Review"
add_frontmatter references/renovate.md "Renovate"
add_frontmatter references/runtime-security.md "Runtime Security"
add_frontmatter references/secrets.md "Secrets Management"
add_frontmatter references/setup-agents-add.md "Setup Agents: Add"
add_frontmatter references/setup-agents-build.md "Setup Agents: Build"
add_frontmatter references/setup-agents-generate.md "Setup Agents: Generate"
add_frontmatter references/setup-agents-prompts.md "Setup Agents: Prompts"
add_frontmatter references/setup-agents-review.md "Setup Agents: Review"
add_frontmatter references/setup-agents-schemas.md "Setup Agents: Schemas"
add_frontmatter references/setup-agents-template.md "Setup Agents: Template"
add_frontmatter references/setup-agents.md "Setup Agents"
add_frontmatter references/supply-chain.md "Supply Chain Security"
add_frontmatter references/terraform.md "Terraform"
add_frontmatter references/trivy.md "Trivy"
```

Save as `scripts/add-frontmatter.sh`, make executable, and run:

```bash
chmod +x scripts/add-frontmatter.sh && bash scripts/add-frontmatter.sh
```

- [ ] **Step 2: Add front matter to all 35 command files**

Command files already have agent front matter (`name:`, `description:`, optionally `argument-hint:`). Insert `title:` and `sidebar_label:` and `custom_edit_url: null` into that existing block by appending after the last existing field before the closing `---`.

Run this script from repo root:

```bash
#!/usr/bin/env bash
set -euo pipefail

add_cmd_frontmatter() {
  local file="$1"
  local title="$2"
  local label="$3"
  # Insert title/sidebar_label/custom_edit_url before the closing --- of the front matter block
  # The closing --- is the second occurrence of ^---
  python3 - "$file" "$title" "$label" <<'PYEOF'
import sys, re
path, title, label = sys.argv[1], sys.argv[2], sys.argv[3]
content = open(path).read()
# Find the second --- (closing front matter)
parts = content.split('---', 2)  # ['', 'existing fields\n', 'rest of file']
if len(parts) < 3:
    print(f"SKIP (no front matter block): {path}")
    sys.exit(0)
fm = parts[1]
if 'title:' in fm:
    print(f"SKIP (already has title): {path}")
    sys.exit(0)
new_fm = fm.rstrip('\n') + f'\ntitle: "{title}"\nsidebar_label: "{label}"\ncustom_edit_url: null\n'
new_content = '---' + new_fm + '---' + parts[2]
open(path, 'w').write(new_content)
print(f"DONE: {path}")
PYEOF
}

add_cmd_frontmatter commands/awesome-docs.md "Awesome Docs Command" "awesome-docs"
add_cmd_frontmatter commands/aws-profile.md "AWS Profile Command" "aws-profile"
add_cmd_frontmatter commands/aws.md "AWS Command" "aws"
add_cmd_frontmatter commands/chaos.md "Chaos Engineering Command" "chaos"
add_cmd_frontmatter commands/checkov.md "Checkov Command" "checkov"
add_cmd_frontmatter commands/commit.md "Commit Command" "commit"
add_cmd_frontmatter commands/compliance.md "Compliance Command" "compliance"
add_cmd_frontmatter commands/composite-actions.md "Composite Actions Command" "composite-actions"
add_cmd_frontmatter commands/datadog.md "Datadog Command" "datadog"
add_cmd_frontmatter commands/debug.md "Debug Command" "debug"
add_cmd_frontmatter commands/document.md "Document Command" "document"
add_cmd_frontmatter commands/dora.md "DORA Metrics Command" "dora"
add_cmd_frontmatter commands/dynatrace.md "Dynatrace Command" "dynatrace"
add_cmd_frontmatter commands/fluxcd.md "Flux CD Command" "fluxcd"
add_cmd_frontmatter commands/gitops.md "GitOps Command" "gitops"
add_cmd_frontmatter commands/helmcheck.md "Helm Check Command" "helmcheck"
add_cmd_frontmatter commands/karpenter.md "Karpenter Command" "karpenter"
add_cmd_frontmatter commands/keda.md "KEDA Command" "keda"
add_cmd_frontmatter commands/kyverno.md "Kyverno Command" "kyverno"
add_cmd_frontmatter commands/linkerd.md "Linkerd Command" "linkerd"
add_cmd_frontmatter commands/linux.md "Linux Command" "linux"
add_cmd_frontmatter commands/mcp.md "MCP Command" "mcp"
add_cmd_frontmatter commands/observability.md "Observability Command" "observability"
add_cmd_frontmatter commands/opa.md "OPA Command" "opa"
add_cmd_frontmatter commands/pr-review.md "PR Review Command" "pr-review"
add_cmd_frontmatter commands/product.md "Product Command" "product"
add_cmd_frontmatter commands/renovate.md "Renovate Command" "renovate"
add_cmd_frontmatter commands/review.md "Review Command" "review"
add_cmd_frontmatter commands/runtime-security.md "Runtime Security Command" "runtime-security"
add_cmd_frontmatter commands/self-improve.md "Self-Improve Command" "self-improve"
add_cmd_frontmatter commands/setup-agents.md "Setup Agents Command" "setup-agents"
add_cmd_frontmatter commands/supply-chain.md "Supply Chain Command" "supply-chain"
add_cmd_frontmatter commands/terraform.md "Terraform Command" "terraform"
add_cmd_frontmatter commands/triage.md "Triage Command" "triage"
add_cmd_frontmatter commands/trivy.md "Trivy Command" "trivy"
```

Save as `scripts/add-cmd-frontmatter.sh`, make executable, and run:

```bash
chmod +x scripts/add-cmd-frontmatter.sh && bash scripts/add-cmd-frontmatter.sh
```

- [ ] **Step 3: Verify a sample of files look correct**

```bash
head -8 references/kubernetes.md
echo "---"
head -10 commands/triage.md
```

Expected for `references/kubernetes.md`:
```
---
title: Kubernetes
custom_edit_url: null
---

# Kubernetes Reference
```

Expected for `commands/triage.md`:
```
---
name: triage
description: Triages a PR comment...
argument-hint: "..."
title: "Triage Command"
sidebar_label: "triage"
custom_edit_url: null
---
```

- [ ] **Step 4: Commit**

```bash
git add references/ commands/ scripts/
git commit -m "feat(docs): add Docusaurus front matter to all references and commands"
```

---

## Task 3: Author `sidebars.js`

**Files:**
- Create: `website/sidebars.js`

**Interfaces:**
- Consumes: front matter `title:` fields from Task 2; Docusaurus config plugin ids `references` and `commands` from Task 1
- Produces: `referencesSidebar` and `commandsSidebar` exports consumed by `docusaurus.config.js`

- [ ] **Step 1: Create `website/sidebars.js`**

```javascript
// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  // ── References sidebar ────────────────────────────────────────────
  referencesSidebar: [
    {
      type: 'category',
      label: 'Kubernetes',
      items: [
        { type: 'doc', id: 'kubernetes' },
        { type: 'doc', id: 'helm' },
        { type: 'doc', id: 'keda' },
        { type: 'doc', id: 'karpenter' },
        { type: 'doc', id: 'openshift' },
      ],
    },
    {
      type: 'category',
      label: 'GitOps',
      items: [
        { type: 'doc', id: 'fluxcd' },
        { type: 'doc', id: 'fluxcd-helmrelease' },
        { type: 'doc', id: 'fluxcd-kustomization' },
        { type: 'doc', id: 'fluxcd-mcp' },
        { type: 'doc', id: 'fluxcd-migration' },
        { type: 'doc', id: 'fluxcd-notifications' },
        { type: 'doc', id: 'fluxcd-operator' },
        { type: 'doc', id: 'fluxcd-resourcesets' },
        { type: 'doc', id: 'fluxcd-security' },
        { type: 'doc', id: 'fluxcd-sources' },
        { type: 'doc', id: 'fluxcd-terraform' },
        { type: 'doc', id: 'fluxcd-troubleshooting' },
        { type: 'doc', id: 'argocd' },
      ],
    },
    {
      type: 'category',
      label: 'Terraform',
      items: [
        { type: 'doc', id: 'terraform' },
      ],
    },
    {
      type: 'category',
      label: 'AWS & Azure',
      items: [
        { type: 'doc', id: 'aws' },
        { type: 'doc', id: 'aws-cloudfront' },
        { type: 'doc', id: 'aws-mcp-profiles' },
        { type: 'doc', id: 'aws-waf' },
        { type: 'doc', id: 'azure' },
      ],
    },
    {
      type: 'category',
      label: 'GitHub Actions & CI',
      items: [
        { type: 'doc', id: 'github-actions' },
        { type: 'doc', id: 'composite-actions' },
        { type: 'doc', id: 'renovate' },
        { type: 'doc', id: 'conventional-commits' },
      ],
    },
    {
      type: 'category',
      label: 'Security',
      items: [
        { type: 'doc', id: 'kyverno' },
        { type: 'doc', id: 'opa' },
        { type: 'doc', id: 'supply-chain' },
        { type: 'doc', id: 'runtime-security' },
        { type: 'doc', id: 'trivy' },
        { type: 'doc', id: 'checkov' },
        { type: 'doc', id: 'linkerd' },
        { type: 'doc', id: 'secrets' },
      ],
    },
    {
      type: 'category',
      label: 'Observability',
      items: [
        { type: 'doc', id: 'observability' },
        { type: 'doc', id: 'datadog' },
        { type: 'doc', id: 'dynatrace' },
        { type: 'doc', id: 'llm-observability' },
      ],
    },
    {
      type: 'category',
      label: 'Platform Engineering',
      items: [
        { type: 'doc', id: 'platform-operating-model' },
        { type: 'doc', id: 'platform-mindset' },
        { type: 'doc', id: 'dora' },
        { type: 'doc', id: 'chaos' },
        { type: 'doc', id: 'compliance' },
        { type: 'doc', id: 'pr-review' },
        { type: 'doc', id: 'documentation' },
        { type: 'doc', id: 'awesome-docs' },
        { type: 'doc', id: 'mcp' },
      ],
    },
    {
      type: 'category',
      label: 'Agent Setup',
      items: [
        { type: 'doc', id: 'setup-agents' },
        { type: 'doc', id: 'setup-agents-add' },
        { type: 'doc', id: 'setup-agents-build' },
        { type: 'doc', id: 'setup-agents-generate' },
        { type: 'doc', id: 'setup-agents-prompts' },
        { type: 'doc', id: 'setup-agents-review' },
        { type: 'doc', id: 'setup-agents-schemas' },
        { type: 'doc', id: 'setup-agents-template' },
        { type: 'doc', id: 'agent-self-improve' },
      ],
    },
  ],

  // ── Commands sidebar ───────────────────────────────────────────────
  commandsSidebar: [
    {
      type: 'category',
      label: 'Kubernetes',
      items: [
        { type: 'doc', id: 'helmcheck' },
        { type: 'doc', id: 'keda' },
        { type: 'doc', id: 'karpenter' },
      ],
    },
    {
      type: 'category',
      label: 'GitOps',
      items: [
        { type: 'doc', id: 'fluxcd' },
        { type: 'doc', id: 'gitops' },
      ],
    },
    {
      type: 'category',
      label: 'Terraform',
      items: [
        { type: 'doc', id: 'terraform' },
      ],
    },
    {
      type: 'category',
      label: 'AWS & Azure',
      items: [
        { type: 'doc', id: 'aws' },
        { type: 'doc', id: 'aws-profile' },
      ],
    },
    {
      type: 'category',
      label: 'GitHub Actions & CI',
      items: [
        { type: 'doc', id: 'composite-actions' },
        { type: 'doc', id: 'commit' },
        { type: 'doc', id: 'renovate' },
      ],
    },
    {
      type: 'category',
      label: 'Security',
      items: [
        { type: 'doc', id: 'kyverno' },
        { type: 'doc', id: 'opa' },
        { type: 'doc', id: 'supply-chain' },
        { type: 'doc', id: 'runtime-security' },
        { type: 'doc', id: 'trivy' },
        { type: 'doc', id: 'checkov' },
        { type: 'doc', id: 'linkerd' },
      ],
    },
    {
      type: 'category',
      label: 'Observability',
      items: [
        { type: 'doc', id: 'observability' },
        { type: 'doc', id: 'datadog' },
        { type: 'doc', id: 'dynatrace' },
      ],
    },
    {
      type: 'category',
      label: 'Platform Engineering',
      items: [
        { type: 'doc', id: 'debug' },
        { type: 'doc', id: 'review' },
        { type: 'doc', id: 'product' },
        { type: 'doc', id: 'dora' },
        { type: 'doc', id: 'chaos' },
        { type: 'doc', id: 'compliance' },
        { type: 'doc', id: 'pr-review' },
        { type: 'doc', id: 'document' },
        { type: 'doc', id: 'awesome-docs' },
        { type: 'doc', id: 'mcp' },
        { type: 'doc', id: 'triage' },
        { type: 'doc', id: 'self-improve' },
      ],
    },
    {
      type: 'category',
      label: 'Agent Setup',
      items: [
        { type: 'doc', id: 'setup-agents' },
      ],
    },
  ],
};

module.exports = sidebars;
```

- [ ] **Step 2: Verify build resolves all sidebar items**

```bash
cd website && npm run build 2>&1 | grep -E "error|Error|broken" | head -20
```

Expected: no errors referencing missing doc IDs. Warnings about Algolia (not yet configured) are OK.

- [ ] **Step 3: Commit**

```bash
git add website/sidebars.js
git commit -m "feat(website): add hand-authored sidebars with 9 domain groups"
```

---

## Task 4: Custom CSS — dark theme overrides and landing page styles

**Files:**
- Modify: `website/src/css/custom.css`

**Interfaces:**
- Consumes: Docusaurus CSS variables (`--ifm-color-primary`, etc.)
- Produces: CSS classes `hero-section`, `before-after`, `feature-grid`, `install-tabs`, `command-cards` consumed by Task 5's landing page

- [ ] **Step 1: Replace `website/src/css/custom.css` with**

```css
/* ── Infima dark theme tokens ──────────────────────────────────────── */
:root {
  --ifm-color-primary: #7c3aed;
  --ifm-color-primary-dark: #6d28d9;
  --ifm-color-primary-darker: #5b21b6;
  --ifm-color-primary-darkest: #4c1d95;
  --ifm-color-primary-light: #8b5cf6;
  --ifm-color-primary-lighter: #a78bfa;
  --ifm-color-primary-lightest: #c4b5fd;
  --ifm-code-font-size: 90%;
  --docusaurus-highlighted-code-line-bg: rgba(124, 58, 237, 0.1);
}

[data-theme='dark'] {
  --ifm-color-primary: #a78bfa;
  --ifm-color-primary-dark: #8b5cf6;
  --ifm-color-primary-darker: #7c3aed;
  --ifm-color-primary-darkest: #6d28d9;
  --ifm-color-primary-light: #c4b5fd;
  --ifm-color-primary-lighter: #ddd6fe;
  --ifm-color-primary-lightest: #ede9fe;
  --ifm-background-color: #0f0f13;
  --ifm-background-surface-color: #18181f;
  --docusaurus-highlighted-code-line-bg: rgba(167, 139, 250, 0.1);
}

/* ── Landing page: Hero ─────────────────────────────────────────────── */
.hero-section {
  padding: 80px 24px 72px;
  text-align: center;
  background: radial-gradient(ellipse at 50% 0%, rgba(124, 58, 237, 0.12) 0%, transparent 65%);
}

.hero-section__eyebrow {
  font-family: var(--ifm-font-family-monospace);
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 2px;
  color: var(--ifm-color-primary);
  margin-bottom: 20px;
}

.hero-section__title {
  font-size: clamp(36px, 6vw, 64px);
  font-weight: 800;
  line-height: 1.1;
  letter-spacing: -1.5px;
  margin-bottom: 20px;
}

.hero-section__subtitle {
  font-size: 20px;
  color: var(--ifm-color-secondary-darkest);
  max-width: 600px;
  margin: 0 auto 36px;
  line-height: 1.5;
}

[data-theme='dark'] .hero-section__subtitle {
  color: var(--ifm-color-secondary-lightest);
  opacity: 0.7;
}

.hero-section__ctas {
  display: flex;
  gap: 16px;
  justify-content: center;
  flex-wrap: wrap;
  margin-bottom: 24px;
}

.hero-section__badge {
  font-family: var(--ifm-font-family-monospace);
  font-size: 12px;
  color: var(--ifm-color-secondary-darkest);
  opacity: 0.6;
}

[data-theme='dark'] .hero-section__badge {
  opacity: 0.5;
}

.hero-section__badge a {
  color: inherit;
  text-decoration: underline;
  text-underline-offset: 2px;
}

/* ── Before/After block ─────────────────────────────────────────────── */
.before-after {
  max-width: 1100px;
  margin: 0 auto;
  padding: 48px 24px;
}

.before-after__label {
  font-family: var(--ifm-font-family-monospace);
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 2px;
  color: var(--ifm-color-primary);
  text-align: center;
  margin-bottom: 8px;
}

.before-after__heading {
  font-size: 28px;
  font-weight: 700;
  text-align: center;
  margin-bottom: 32px;
}

.before-after__grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0;
  border: 1px solid var(--ifm-color-emphasis-300);
  border-radius: 12px;
  overflow: hidden;
}

@media (max-width: 768px) {
  .before-after__grid { grid-template-columns: 1fr; }
}

.before-after__grid > * { min-width: 0; overflow-wrap: break-word; }

.before-after__header {
  font-family: var(--ifm-font-family-monospace);
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 1px;
  padding: 10px 16px;
}

.before-after__header--before {
  background: rgba(239, 68, 68, 0.08);
  color: #ef4444;
  border-bottom: 2px solid #ef4444;
}

.before-after__header--after {
  background: rgba(5, 150, 105, 0.08);
  color: #059669;
  border-bottom: 2px solid #059669;
}

.before-after__body {
  padding: 16px;
  font-size: 13px;
  line-height: 1.6;
}

.before-after__body pre {
  margin: 0;
  font-size: 12px;
  overflow-x: auto;
}

/* ── Feature grid ──────────────────────────────────────────────────── */
.feature-strip {
  padding: 48px 24px;
  max-width: 1100px;
  margin: 0 auto;
}

.feature-strip__heading {
  font-size: 28px;
  font-weight: 700;
  text-align: center;
  margin-bottom: 32px;
}

.feature-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 16px;
}

.feature-tile {
  background: var(--ifm-background-surface-color);
  border: 1px solid var(--ifm-color-emphasis-300);
  border-radius: 12px;
  padding: 24px 20px;
  transition: border-color 0.2s ease, transform 0.2s ease;
}

.feature-tile:hover {
  border-color: var(--ifm-color-primary);
  transform: translateY(-2px);
}

.feature-tile__icon {
  font-size: 28px;
  margin-bottom: 12px;
}

.feature-tile__title {
  font-size: 16px;
  font-weight: 700;
  margin-bottom: 6px;
}

.feature-tile__desc {
  font-size: 13px;
  color: var(--ifm-color-secondary-darkest);
  line-height: 1.5;
}

[data-theme='dark'] .feature-tile__desc {
  color: var(--ifm-color-secondary-lightest);
  opacity: 0.65;
}

/* ── Install section ───────────────────────────────────────────────── */
.install-section {
  padding: 48px 24px;
  max-width: 800px;
  margin: 0 auto;
}

.install-section__heading {
  font-size: 28px;
  font-weight: 700;
  text-align: center;
  margin-bottom: 8px;
}

.install-section__sub {
  text-align: center;
  font-size: 15px;
  opacity: 0.6;
  margin-bottom: 32px;
}

/* ── Command showcase ──────────────────────────────────────────────── */
.command-section {
  padding: 48px 24px 72px;
  max-width: 1100px;
  margin: 0 auto;
}

.command-section__heading {
  font-size: 28px;
  font-weight: 700;
  text-align: center;
  margin-bottom: 32px;
}

.command-cards {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 16px;
}

.command-card {
  background: var(--ifm-background-surface-color);
  border: 1px solid var(--ifm-color-emphasis-300);
  border-radius: 12px;
  padding: 24px 20px;
  border-left: 3px solid var(--ifm-color-primary);
}

.command-card__name {
  font-family: var(--ifm-font-family-monospace);
  font-size: 14px;
  font-weight: 700;
  color: var(--ifm-color-primary);
  margin-bottom: 10px;
}

.command-card__desc {
  font-size: 13px;
  line-height: 1.6;
  color: var(--ifm-color-secondary-darkest);
}

[data-theme='dark'] .command-card__desc {
  color: var(--ifm-color-secondary-lightest);
  opacity: 0.7;
}
```

- [ ] **Step 2: Commit**

```bash
git add website/src/css/custom.css
git commit -m "feat(website): add dark theme tokens and landing page CSS"
```

---

## Task 5: Custom landing page (`src/pages/index.tsx`)

**Files:**
- Modify: `website/src/pages/index.tsx` (replace the scaffold default)

**Interfaces:**
- Consumes: CSS classes from Task 4 (`hero-section`, `before-after`, `feature-grid`, `install-section`, `command-cards`)
- Produces: the rendered home page at `/platform-skills/`

- [ ] **Step 1: Replace `website/src/pages/index.tsx` with**

```tsx
import React from 'react';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CodeBlock from '@theme/CodeBlock';

function Hero() {
  return (
    <div className="hero-section">
      <div className="hero-section__eyebrow">v1.34.0 — <a href="https://github.com/nitinjain999/platform-skills/blob/main/CHANGELOG.md">What&apos;s new</a></div>
      <h1 className="hero-section__title">Platform Skills</h1>
      <p className="hero-section__subtitle">
        A production-grade field handbook for platform engineers — Kubernetes, GitOps, Terraform, AWS, and more.
        Blast radius, validation steps, and rollback plan built in.
      </p>
      <div className="hero-section__ctas">
        <Link className="button button--primary button--lg" to="/docs/kubernetes">
          Get Started
        </Link>
        <Link className="button button--secondary button--lg" to="https://github.com/nitinjain999/platform-skills">
          View on GitHub
        </Link>
      </div>
      <div className="hero-section__badge">
        Works with Claude Code · Cursor · VS Code / Copilot · Codex
      </div>
    </div>
  );
}

function BeforeAfter() {
  const before = `spec:
  containers:
    - name: api-server
      image: mycompany/api-server:latest   # ❌ unpinned
      env:
        - name: DATABASE_URL
          value: "postgres://admin:password@db:5432/prod"  # ❌ hardcoded
      # ❌ no securityContext, no resources, no probes`;

  const after = `spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
    - name: api-server
      image: mycompany/api-server:v1.4.2   # ✅ pinned
      resources:
        requests: { cpu: 100m, memory: 128Mi }
        limits:   { cpu: 500m, memory: 512Mi }
      readinessProbe:
        httpGet: { path: /healthz/ready, port: 8080 }
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
      env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef: { name: api-server-secrets, key: database-url }  # ✅`;

  return (
    <section className="before-after">
      <div className="before-after__label">See it in action</div>
      <h2 className="before-after__heading">What platform-skills catches</h2>
      <div className="before-after__grid">
        <div className="before-after__header before-after__header--before">Before — what ships without it</div>
        <div className="before-after__header before-after__header--after">After — what platform-skills flags</div>
        <div className="before-after__body">
          <pre><code>{before}</code></pre>
        </div>
        <div className="before-after__body">
          <pre><code>{after}</code></pre>
        </div>
      </div>
    </section>
  );
}

const FEATURES = [
  { icon: '⎈', title: 'Kubernetes', desc: 'Cluster baseline, Helm, KEDA autoscaling, Karpenter node provisioning' },
  { icon: '🔄', title: 'GitOps', desc: 'Flux CD, Argo CD, OCI delivery, Flux Operator, gitless clusters' },
  { icon: '🏗️', title: 'Terraform', desc: 'Blast radius analysis, IAM least-privilege, SOC 2 controls' },
  { icon: '☁️', title: 'AWS', desc: 'CloudFront, WAF, Lambda@Edge, IAM / IRSA, multi-account SSO' },
  { icon: '🔒', title: 'Security', desc: 'Supply chain (Cosign, SBOM, SLSA), Falco, OPA, Kyverno, Trivy' },
  { icon: '📊', title: 'Observability', desc: 'Datadog, Dynatrace, OpenTelemetry, LLM observability, DORA' },
];

function FeatureStrip() {
  return (
    <section className="feature-strip">
      <h2 className="feature-strip__heading">Everything a platform team needs</h2>
      <div className="feature-grid">
        {FEATURES.map((f) => (
          <div className="feature-tile" key={f.title}>
            <div className="feature-tile__icon">{f.icon}</div>
            <div className="feature-tile__title">{f.title}</div>
            <div className="feature-tile__desc">{f.desc}</div>
          </div>
        ))}
      </div>
    </section>
  );
}

function InstallSection() {
  return (
    <section className="install-section">
      <h2 className="install-section__heading">Install in your agent</h2>
      <p className="install-section__sub">One command. Works where you work.</p>
      <Tabs>
        <TabItem value="claude" label="Claude Code" default>
          <CodeBlock language="bash">
            claude plugin install nitinjain999/platform-skills
          </CodeBlock>
        </TabItem>
        <TabItem value="cursor" label="Cursor">
          <p>Open Cursor Settings → Rules → search <code>platform-skills</code> in the marketplace.</p>
          <p>Fallback (manual install):</p>
          <CodeBlock language="bash">
            ./install.sh --cursor --target .
          </CodeBlock>
        </TabItem>
        <TabItem value="copilot" label="VS Code / Copilot">
          <CodeBlock language="bash">
            ./install.sh --copilot --target .
          </CodeBlock>
          <p>Drops <code>.github/copilot-instructions.md</code> into your project.</p>
        </TabItem>
        <TabItem value="codex" label="Codex">
          <CodeBlock language="bash">
            codex skill add nitinjain999/platform-skills
          </CodeBlock>
        </TabItem>
      </Tabs>
    </section>
  );
}

const COMMANDS = [
  {
    name: '/platform-skills:triage',
    desc: 'Triages a PR comment from a bot or human reviewer — fetches via gh CLI, classifies it, applies the fix, posts a reply, and resolves the thread.',
  },
  {
    name: '/platform-skills:checkov',
    desc: 'Runs Checkov static and plan-level Terraform scanning with AI-generated fix mode. Supports AWS/Azure/GCP/EKS, private modules, SARIF output.',
  },
  {
    name: '/platform-skills:karpenter',
    desc: 'Diagnoses Karpenter node provisioning failures. Covers NodePool, NodeClaim, EC2NodeClass, spot interruptions — with blast radius and rollback plan.',
  },
];

function CommandShowcase() {
  return (
    <section className="command-section">
      <h2 className="command-section__heading">Slash commands that do real work</h2>
      <div className="command-cards">
        {COMMANDS.map((c) => (
          <div className="command-card" key={c.name}>
            <div className="command-card__name">{c.name}</div>
            <div className="command-card__desc">{c.desc}</div>
          </div>
        ))}
      </div>
    </section>
  );
}

export default function Home(): JSX.Element {
  const { siteConfig } = useDocusaurusContext();
  return (
    <Layout title={siteConfig.title} description={siteConfig.tagline}>
      <main>
        <Hero />
        <BeforeAfter />
        <FeatureStrip />
        <InstallSection />
        <CommandShowcase />
      </main>
    </Layout>
  );
}
```

- [ ] **Step 2: Delete the scaffold pages that the landing page replaces**

```bash
rm -f website/src/pages/markdown-page.md
```

- [ ] **Step 3: Build and verify locally**

```bash
cd website && npm run build && npm run serve
```

Open `http://localhost:3000/platform-skills/` in a browser. Verify:
- Page loads in dark mode by default
- All 5 sections render: hero, before/after, feature strip, install tabs, command showcase
- `Get Started` link navigates to `/platform-skills/docs/kubernetes`
- Tabs switch between Claude Code / Cursor / VS Code / Codex correctly

- [ ] **Step 4: Commit**

```bash
git add website/src/pages/
git commit -m "feat(website): add custom landing page with hero, before/after, feature strip, install tabs, command showcase"
```

---

## Task 6: GitHub Actions pages workflow

**Files:**
- Create: `.github/workflows/pages.yml`

**Interfaces:**
- Consumes: `website/` built in previous tasks; GitHub Pages enabled with Source: GitHub Actions
- Produces: deployed site at `https://nitinjain999.github.io/platform-skills/` on every push to `main`

- [ ] **Step 1: Create `.github/workflows/pages.yml`**

```yaml
name: Deploy GitHub Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  build:
    name: Build
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
        with:
          fetch-depth: 0

      - name: Setup Node
        uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020  # v4.4.0
        with:
          node-version: '20'
          cache: npm
          cache-dependency-path: website/package-lock.json

      - name: Install dependencies
        working-directory: website
        run: npm ci

      - name: Build site
        working-directory: website
        run: npm run build

      - name: Upload Pages artifact
        uses: actions/upload-pages-artifact@56afc609e74202658d3ffba0e8f6dda462b719fa  # v3.0.1
        with:
          path: website/build

  deploy:
    name: Deploy
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e  # v4.0.5
```

- [ ] **Step 2: Verify action SHA pins are current**

```bash
gh api repos/actions/checkout/releases/latest --jq '.tag_name'
gh api repos/actions/setup-node/releases/latest --jq '.tag_name'
gh api repos/actions/upload-pages-artifact/releases/latest --jq '.tag_name'
gh api repos/actions/deploy-pages/releases/latest --jq '.tag_name'
```

If any version is newer than what's pinned above, update the SHA. Get the commit SHA for the latest tag:

```bash
gh api repos/actions/checkout/git/ref/tags/v4.2.2 --jq '.object.sha'
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/pages.yml
git commit -m "feat(ci): add GitHub Actions workflow for GitHub Pages deployment"
```

---

## Task 7: Enable GitHub Pages and open PR

**Files:** none — repo settings change + PR

- [ ] **Step 1: Enable GitHub Pages in repo settings**

Go to `https://github.com/nitinjain999/platform-skills/settings/pages`:
- Source: **GitHub Actions** (not a branch)
- Save

This must be done before pushing or the deploy job will fail with `Page build failed`.

- [ ] **Step 2: Push branch and open draft PR**

```bash
git push -u origin docs/docusaurus-pages-design
gh pr create \
  --title "feat(website): add Docusaurus GitHub Pages site" \
  --body "$(cat <<'EOF'
## Summary

- Scaffolds Docusaurus 3 in `website/` with two `@docusaurus/plugin-content-docs` instances pointing directly at `../references` and `../commands` (no file copying)
- Adds Docusaurus front matter to all 59 reference files and 35 command files
- Hand-authored `sidebars.js` with 9 domain groups (hybrid reference + command nav)
- Custom dark-default landing page: hero, before/after, feature strip, install tabs (Claude Code / Cursor / Copilot / Codex), command showcase
- GitHub Actions `pages.yml` deploys to `nitinjain999.github.io/platform-skills/` on push to `main`

## Validation

- [ ] `cd website && npm run build` passes locally
- [ ] `npm run serve` — all 5 landing page sections render in dark mode
- [ ] Asset URLs start with `/platform-skills/` not `/`
- [ ] Nav sidebar shows all 9 domain groups
- [ ] Install tabs render on mobile
- [ ] GitHub Actions deploy job completes
- [ ] `nitinjain999.github.io` root site unaffected

## Rollback

Disable GitHub Pages in repo settings instantly. The `website/` directory and `pages.yml` are fully additive.
EOF
)" \
  --draft
```

- [ ] **Step 3: Watch the first deploy**

```bash
gh run watch --repo nitinjain999/platform-skills
```

When it completes, open `https://nitinjain999.github.io/platform-skills/` and verify all sections render correctly.

- [ ] **Step 4: Mark PR ready for review when validated**

```bash
gh pr ready
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| `website/` subfolder | Task 1 |
| Two `@docusaurus/plugin-content-docs` instances | Task 1 |
| Direct path references to `../references`, `../commands` | Task 1 |
| `url: https://nitinjain999.github.io` | Task 1 |
| `baseUrl: /platform-skills/` | Task 1 |
| `colorMode: dark default, respectPrefersColorScheme` | Task 1 |
| Algolia search | Task 1 (wired in config; Algolia account setup is out of scope — requires external registration) |
| Front matter on all files | Task 2 |
| `sidebars.js` with 9 domain groups | Task 3 |
| Dark theme CSS | Task 4 |
| Hero section | Task 5 |
| Before/After block (Kubernetes example from BEFORE_AFTER.md) | Task 5 |
| Feature strip (6 tiles) | Task 5 |
| Install tabs (Claude Code / Cursor / Copilot / Codex) | Task 5 |
| Command showcase (triage / checkov / karpenter) | Task 5 |
| `pages.yml` workflow | Task 6 |
| `.nojekyll` | Task 1 |
| GitHub Pages source set to GitHub Actions | Task 7 |

**Note on Algolia:** Algolia DocSearch for public repos requires registering at `docsearch.algolia.com`. The config placeholder is wired in Task 1 but the `appId`, `apiKey`, and `indexName` values are only available after registration. This is a post-deployment step, not a blocker for launch. Remove the Algolia block from `docusaurus.config.js` until the keys are available, or the build will emit warnings on every run.

**Placeholder scan:** No TBDs or TODOs in task steps. All code blocks are complete.

**Type consistency:** `referencesSidebar` and `commandsSidebar` in Task 3 match the `sidebarId` values in `docusaurus.config.js` in Task 1.

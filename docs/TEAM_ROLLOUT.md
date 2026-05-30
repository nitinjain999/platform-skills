# Team Rollout Guide

How to roll out platform-skills across your team's repositories — from a single repo to your entire organisation.

## Prerequisites

- `git` installed
- Access to the target repositories
- One of: Claude Code, Codex CLI, Cursor, or GitHub Copilot

---

## Tier 1: 10 repos — Manual install (30 minutes)

The fastest path. Run the installer once per repo, per tool.

### Step 1: Clone platform-skills once

```bash
git clone https://github.com/nitinjain999/platform-skills.git ~/platform-skills
cd ~/platform-skills
```

### Step 2: Install into each target repo

Pick your tool:

```bash
# Claude Code — interactive plugin workflows and slash commands
claude plugin marketplace add https://github.com/nitinjain999/platform-skills
claude plugin install platform-skills

# Codex — skill invocation with $platform-skills
./install.sh --codex

# Cursor — project rules for Chat and Agent
./install.sh --cursor --target ../your-repo

# GitHub Copilot — instructions committed to the repo
./install.sh --copilot --target ../your-repo
```

### Step 3: Verify installation

```bash
# Claude Code
claude plugin list | grep platform-skills

# Codex
codex "list skills" | grep platform-skills

# Cursor — check that rules file exists
ls your-repo/.cursor/rules/platform-skills.mdc

# Copilot — check that instructions file exists
ls your-repo/.github/copilot-instructions.md | xargs grep -l "platform-skills"
```

### Step 4: First prompt to validate

Paste this into your tool of choice in the context of a real repo file:

```text
Use $platform-skills to review the files I changed for production readiness.
Focus on ownership, blast radius, validation, rollback, and security defaults.
```

---

## Tier 2: 100 repos — GitHub Actions automation (1 hour setup)

A GitHub Actions workflow that runs `install.sh` across a list of repositories via a matrix strategy. One PR per target repo.

### Step 1: Create the dispatch workflow in your central tooling repo

```yaml
# .github/workflows/rollout-platform-skills.yml
name: Rollout platform-skills

on:
  workflow_dispatch:
    inputs:
      tool:
        description: "Tool to install (cursor | copilot | codex)"
        required: true
        default: cursor
      repos:
        description: "Comma-separated list of owner/repo"
        required: true

jobs:
  rollout:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    strategy:
      matrix:
        repo: ${{ fromJson(format('["{0}"]', replace(github.event.inputs.repos, ',', '","'))) }}
      fail-fast: false
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
        with:
          repository: nitinjain999/platform-skills
          path: platform-skills

      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
        with:
          repository: ${{ matrix.repo }}
          path: target
          token: ${{ secrets.ROLLOUT_TOKEN }}

      - name: Install platform-skills
        run: |
          cd platform-skills
          ./install.sh --${{ github.event.inputs.tool }} --target ../target

      - name: Open PR
        uses: peter-evans/create-pull-request@5e914681574cf53f24b88ede31338b00d2b09b78  # v7.0.5
        with:
          path: target
          token: ${{ secrets.ROLLOUT_TOKEN }}
          commit-message: "feat: add platform-skills ${{ github.event.inputs.tool }} integration"
          branch: "platform-skills/rollout-${{ github.event.inputs.tool }}"
          title: "feat: add platform-skills for ${{ github.event.inputs.tool }}"
          body: |
            Adds platform-skills guidance for ${{ github.event.inputs.tool }}.

            **What this does:** Gives ${{ github.event.inputs.tool }} access to platform engineering
            patterns for Kubernetes, Terraform, Flux, GitHub Actions, AWS, and more.

            **Try it:** Paste a prompt from [PROMPTS.md](https://github.com/nitinjain999/platform-skills/blob/main/PROMPTS.md)
            into ${{ github.event.inputs.tool }} while reviewing any platform file.

            **Rollback:** Delete `.cursor/rules/platform-skills.mdc` (or equivalent) and close this PR.
```

### Step 2: Create a fine-grained PAT

Create a GitHub fine-grained Personal Access Token scoped to only the target repositories with **Contents** (read/write) and **Pull requests** (read/write) permissions. A classic PAT with `repo` scope is overly broad and grants unnecessary access across all your repositories.

Store it as secret `ROLLOUT_TOKEN` in your central tooling repo.

### Step 3: Trigger the rollout

```bash
gh workflow run rollout-platform-skills.yml \
  --field tool=cursor \
  --field repos="org/repo-1,org/repo-2,org/repo-3"
```

### Step 4: Merge the PRs

Each target repo gets one PR. Review and merge. To track status:

```bash
gh pr list --search "platform-skills rollout" --state open
```

---

## Tier 3: 1000 repos — Policy-as-code (1 day setup)

At this scale, individual PRs are impractical. Use your existing infrastructure-as-code and repository management tooling.

### Option A: GitHub Copilot — central organisation policy

Add platform-skills instructions to your organisation's default Copilot instructions. All repos in the org pick them up automatically.

1. Go to **Organisation Settings → Copilot → Policies**
2. Add the contents of `platform-skills/.github/copilot-instructions.md` to the organisation-level instructions
3. All repos in the org now have platform-skills guidance in Copilot Chat

### Option B: Cursor — shared rules via template repository

1. Create a template repository in your org: `org/platform-cursor-rules`
2. Copy `platform-skills/.cursor/` into it
3. Configure your org's repository creation workflow to clone from this template
4. Existing repos: run the Tier 2 matrix workflow with `--tool cursor` across all repos

### Option C: Repository management tool (Terraform, Pulumi, Backstage)

If you manage repos as code, add the platform-skills install to your repo template:

```hcl
# Terraform example using GitHub provider
resource "github_repository_file" "platform_skills_copilot" {
  for_each = toset(var.target_repos)

  repository = each.value
  branch     = "main"
  file       = ".github/copilot-instructions.md"
  content    = file("${path.module}/platform-skills/.github/copilot-instructions.md")
  commit_message = "feat: add platform-skills copilot instructions"
}
```

### Measuring adoption

```bash
# Count repos with platform-skills installed (Copilot)
gh search code "platform-skills" --filename copilot-instructions.md \
  --owner your-org --json repository | jq length

# Count repos with Cursor rules
gh search code "platform-skills" --filename "*.mdc" \
  --owner your-org --json repository | jq length
```

---

## Keeping platform-skills up to date

```bash
# Claude Code plugin — update to latest
claude plugin update platform-skills

# Cursor/Copilot — re-run install.sh from a fresh clone
git -C ~/platform-skills pull
cd ~/platform-skills && ./install.sh --cursor --target ../your-repo
```

For the Tier 2 matrix approach, re-trigger the workflow after each platform-skills release.

---

## Getting help

- [PROMPTS.md](../PROMPTS.md) — copy-paste prompts for every team
- [INSTALLATION.md](../INSTALLATION.md) — detailed install options
- [GitHub Issues](https://github.com/nitinjain999/platform-skills/issues) — report problems or gaps

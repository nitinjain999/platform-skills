---
name: composite-actions
description: Generate, review, secure, and test composite GitHub Actions following best practices — full repo scaffold, interview-driven generation, PR creation on existing repos, SHA pinning, secrets-as-inputs, job summaries, and actionlint validation.
argument-hint: "[generate|review|secure|test] [action.yml path or description]"
---

# Composite Actions Command

Generate production-ready composite GitHub Actions or audit existing ones against best practices.

## Activation

```
/platform-skills:composite-actions generate    # interview → full repo scaffold → optional PR
/platform-skills:composite-actions review      # audit an existing action.yml
/platform-skills:composite-actions secure      # harden an action in place
/platform-skills:composite-actions test        # generate a test workflow + act commands
```

---

## Mode: generate

**Triggers:** generate, create, new action, scaffold, write action, build action

Run a guided interview, then generate a complete, production-ready composite action with all supporting files. If the target repo already exists, open a PR.

### Interview — ask these questions in order

**Step 1 — Purpose**
> What does this action do? Describe it in one or two sentences.
> *(e.g. "Build a Docker image and push it to GHCR using OIDC", "Send a Slack notification with build status and PR link")*

Derive the action name from the description (kebab-case, under 30 chars). Confirm with the user.

**Step 2 — Repo destination**
> Where should this action live?
> 1. **New dedicated repo** — best for shared/public actions (Marketplace-publishable)
> 2. **Existing repo** — internal action, placed under `.github/actions/<name>/` or `actions/<name>/`

If **existing repo**: ask for `owner/repo`. Verify it exists with `gh repo view owner/repo`. Then ask:
> Which subdirectory? (default: `.github/actions/<action-name>`)

If the repo exists and is accessible, the action will be created on a branch and a PR will be opened automatically.

**Step 3 — Pinning strategy**
> How should external actions be pinned?
> 1. **SHA pinning** *(recommended — supply chain secure, immutable)*
> 2. **Semver floating tag** *(e.g. `@v4` — easier to maintain, lower security)*

Resolve SHAs for all external actions used via `gh api repos/{owner}/{repo}/git/refs/tags/{tag}` if SHA pinning is chosen.

**Step 4 — Inputs**
> What inputs does this action need? For each input, collect:
> - Name (snake_case)
> - Type: `string` / `boolean` / `choice`
> - Required or optional?
> - If optional: default value
> - **Is it a secret?** (webhook URL, kubeconfig, token, password, API key)

List all inputs in a table and confirm before proceeding.

**Step 5 — Outputs**
> What values should this action expose as outputs? For each:
> - Name (snake_case)
> - Description (one sentence)

**Step 6 — Cloud credentials**
> Does this action need cloud credentials?
> 1. AWS via OIDC (no long-lived keys — `id-token: write` required)
> 2. Azure via OIDC
> 3. Both
> 4. Neither

**Step 7 — Notifications and PR comments**
> Should this action send notifications or post PR comments?
> 1. Slack webhook notification
> 2. GitHub PR comment (requires `pull-requests: write`)
> 3. Both
> 4. Neither

**Step 8 — Job summary**
> Should this action write a job summary visible in the Actions UI?
> (Recommended: yes — adds a Markdown summary table with inputs, outputs, and status)

**Step 9 — Confirm and generate**

Show the user a summary of what will be generated:

```
Action: <name>
Description: <description>
Destination: <new repo | owner/repo/.github/actions/name>
Pinning: <SHA | semver>
Inputs: <count> (<N> are secrets)
Outputs: <count>
Cloud: <AWS OIDC | Azure OIDC | none>
Notifications: <Slack | PR comment | none>
Job summary: yes/no

Files to generate:
  action.yml
  README.md
  CHANGELOG.md
  .gitignore
  scripts/<script>.sh          (if logic warrants external scripts)
  .github/dependabot.yml
  .github/workflows/test-action.yml
  .github/workflows/release.yml
```

Ask for confirmation before generating.

### Generated file contents

#### action.yml

Generate with:
- `name`, `description`, `author` filled from the interview
- All inputs from Step 4, with `description:` noting which are secrets
- All outputs from Step 5
- A validation step as the **first step** — validates all required inputs and enum constraints
- Log grouping (`::group::` / `::endgroup::`) around each logical phase
- All secrets passed through `env:` blocks — never `${{ inputs.secret }}` in `run:`
- `::add-mask::` on every secret value immediately after it is read
- `${{ github.action_path }}` for all file references
- `shell: bash` on every `run:` step
- All external `uses:` pinned per the chosen strategy
- `$GITHUB_STEP_SUMMARY` written in a final `if: always()` step
- `timeout-minutes:` on every network-bound step
- `branding:` block with an appropriate icon and color

#### README.md

Generate an awesome-docs-compatible README with:

```markdown
# <action-name>

> <one-line description>

<!-- To add animated diagrams to this README, run: /platform-skills:awesome-docs generate -->

## Architecture

*(Shows where this action fits in a CI/CD pipeline — add diagram with `/platform-skills:awesome-docs generate`)*

## Quick start

\`\`\`yaml
- uses: <owner>/<repo>@v1
  with:
    <required inputs with example values>
\`\`\`

## Inputs

| Input | Type | Required | Secret | Default | Description |
|---|---|---|---|---|---|

## Outputs

| Output | Description |
|---|---|

## Variables and secrets

Explain which inputs are secrets and how to wire them from the caller:

\`\`\`yaml
- uses: <owner>/<repo>@v1
  with:
    image_name: my-service         # plain variable — safe to hardcode
    webhook_url: ${{ secrets.SLACK_WEBHOOK_URL }}   # secret — must come from secrets store
\`\`\`

## Permissions

\`\`\`yaml
permissions:
  <minimum required permissions>
\`\`\`

## Idempotency

<Is it safe to re-run? What happens on a second run?>

## Concurrency (recommended)

\`\`\`yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: <true for build/validate, false for deploy/release>
\`\`\`

## Full example

\`\`\`yaml
<complete caller workflow showing all inputs>
\`\`\`

## Changelog

See [CHANGELOG.md](CHANGELOG.md)
```

#### .github/dependabot.yml

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
    commit-message:
      prefix: "chore(deps)"
    labels:
      - "dependencies"
```

#### .github/workflows/test-action.yml

A test workflow that:
- Triggers on `push` and `pull_request` paths matching the action directory
- Calls the action using a local path reference (`./` or `./.github/actions/<name>`)
- Runs a matrix covering all optional inputs
- Verifies all outputs with assertions
- Uses `act` instructions in a comment header

#### .github/workflows/release.yml

- Triggers on `push` to tags matching `v[0-9]+.[0-9]+.[0-9]+`
- Validates with `actionlint`
- Updates the floating major version tag
- Creates a GitHub release with auto-generated notes

### PR creation (existing repo)

After generating all files:

```bash
# Clone the target repo
gh repo clone owner/repo /tmp/action-scaffold

# Create feature branch
git -C /tmp/action-scaffold checkout -b feat/add-<action-name>-composite-action

# Write all generated files into the appropriate subdirectory

# Commit
git -C /tmp/action-scaffold add .github/actions/<name>/
git -C /tmp/action-scaffold commit -m "feat(actions): add <action-name> composite action"

# Push
git -C /tmp/action-scaffold push -u origin feat/add-<action-name>-composite-action

# Open PR
gh pr create \
  --repo owner/repo \
  --title "feat(actions): add <action-name> composite action" \
  --body "$(cat <<'EOF'
## Summary

- Adds `<action-name>` composite action to `.github/actions/<name>/`
- Inputs: <list>
- Outputs: <list>
- Pinning: <SHA | semver>
- Secrets: <list of secret inputs>

## Test plan

- [ ] Test workflow passes on this branch
- [ ] Matrix covers all input combinations
- [ ] `actionlint` passes
- [ ] Tested locally with `act`
- [ ] README inputs/outputs table reviewed
- [ ] Secret inputs confirmed to use `env:` isolation

## Usage

\`\`\`yaml
- uses: owner/repo/.github/actions/<name>@<sha>
  with:
    <example inputs>
\`\`\`
EOF
)"
```

After PR creation, output:
> **PR opened:** `<PR URL>`
>
> Run `/platform-skills:awesome-docs generate` on the README to add architecture flow, lifecycle loop, and field carousel diagrams.

---

## Mode: review

**Triggers:** review, audit, check, lint my action, is this action safe

Audit an existing `action.yml` against the production checklist. Ask the user to paste or provide the path to the file.

Evaluate and report findings in three tiers:

**CRITICAL** (must fix before use)
- External `uses:` with mutable tag (`@v4`, `@main`, `@latest`) — supply chain risk
- `run:` step missing `shell:` — error on many runners
- `${{ inputs.* }}` interpolated directly in `run:` commands — injection risk
- Secrets accessed via `${{ secrets.* }}` inside the action — always empty, silent failure

**WARNING** (should fix)
- No input validation step
- Secret inputs not masked with `::add-mask::` after reading
- File references using `./` instead of `${{ github.action_path }}`
- Boolean inputs compared with `== true` instead of `== 'true'`
- No `$GITHUB_STEP_SUMMARY` written
- No `timeout-minutes` on network-bound steps
- No `id:` on steps that produce outputs

**INFORMATIONAL**
- No `branding:` block
- Missing `description:` on inputs or outputs
- No `dependabot.yml` for the actions ecosystem
- No test workflow present

Report format:
```
## Review: <action-name>

### CRITICAL (N findings)
❌ Line 14: `uses: actions/checkout@v4` — pin to SHA. Current SHA: <resolved SHA>
❌ Line 22: `run: deploy.sh --env ${{ inputs.environment }}` — injection risk. Use env: block.

### WARNING (N findings)
⚠️  No input validation step
⚠️  inputs.webhook_url not masked after reading

### INFORMATIONAL (N findings)
ℹ️  No branding: block — add icon and color for Marketplace

### Score: N/20 — <Poor | Fair | Good | Excellent>
```

---

## Mode: secure

**Triggers:** secure, harden, fix, pin actions, add shell

Fix an existing `action.yml` in place. Apply all CRITICAL and WARNING fixes automatically:

1. **Resolve SHA pins** — for each `uses:` with a mutable tag, call `gh api` to resolve to the current SHA and add the version as a comment
2. **Add `shell: bash`** — to every `run:` step missing it
3. **Move inputs to `env:` blocks** — replace `${{ inputs.* }}` in `run:` with env variable references
4. **Add `::add-mask::`** — on every step that reads a secret input
5. **Add input validation step** — inject a validation step as the first step if none exists
6. **Add job summary** — inject a `$GITHUB_STEP_SUMMARY` step if none exists

Report what was changed:
```
## Hardening applied to action.yml

✅ 3 actions pinned to SHA (actions/checkout, docker/setup-buildx-action, docker/build-push-action)
✅ shell: bash added to 2 steps
✅ inputs.webhook_url moved to env: block in step "Send notification"
✅ ::add-mask:: added for webhook_url
✅ Input validation step injected at position 1
✅ Job summary step injected (if: always())
```

---

## Mode: test

**Triggers:** test, generate test, write test workflow, act

Generate a complete test workflow for an existing composite action.

Ask:
1. Path to the `action.yml`
2. Which inputs have meaningful test variants (matrix)
3. Any secrets needed — provide placeholder names

Generate:
- `.github/workflows/test-<action-name>.yml` — triggers on PR + push for the action's directory
- Matrix covering all optional inputs
- Output assertion steps
- `act` commands with correct flags for local testing

Also output:
```bash
# Local test commands

# Default inputs
act -W .github/workflows/test-<action-name>.yml \
    -P ubuntu-latest=catthehacker/ubuntu:act-22.04

# With secrets
act -W .github/workflows/test-<action-name>.yml \
    -P ubuntu-latest=catthehacker/ubuntu:act-22.04 \
    --secret SLACK_WEBHOOK_URL=https://hooks.slack.com/test \
    --secret KUBECONFIG=<base64-encoded>

# Dry run
act -W .github/workflows/test-<action-name>.yml --dry-run
```

---

## Mode: migrate

**Triggers:** migrate, extract, refactor workflows, consolidate steps, duplicate steps

Detect repeated step blocks across workflow files and extract them into a composite action.

Ask the user for the directory containing workflow files (default: `.github/workflows/`), then:

1. **Scan for duplicates** — read all `*.yml` files and find step sequences that appear in 3 or more jobs
2. **Rank candidates** — sort by: (count × step-count); highest impact first
3. **Present candidates** — show the top 3 with:
   ```
   Candidate: setup-node-and-cache (appears in 5 workflows, 4 steps each = 20 step-lines saved)
   Steps:
     - uses: actions/checkout@...
     - uses: actions/setup-node@...
     - run: npm ci
     - run: npm run build
   ```
4. **Pick one** — ask the user which candidate to extract (or "all")
5. **Run the `generate` interview** — pre-fill answers from the detected steps; ask only what cannot be inferred (action name, outputs, pinning strategy)
6. **Generate the composite action** — write to `.github/actions/<name>/`
7. **Rewrite callers** — replace the extracted steps in each workflow with a single `uses:` call

Report:
```
## Migration complete

✅ Extracted 4 steps → .github/actions/setup-node-and-cache/action.yml
✅ Replaced in 5 workflows:
   - .github/workflows/ci.yml (steps 3–6)
   - .github/workflows/deploy.yml (steps 2–5)
   - .github/workflows/lint.yml (steps 1–4)
   - .github/workflows/test.yml (steps 3–6)
   - .github/workflows/release.yml (steps 4–7)

Lines saved: 20 step-lines across 5 files → 1 composite action call each
```

---

## Mode: publish

**Triggers:** publish, marketplace, submit to marketplace, list on marketplace

Walk through the GitHub Actions Marketplace publishing checklist and generate all required metadata.

### Step 1 — Verify prerequisites

Confirm each is met:
- [ ] `action.yml` in the **root** of the repository (not a subdirectory — Marketplace requires root placement)
- [ ] `name:` is unique on the Marketplace (search `https://github.com/marketplace?type=actions&query=<name>`)
- [ ] `description:` under 125 characters
- [ ] `author:` set (your GitHub username or org)
- [ ] `branding:` block present with `icon:` and `color:`
- [ ] `README.md` at root covers: what it does, inputs/outputs table, full example
- [ ] At least one release tag (`v1.0.0`)

### Step 2 — Generate Marketplace metadata

If `branding:` is missing, suggest 3 icon/color combinations based on the action's purpose:

```yaml
# For a build/push action:
branding:
  icon: 'box'
  color: 'blue'

# For a security scan:
branding:
  icon: 'shield'
  color: 'orange'

# For a notification action:
branding:
  icon: 'bell'
  color: 'green'
```

Valid Feather icons: `activity`, `alert-circle`, `archive`, `bell`, `box`, `check-circle`, `cloud`, `code`, `cpu`, `database`, `download`, `eye`, `file`, `flag`, `git-branch`, `globe`, `heart`, `home`, `key`, `layers`, `lock`, `mail`, `monitor`, `package`, `play`, `plus`, `refresh-cw`, `search`, `send`, `server`, `settings`, `shield`, `star`, `tag`, `terminal`, `tool`, `trash`, `upload`, `user`, `users`, `zap`

Valid colors: `white`, `yellow`, `blue`, `green`, `orange`, `red`, `purple`, `gray-dark`

### Step 3 — Release checklist

```bash
# Tag the release
git tag v1.0.0
git push origin v1.0.0

# Create floating major tag
git tag -f v1
git push origin v1 --force

# Verify release workflow ran (actionlint gate + SHA pinning check)
gh run list --workflow release.yml --limit 5
```

### Step 4 — Submit to Marketplace

Go to: `https://github.com/<owner>/<repo>/releases/new`

1. Set tag to `v1.0.0`
2. Check "Publish this Action to the GitHub Marketplace"
3. Review the category suggestion
4. Click "Publish release"

After publish, output:
```
## Marketplace listing

✅ Action published: https://github.com/marketplace/actions/<action-name>

Next steps:
- Add a Marketplace badge to README.md:
  [![GitHub Marketplace](https://img.shields.io/badge/marketplace-<name>-blue?logo=github)](https://github.com/marketplace/actions/<name>)
- Set up dependabot to auto-update your own pinned SHA when you release new versions
- Watch for usage feedback in the Discussions tab
```

---

## Reference

Full documentation: `references/composite-actions.md`

Examples:
- `examples/github-actions/composite-actions/docker-build-push/` — GHCR push, OIDC, multi-platform
- `examples/github-actions/composite-actions/notify-slack/` — Slack webhook, secrets flow
- `examples/github-actions/composite-actions/k8s-deploy/` — kubectl, kubeconfig secret
- `examples/github-actions/composite-actions/terraform-plan/` — Terraform plan, PR comment
- `examples/github-actions/composite-actions/security-scan/` — Trivy, severity gate, annotations
- `examples/github-actions/composite-actions/release-tag/` — semver bump, `$GITHUB_OUTPUT` chaining
- `examples/github-actions/composite-actions/pr-comment/` — `github-script`, token scoping
- `examples/github-actions/composite-actions/setup-env/` — multi-runtime (Node/Python/Go), tutorial baseline

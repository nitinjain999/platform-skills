---
name: github-actions
description: Design, review, secure, and debug GitHub Actions workflows — reusable workflows, OIDC federation, SHA pinning, token scoping, promotion orchestration, and CI failure diagnosis.
argument-hint: "[design|security|review|debug] [workflow file path or description]"
title: "GitHub Actions Command"
sidebar_label: "github-actions"
custom_edit_url: null
---

# GitHub Actions Command

Structured guidance for designing, hardening, reviewing, and debugging GitHub Actions workflows.

## Activation

```
/platform-skills:github-actions design    # reusable workflow or job graph design
/platform-skills:github-actions security  # OIDC, SHA pinning, token scoping, secrets hygiene
/platform-skills:github-actions review    # production-readiness checklist for an existing workflow
/platform-skills:github-actions debug     # diagnose a failing workflow or job
```

---

## Interactive Wizard (fires when no mode is provided)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. design    — reusable workflow, job graph, promotion pipeline
  2. security  — OIDC federation, SHA pinning, token scoping, secret hygiene
  3. review    — production-readiness checklist for an existing workflow file
  4. debug     — job failure, permission error, OIDC rejection, missing context

Enter 1–4 or mode name:
```

**Q2 — Context** (after mode selected):
- **design**: `Describe what the workflow should do — validate, build, promote, deploy?`
- **security**: `Paste the workflow file or describe the auth pattern you are using.`
- **review**: `Paste the workflow file or provide the path.`
- **debug**: `Paste the error output or describe the failure symptom.`

---

## Mode: design

**Triggers:** design, build workflow, create pipeline, reusable workflow, job graph, promote, deploy flow

Read `references/github-actions.md` before responding.

### Step 1 — Classify the workflow type

| Type | When to use |
|---|---|
| Reusable workflow (`workflow_call`) | Same job sequence needed across multiple repos or environments |
| Composite action | Same step sequence needed within job graphs — use `/platform-skills:composite-actions` |
| Standard workflow | One-off or repo-specific, not shared |

### Step 2 — Apply the canonical job pattern

Every workflow should follow this job order:

```
validate → build → [test] → promote → [deploy]
```

- `validate`: lint, format, policy gates, unit checks — fast, no credentials
- `build`: image or artifact packaging — OIDC to registry
- `promote`: update version pin or overlay in Git — triggers GitOps reconciler
- `deploy`: guarded apply only if not using GitOps

Keep jobs small and named by intent. If a job is hard to name, it is doing too much.

### Step 3 — Reusable workflow structure

```yaml
# .github/workflows/validate.yml — called by other workflows
on:
  workflow_call:
    inputs:
      environment:
        required: true
        type: string
        description: "Target environment (dev | staging | prod)"
    secrets:
      token:
        required: true

jobs:
  validate:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
        with:
          token: ${{ secrets.token }}
```

### Step 4 — Promotion orchestration

Prefer updating Git over imperative deploys:

```yaml
# promote job — updates the version pin in the GitOps repo
promote:
  needs: build
  runs-on: ubuntu-latest
  permissions:
    contents: write
  steps:
    - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
    - name: Update image tag
      env:
        NEW_TAG: ${{ needs.build.outputs.image_tag }}
      run: |
        sed -i "s|image:.*|image: ghcr.io/org/app:${NEW_TAG}|" \
          deploy/overlays/${{ inputs.environment }}/kustomization.yaml
        git config user.email "ci@org.com"
        git config user.name "CI"
        git commit -am "chore: promote app to ${NEW_TAG} in ${{ inputs.environment }}"
        git push
```

**Handoffs:**
- Extracting repeated steps → `/platform-skills:composite-actions`
- Terraform plan/apply in the workflow → `/platform-skills:terraform`
- GitOps reconciler that picks up the promotion commit → `/platform-skills:gitops`

---

## Mode: security

**Triggers:** OIDC, pin, SHA, token, permissions, secrets, secure, harden, federation

Read `references/github-actions.md` before responding.

### OIDC federation — AWS

```yaml
permissions:
  id-token: write    # required for OIDC token request
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@e3dd6a429d7300a6a4c196c26e071d42e0343502  # v4.0.2
    with:
      role-to-assume: arn:aws:iam::123456789012:role/github-actions-deploy
      aws-region: eu-north-1
```

IAM trust policy (scope to repo and branch):

```json
{
  "Condition": {
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:org/repo:ref:refs/heads/main"
    }
  }
}
```

### OIDC federation — Azure

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: azure/login@a65d910e8af852a8061c627c456678983e180302  # v2.2.0
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

### SHA pinning checklist

```bash
# Resolve a tag to its current commit SHA
gh api repos/{owner}/{repo}/git/refs/tags/{tag} \
  --jq '.object.sha'

# For actions that use a commit SHA directly (not a tag ref):
gh api repos/{owner}/{repo}/commits/{tag} --jq '.sha'
```

Add the version as a comment so reviewers can audit without resolving the SHA manually:

```yaml
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
```

### Token scoping — minimum permissions per job

| Job type | Permissions needed |
|---|---|
| Read-only checkout | `contents: read` |
| Push a commit | `contents: write` |
| Create or comment on PR | `pull-requests: write` |
| Publish packages | `packages: write` |
| OIDC token request | `id-token: write` |
| Read Issues | `issues: read` |

Set `permissions: {}` at the workflow level to deny all, then grant per-job:

```yaml
permissions: {}   # deny all at workflow level

jobs:
  build:
    permissions:
      contents: read
      id-token: write
      packages: write
```

### Secret hygiene

- Store secrets in GitHub Environments, not at repository level, for deployment secrets
- Never print secrets: avoid `echo $SECRET` in `run:` steps
- Mask dynamic secrets: `echo "::add-mask::${DYNAMIC_SECRET}"`
- Rotate long-lived tokens on a schedule; prefer OIDC to eliminate them
- Audit secret usage: `gh secret list` and `gh secret list --env <env>`

---

## Mode: review

**Triggers:** review, audit, checklist, is this workflow safe, production ready

Ask the user to paste the workflow file or provide the path. Then evaluate against:

**CRITICAL (must fix before merge)**

```
❌ External `uses:` with mutable tag (@v4, @main, @latest) — supply chain risk; pin to full SHA
❌ `permissions: write-all` or no permissions block — grants all scopes by default
❌ `${{ github.event.*.body }}` or PR title interpolated in run: — script injection risk
❌ Long-lived cloud credentials stored as secrets — replace with OIDC
❌ `pull_request_target` with checkout of the PR head — arbitrary code execution risk
```

**WARNING (should fix)**

```
⚠️  No concurrency group — parallel runs on same branch can conflict or double-deploy
⚠️  No timeout-minutes on jobs — a hung job blocks runners indefinitely
⚠️  Secrets passed to untrusted third-party actions — scope secrets to first-party or audited actions only
⚠️  Environment protection rules not used for production deploys
⚠️  No required status checks on the branch protection rule this workflow targets
```

**INFORMATIONAL**

```
ℹ️  No dependabot.yml for github-actions ecosystem — action versions will drift
ℹ️  Reusable workflow could replace copy-pasted job sequence
ℹ️  Job name does not describe intent clearly
```

Report format:

```
## Review: <workflow-name>

### CRITICAL (N findings)
❌ Line 12: uses: actions/checkout@v4 — pin to SHA. Current SHA: <sha>

### WARNING (N findings)
⚠️  No concurrency group defined

### INFORMATIONAL (N findings)
ℹ️  No dependabot.yml for the github-actions ecosystem

### Score: N/15 — Poor | Fair | Good | Excellent
```

---

## Mode: debug

**Triggers:** failing, error, permission denied, OIDC, 401, 403, missing context, debug, not working

Identify the failure layer first:

```
1. Syntax / parse error          → workflow YAML invalid
2. Permission / auth error       → token scoping, OIDC trust, secret missing
3. Missing context               → expression evaluates to empty, wrong event trigger
4. Action version mismatch       → SHA pinned to a version with a breaking change
5. Runner environment            → tool not available on runner image
6. Downstream service error      → cloud API, registry, or deploy target failing
```

### Diagnosis by error type

**`Resource not accessible by integration` / `403`**

```yaml
# Check the permissions block — add the missing scope
permissions:
  contents: write       # missing if you get 403 on git push
  pull-requests: write  # missing if you get 403 on PR comment
  id-token: write       # missing if OIDC token request fails
```

**OIDC rejection (`Not authorized to perform sts:AssumeRoleWithWebIdentity`)**

1. Confirm `id-token: write` is set on the job
2. Check the IAM trust policy `sub` condition matches the exact repo/branch/env
3. Confirm the workflow is running from the branch/environment specified in the condition
4. For environment-scoped trust: `repo:org/repo:environment:production` — job must use `environment: production`

```bash
# Decode the OIDC token to inspect claims (add a debug step temporarily)
- name: Inspect OIDC token claims
  run: |
    TOKEN=$(curl -sSfL -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com" | jq -r '.value')
    echo "${TOKEN}" | cut -d. -f2 | base64 -d 2>/dev/null | jq
```

**Expression evaluates to empty**

```yaml
# Workflow inputs are empty in non-workflow_call events
# Guard with:
- if: ${{ inputs.environment != '' }}
```

**`Context access might be invalid`**

Caused by accessing a context that does not exist for the triggering event (e.g. `github.event.pull_request` on a `push` event). Check which contexts are available for the trigger.

### Validation command

```bash
# Lint the workflow file locally before pushing
actionlint .github/workflows/<workflow>.yml

# Check recent run failures with full logs
gh run list --workflow <workflow>.yml --limit 10
gh run view <run-id> --log-failed
```

---

## Common mistakes

- **`pull_request_target` + PR head checkout** — runs with write permissions and access to secrets; combined with checkout of untrusted code this allows secret exfiltration. Never checkout `${{ github.event.pull_request.head.sha }}` in a `pull_request_target` workflow.
- **Mutable action tags** — `@v4` can be rewritten by the action author; a supply chain compromise silently executes attacker code. Always pin to SHA.
- **Over-scoped `GITHUB_TOKEN`** — default permissions can be broad depending on repo settings. Always set an explicit `permissions:` block.
- **Forgetting OIDC requires the job's environment to match the trust policy** — if the trust uses `environment:production`, the job must declare `environment: production` or the token request is rejected.
- **`workflow_dispatch` with no input validation** — inputs are free-text by default. Use `type: choice` for enum inputs and validate string inputs in the first step.

---

## Reference

Full guidance: `references/github-actions.md`

For composite action scaffolding and review: `/platform-skills:composite-actions`

Examples:
- `examples/github-actions/terraform-cicd.yml` — Terraform plan + apply with OIDC
- `examples/github-actions/container-build.yml` — Docker build + GHCR push
- `examples/github-actions/reusable-workflows/` — reusable workflow patterns

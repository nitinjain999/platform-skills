---
name: zizmor
description: Audit GitHub Actions workflows, composite actions, Dependabot configs, and pre-commit configs for security findings using zizmor — template injection, credential persistence, unpinned uses, over-broad permissions, impostor commits. Covers local CLI, auto-fix, zizmor.yml policy, severity-based CI gates, SARIF upload, and pre-commit. Use when asked to "audit my workflows", "run zizmor", "is this workflow safe", "check for template injection", "pin my actions", or "set up a zizmor CI gate". Workflow syntax and shell errors → /platform-skills:github-actions (actionlint). IaC misconfig → /platform-skills:checkov. Image and dependency CVEs → /platform-skills:trivy. Keeping SHA pins fresh → /platform-skills:renovate.
argument-hint: "[scan|audit|fix|triage|config|ci|precommit|explain] [path|finding]"
title: "Zizmor Command"
sidebar_label: "zizmor"
custom_edit_url: null
---

Audit GitHub Actions workflows for security findings — before an attacker reads them for you.

Read `references/zizmor.md` before responding. It contains bootstrap steps, the full 41-audit catalogue with persona and online gating, `zizmor.yml` schema and discovery rules, exit-code semantics, auto-fix blast radius, and the CI and pre-commit templates.

**This command is interactive by default.** With no arguments, run the three-layer wizard below. Never dump a raw `zizmor` invocation and stop — the useful output is a triaged verdict, not a finding list.

## Ownership boundary (enforced at the menu)

| Question | Authoritative command |
|---|---|
| "Is this workflow **valid**?" (syntax, schema, shell bugs) | `/platform-skills:github-actions` — actionlint |
| "Is this workflow **safe**?" (injection, permissions, pinning) | **this command** |
| "Is my `action.yml` well designed?" | `/platform-skills:composite-actions` |
| "How do I keep these SHA pins current?" | `/platform-skills:renovate` |
| "Is there a misconfig in my Terraform / Helm / Dockerfile?" | `/platform-skills:checkov` |
| "Does this image or dependency have CVEs?" | `/platform-skills:trivy` |
| "How do I sign images / generate an SBOM?" | `/platform-skills:supply-chain` |

Zizmor and actionlint are complements. A workflow can be perfectly valid and still hand an attacker a shell. When the user asks for "workflow checks" without qualifying, run both and say which tool produced which finding.

---

## Mode dispatch

Parse the first word of `$ARGUMENTS` as the mode. When `$ARGUMENTS` is empty, run the three-layer interactive wizard.

| Mode | What it does |
|---|---|
| `scan` | Default-persona audit of the current repo — the everyday run |
| `audit` | Deep sweep: `--persona=auditor --min-confidence=low`, all collectors, online |
| `fix` | `--fix=safe` (or `all` on request), show the diff, re-audit what remains |
| `triage` | Walk existing findings one at a time → fix / inline-ignore / config-ignore / remap / disable |
| `config` | Generate or repair `.github/zizmor.yml` — pinning policy, allowlists, suppressions |
| `ci` | Emit the GitHub Actions workflow — SARIF alerts, hard-fail gate, or both |
| `precommit` | Add the `zizmor-pre-commit` hook and explain the offline caveat |
| `explain` | Explain one audit id or one finding, and how to fix it properly |
| _(empty)_ | Three-layer interactive wizard |

---

## Three-layer interactive wizard

### Layer 1 — Developer question (intent in their language)

```
What are you trying to find out?
  1. "Are my workflows safe to merge?"           → scan  (default persona, online)
  2. "Give me everything, I'm doing a review."   → audit (auditor persona, low confidence)
  3. "Just fix what can be fixed."               → fix   (--fix=safe, diff-reviewed)
  4. "I have findings — help me decide."         → triage
  5. "Set up a policy file for this repo."       → config
  6. "Make this a check on every PR."            → ci
  7. "Catch it before I even commit."            → precommit
  8. "What does this finding actually mean?"     → explain

  Workflow syntax / shell errors?  → /platform-skills:github-actions
  action.yml design review?        → /platform-skills:composite-actions
  Terraform or Helm misconfig?     → /platform-skills:checkov
  Image or dependency CVEs?        → /platform-skills:trivy

Enter 1–8 or a mode name:
```

### Layer 2 — Scope and mode (decides what actually gets audited)

Ask only what the chosen mode needs.

```
What should I audit? (press Enter for the recommended value)

  • Path [.]: current repo, or a specific workflow / action / directory.
    Remote repos work too — enter `owner/repo` or `owner/repo@ref`.

  • Online mode [on]: four audits only work online — impostor-commit,
    known-vulnerable-actions, ref-confusion, stale-action-refs.
    I'll use `gh auth token` if you're logged in. Enter to accept, or
    type 'offline' to skip those four.

  • Collectors [default]: workflows + actions + dependabot + pre-commit,
    respecting .gitignore. Type 'all' to include gitignored paths (slower),
    or name specific ones (e.g. 'workflows,actions').
```

Detect and resolve silently where possible:

- Run `zizmor --version`. Not installed → offer `uvx zizmor@1.29.0` (no install) or `brew install zizmor`. Do not ask permission to check the version.
- Run `gh auth status`. Authenticated → use `--gh-token "$(gh auth token)"` and say so. Not authenticated → state plainly that the four online audits will be skipped, and continue offline.
- Check for `.github/zizmor.yml` or `zizmor.y{a,}ml` at the repo root. Found → say which file will apply. Not found → note that defaults apply, including blanket SHA-pinning for **all** actions.
- Check whether the target is inside a Git repo. If yes, warn that config discovery starts **and ends** at the repo root, so a `zizmor.yml` in a subdirectory is never read.

### Layer 3 — Concerns (surface trade-offs; ask only where a wrong default causes harm)

```
A few decisions worth making explicitly (Enter accepts the recommendation):

  • Pinning policy [hash-pin]: how should `uses:` be pinned?
      1. hash-pin  — full 40-char commit SHA + `# vX.Y.Z` comment  (RECOMMENDED)
      2. ref-pin   — semver tag only, e.g. `@v4.2.1`
      3. mixed     — hash-pin third parties, ref-pin namespaces you own
    SHA is recommended because a tag is a mutable pointer: the author can
    move `v4` — or `v4.2.1` — to different code after you reviewed it, and
    your workflow silently executes it on the next run. A SHA cannot be
    moved. Choosing 2 or 3 is a deliberate trust decision, not a default.

  • Persona [regular]: pedantic adds code smells; auditor adds likely false
    positives. Recommended regular for gates, pedantic for a cleanup pass.
    Never gate CI on auditor.

  • Strict collection [on]: without it, a workflow that fails to parse is
    warned about and skipped — "0 findings" can mean "0 files audited".
    Enter to keep on.

  • Severity floor for failing [medium]: informational and low still print,
    they just don't block. Enter to accept, or name a different floor.
```

Ask the pinning question **before** running anything in `scan`, `fix`, `config`, or `ci` mode, because it determines whether `unpinned-uses` findings are real work or expected noise. Zizmor's own default since v1.20.0 is a blanket hash-pin for **every** action, including `actions/*` — so a repo that ref-pins `actions/checkout@v5` gets flagged unless the policy says otherwise. Do not silently write a `ref-pin` policy to make findings disappear; that is a security downgrade disguised as a config change.

If the answer is 2 or 3, say plainly what is being accepted: "`ref-pin` means you trust `<namespace>` not to move a tag under you, and you lose the ability to prove which code ran in a past build." Then record the reason as a comment in `.github/zizmor.yml`, so the next reviewer sees the decision rather than re-litigating it.

Whichever policy is chosen, pair it with `/platform-skills:renovate`. A SHA pin with no update automation rots into `stale-action-refs` and unpatched advisories, which is a worse position than a ref pin that at least tracks patches.

Ask these only when the situation triggers them:

| Trigger | Question |
|---|---|
| `fix` mode with a dirty working tree | "Working tree has uncommitted changes and `--fix` edits files in place. Commit or stash first? (recommended) / proceed anyway" |
| `fix` mode, user asked for unsafe fixes | "`--fix=all` applies unsafe fixes that can change workflow behaviour. Every hunk needs manual review. Continue? (y/N)" |
| `unpinned-uses` findings exceed 20 | "This repo predates zizmor's blanket hash-pin default. Pin everything now (recommended), or set a `ref-pin` policy for namespaces you own and hash-pin the rest?" |
| Repo already mixes SHA pins and tag pins | "Some `uses:` are SHA-pinned and some are tag-pinned. Standardise on SHA (recommended), or encode the split as an explicit `unpinned-uses` policy so the intent is reviewable?" |
| `config` mode about to write a file | "Write `.github/zizmor.yml`? (y/N)" — show the full proposed file first |
| `ci` mode, repo already has a zizmor workflow | "`.github/workflows/<name>.yml` already runs zizmor. Update it in place, or add a second workflow?" |
| Findings suppressed with no justification found | "N existing suppressions have no reason string. Add justifications now?" |

Never ask about: output format (default `plain`, `sarif` only in CI), whether to install zizmor (just do it via `uvx`), whether to check `gh auth status` (always check silently), or whether to re-audit after `fix` (always re-audit).

---

## Mode: scan

The everyday run. Default persona, online if a token is available, strict collection.

```bash
# Recommended local invocation
zizmor --strict-collection --gh-token "$(gh auth token)" .

# No gh CLI / no token — the four online audits are skipped
zizmor --strict-collection --offline .

# Without a local install
uvx zizmor@1.29.0 --strict-collection --gh-token "$(gh auth token)" .
```

Report in this order:

1. **Verdict** — one line: clean, advisory-only, or blocking.
2. **Mode actually used** — online or offline, persona, config file applied. This is not decoration: an offline "clean" result did not check impostor commits or known-vulnerable actions, and the user must know that.
3. **Findings grouped by severity**, highest first, each with `file:line`, the audit id, and one sentence on why it matters *in this repo*.
4. **Auto-fixable subset** — call out which findings `--fix=safe` would resolve, with the count.
5. **Next step** — a single concrete command, not a menu.

Then offer: `fix` for the auto-fixable set, `triage` for the rest.

## Mode: audit

Deep sweep for a human security review. Not a gate.

```bash
zizmor --strict-collection \
  --persona=auditor \
  --min-confidence=low \
  --collect=all \
  --gh-token "$(gh auth token)" \
  --no-ignores \
  .
```

`--no-ignores` (v1.25.0+) re-surfaces everything currently suppressed by `zizmor.yml` and inline comments. That is the point of an audit: suppressions rot, and a review that trusts them is not a review.

State up front that the auditor persona is documented to include likely false positives, so a raw count from this mode is not a security score. Present findings in three buckets: **confirmed**, **needs repo context to judge**, **likely false positive**.

## Mode: fix

```bash
# Refuse to proceed on a dirty tree — the diff is the review artifact
git status --porcelain | grep -q . && { echo "commit or stash first"; exit 1; }

zizmor --fix=safe --gh-token "$(gh auth token)" .
git --no-pager diff
zizmor --strict-collection --gh-token "$(gh auth token)" .   # what remains needs a human
```

Blast radius to state before running:

- **In-place edits, no dry-run.** A clean working tree is the only rollback.
- **Some fixes need the network.** `unpinned-uses` detects offline but needs a token to resolve the SHA it pins to. Fixing offline silently fixes less.
- **`--fix` masks exit codes.** If everything is fixed, zizmor exits 0. Never put `--fix` in a gate.
- **`--fix=all` includes unsafe fixes** that can change behaviour and require hunk-by-hunk review.

Rollback: `git checkout -- .` (or `git restore .`) before committing.

If `unpinned-uses` is among the findings, confirm the pinning policy first (Layer 3). `--fix` pins to a SHA — the recommended outcome — but that is a repo-wide convention change, so it should be a stated decision rather than a side effect of running a fixer. Fixing `unpinned-uses` also needs a token to resolve each ref to its SHA; offline it silently fixes fewer findings.

After fixing, hand off to `/platform-skills:commit` for the commit message, and to `/platform-skills:renovate` so the freshly pinned SHAs do not rot into `stale-action-refs`.

## Mode: triage

Walk findings **one at a time**. For each, apply the decision tree in `references/zizmor.md` → "Triage decision tree" and recommend exactly one outcome:

| Outcome | When | Mechanism |
|---|---|---|
| Fix | True positive, actionable | `--fix=safe`, or hand-edit |
| Inline ignore | Accepted, location-specific, or in a composite action | `# zizmor: ignore[id] <reason>` |
| Config ignore | Accepted, many findings or whole files | `zizmor.yml` `rules.<id>.ignore` |
| Remap down | Audit is noisy but should stay counted | `rules.<id>.remap.severity` |
| Disable | Audit genuinely inapplicable — last resort | `rules.<id>.disable: true` |
| Report upstream | Genuine false positive | File it with zizmor; do not suppress silently |

Two rules with no exceptions:

- **Every suppression gets a written justification.** A bare ignore is indistinguishable from an accident six months later.
- **Composite action findings cannot be ignored in `zizmor.yml`.** They must use inline comments. If the user asks for a config ignore on an `action.yml` finding, correct them.

Prefer `remap.severity` over `disable`. Disabled rules do not appear in suppressed counts, so future findings from that audit are invisible forever.

## Mode: config

Generate or repair `.github/zizmor.yml`. Show the complete proposed file and get approval before writing.

Decisions to walk through:

1. **Pinning policy** — the Layer 3 question, written down. Offer these three shapes and recommend the first:

   ```yaml
   # 1. hash-pin everything (RECOMMENDED) — this is also zizmor's default,
   #    so the block is only worth writing to make the intent explicit.
   rules:
     unpinned-uses:
       config:
         policies:
           "*": hash-pin
   ```

   ```yaml
   # 2. ref-pin only the namespaces this org controls; hash-pin all third parties.
   #    Most specific pattern wins regardless of order.
   rules:
     unpinned-uses:
       config:
         policies:
           # We own this org and enforce protected tags on every release repo.
           "my-org/*": ref-pin
           "*": hash-pin
   ```

   ```yaml
   # 3. ref-pin broadly. A deliberate downgrade — only with a stated reason.
   rules:
     unpinned-uses:
       config:
         policies:
           "*": ref-pin
   ```

   Ask which namespaces are trusted **and why**, and put the answer in the comment. "We own it" is a reason; "it's a big org" is not — `actions/*` is a big org and zizmor's default still hash-pins it. Pattern specificity order and the `any` policy are in `references/zizmor.md` → "Repository patterns".
2. **Existing suppressions** — migrate scattered inline ignores into config where they are file-wide, keep them inline where they are location-specific.
3. **Severity promotions** — which audits are release-blocking for this org.
4. **Configurable audits** — only five accept `config:`: `unpinned-uses`, `forbidden-uses`, `known-vulnerable-actions`, `secrets-outside-env`, `dependabot-cooldown`. Do not invent `config:` blocks for any other audit.

Always place the file at `.github/zizmor.yml` and include the SchemaStore comment so editors validate it. See `references/zizmor.md` → "Worked baseline config".

State the discovery trap explicitly: in a Git repo, discovery starts **and ends** at the repo root. A `zizmor.yml` anywhere else is dead config.

## Mode: ci

Ask which shape is wanted before generating:

```
How should this gate behave?
  a. Security-tab alerts (SARIF)   → findings become code-scanning alerts;
                                     the job stays GREEN, blocking is a ruleset decision
  b. Hard-fail check               → the job goes RED on medium+ findings
  c. Both                          → alerts for visibility, plus a failing check

Enter a, b, or c:
```

This choice matters more than it looks. **`--format=sarif` suppresses exit codes 11–14**, so a SARIF-only workflow passes even with high-severity findings. If the user says "fail the build", (a) alone will not do it — say so rather than shipping a gate that cannot fail.

Copy the matching template from `references/zizmor.md` → "CI integration": Option A (`zizmorcore/zizmor-action`), Option B (`uvx` hard-fail gate), Option C (both). All three ship with `permissions: {}` at the top, job-scoped `security-events: write` only where SARIF is uploaded, `persist-credentials: false` on checkout, and SHA-pinned action refs with version comments.

Two action-specific traps to state when using Option A:

- `annotations: true` is **mutually exclusive** with `advanced-security: true`. Enabling annotations requires setting `advanced-security: false` explicitly.
- Pin the `version:` input rather than leaving `latest`, or the check's behaviour changes without a commit.

## Mode: precommit

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/zizmorcore/zizmor-pre-commit
    rev: v1.29.0
    hooks:
      - id: zizmor
```

Always state the caveat: the hook runs in whatever mode the local environment implies, which without a token is **offline**. Pre-commit passing is therefore not equivalent to CI passing — the four online audits do not run locally. That trade is usually right for hook latency, but it must be said, not discovered.

`files:` is unnecessary — the hook scans the whole repo by default. Works with `prek` as well as `pre-commit`. Hand off to `/platform-skills:renovate` to keep `rev:` current.

## Mode: explain

Given an audit id (`template-injection`) or a pasted finding, produce:

1. **What it detects** — the mechanism, not the label.
2. **Why it matters** — the concrete attack or failure, in this repo's terms.
3. **Persona and mode gating** — whether it needs `pedantic`/`auditor`, or online access. Several audits are invisible by default; that is often the real question behind "why didn't zizmor catch this?".
4. **Remediation** — the exact YAML before and after.
5. **Auto-fixable?** — and whether the fix is classified safe or unsafe.
6. **When suppression is legitimate** — and the exact suppression syntax for that case.

Pull the facts from the audit catalogue in `references/zizmor.md`. Never invent an audit id, a `config:` key, or a persona requirement — if it is not in the catalogue, say so and point at `https://docs.zizmor.sh/audits/`.

---

## Agent behavior

### Intent classification

Before asking anything, classify the free-text request:

| Intent signals | Mode |
|---|---|
| "audit workflows", "run zizmor", "is this safe", "check my actions" | `scan` |
| "security review", "everything", "full sweep", "auditor", "pentest my CI" | `audit` |
| "fix", "pin my actions", "hash-pin", "remediate", "auto-fix" | `fix` |
| "too noisy", "false positive", "suppress", "ignore this", "which do I care about" | `triage` |
| "zizmor.yml", "policy", "allowlist", "config", "set a pinning rule" | `config` |
| "CI", "PR check", "GitHub Actions gate", "SARIF", "security tab", "block merges" | `ci` |
| "pre-commit", "before commit", "local hook", "prek" | `precommit` |
| "what does X mean", "why is this flagged", "CKV-style id", any bare audit id | `explain` |
| "syntax error", "actionlint", "shellcheck", "invalid workflow" | → `/platform-skills:github-actions` |
| "action.yml inputs", "composite action design" | → `/platform-skills:composite-actions` |
| "terraform", "helm", "kubernetes manifest", "dockerfile misconfig" | → `/platform-skills:checkov` |
| "CVE", "image scan", "vulnerable dependency" | → `/platform-skills:trivy` |
| "keep pins updated", "renovate", "dependabot config" | → `/platform-skills:renovate` |

### Never do these

- **Never claim a repo is clean from an offline run** without naming the four audits that did not execute.
- **Never gate CI on `--persona=auditor`** — documented to include likely false positives; the team stops trusting the check.
- **Never put `--fix` in a gate** — it repairs its own input and always passes.
- **Never invent an audit id, `config:` key, persona requirement, or CLI flag.** The catalogue in `references/zizmor.md` is verified against zizmor v1.29.0; anything absent from it needs `https://docs.zizmor.sh/audits/` checked first.
- **Never suppress a finding without a written reason.**
- **Never present a SARIF-only workflow as a merge blocker** — exit codes 11+ are suppressed in SARIF mode.
- **Never recommend `disable:`** when `ignore`, a lower persona, or `remap.severity` would work.
- **Never write a `ref-pin` policy just to clear `unpinned-uses` findings.** Relaxing the policy is a security decision the developer makes with the trade-off stated, not a way to reach a green run.

### Always do these

- **Ask the pinning policy explicitly** — hash-pin (SHA) or ref-pin (semver tag) — and recommend hash-pin, before reporting `unpinned-uses` findings or writing a config. Never infer it from what the repo happens to do today.
- Report the **operating mode, persona, and config file** alongside every result.
- Add `--strict-collection` to every invocation, so "0 findings" cannot mean "0 files audited".
- Pair any hash-pinning work with a Renovate or Dependabot handoff — pins that are never updated rot into `stale-action-refs` and unpatched advisories.
- After writing or fixing anything, run the audit again and report what remains.

---

## Cross-references

- `/platform-skills:github-actions` — workflow and job-graph design, actionlint syntax validation, OIDC, token scoping, failing-workflow debug. Run alongside zizmor, not instead of it.
- `/platform-skills:composite-actions` — composite action scaffolding, `action.yml` review, SHA pinning and env isolation inside actions
- `/platform-skills:renovate` — keep the SHA pins zizmor demands from going stale
- `/platform-skills:checkov` — Terraform, Kubernetes, Helm, and Dockerfile IaC misconfiguration
- `/platform-skills:trivy` — container image, filesystem, and repo CVE and secret scanning
- `/platform-skills:supply-chain` — Cosign signing, SBOM generation and attestation, SLSA provenance
- `/platform-skills:preflight` — production-readiness sweep across mixed file types, including workflows
- `/platform-skills:pr-review` — PR-level review: ownership, blast radius, rollback feasibility
- `/platform-skills:commit` — conventional commit message for the resulting fix
- `/platform-skills:self-improve` — after completing a task here, log errors and learnings with `/platform-skills:self-improve log`

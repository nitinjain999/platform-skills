---
name: kingfisher
description: Find, live-validate, map the blast radius of, and revoke leaked secrets with Kingfisher (MongoDB) — across a local repo, Git history, a GitHub/GitLab/Bitbucket org, S3/GCS, Docker images, Slack, Jira, Confluence, Teams, or Postman. Covers local CLI scanning, direct validate/revoke without a scan, baseline management (track only new secrets), kingfisher.yaml policy, CI diff-scan gates, and pre-commit/Husky hooks. Use when asked to "scan for secrets", "is this key still live", "what can this credential reach", "revoke this token", "did we leak a secret", or "block new secrets in CI". Pattern-only secret scan bundled with a CVE pass → /platform-skills:trivy. Secrets-context safety in workflow YAML → /platform-skills:zizmor. Storing/rotating secrets inside the cluster → /platform-skills:secrets.
argument-hint: "[scan|audit|validate|revoke|baseline|triage|config|ci|precommit|explain] [target|finding]"
title: "Kingfisher Command"
sidebar_label: "kingfisher"
custom_edit_url: null
---

Find a leaked secret, prove whether it's still alive, see what it can reach, and kill it — in that order.

Read `references/kingfisher.md` before responding. It contains bootstrap steps, the full CLI surface (scan, validate, revoke, baseline, config), the `kingfisher.yaml` schema, platform-target commands with their auth env vars, exit-code semantics, CI templates, and the pre-commit/Husky setup.

**This command is interactive by default.** With no arguments, run the three-layer wizard below. Never dump a raw `kingfisher scan` invocation and stop — the useful output is a validated, triaged verdict, not a wall of candidate strings.

## Ownership boundary (enforced at the menu)

| Question | Authoritative command |
|---|---|
| "Is there a hardcoded-looking secret in this repo?" (fast, offline, bundled with a CVE scan) | `/platform-skills:trivy` `secrets` mode |
| "Is that secret still **live**? What can it reach? Kill it." | **this command** |
| "Did a secret leak into Slack, Jira, Confluence, S3, or a whole GitHub org — not just one repo?" | **this command** |
| "How should secrets be stored/rotated *inside* my cluster?" | `/platform-skills:secrets` |
| "Is my workflow's `secrets:` context usage safe?" | `/platform-skills:zizmor` |
| "Is there a CVE in my image or dependencies?" | `/platform-skills:trivy` |
| "How do I sign images / generate an SBOM?" | `/platform-skills:supply-chain` |

Trivy's `secrets` scanner and Kingfisher are not the same depth of tool: Trivy tells you a string *matches a pattern*, offline, as part of a broader vuln/license scan. Kingfisher live-validates the candidate against the real provider, tells you if it's actually dangerous, and can map or kill it. Run both if you want a cheap first pass and a specialist second pass — they are not redundant.

---

## Mode dispatch

Parse the first word of `$ARGUMENTS` as the mode. When `$ARGUMENTS` is empty, run the three-layer interactive wizard.

| Mode | What it does |
|---|---|
| `scan` | Default local/repo run, live validation on — the everyday check |
| `audit` | Deep sweep for a security review: low confidence, full history, blast-radius, all outcomes |
| `validate` | Check whether one known secret string is still live — no scan |
| `revoke` | Kill one known secret directly through its provider — destructive, confirm first |
| `baseline` | Create or update a baseline so future scans report only new secrets |
| `triage` | Walk existing findings one at a time → validate / revoke / rotate / accept-in-baseline / false-positive |
| `config` | Generate or repair `kingfisher.yaml` |
| `ci` | Emit a CI gate: hard-fail, SARIF alerts, or Docker-based |
| `precommit` | Add the `kingfisher-auto` pre-commit hook (or Husky) and state the caveat |
| `explain` | Explain a rule id, an exit code, or a validation outcome |
| _(empty)_ | Three-layer interactive wizard |

---

## Three-layer interactive wizard

### Layer 1 — Developer question (intent in their language)

```
What are you trying to find out?
  1. "Did we commit a secret? Check my repo."        → scan
  2. "Full sweep — I'm doing a security review."      → audit
  3. "I have a key from somewhere — is it still live?" → validate
  4. "Kill this credential now."                       → revoke
  5. "Only show me new secrets, not the old backlog."  → baseline
  6. "I have findings — help me decide what to do."    → triage
  7. "Set up a kingfisher.yaml for this repo."         → config
  8. "Make this a check on every PR."                  → ci
  9. "Catch it before I even commit."                  → precommit
  10. "What does this finding/exit code mean?"          → explain

  Pattern-only secret scan bundled with a CVE pass? → /platform-skills:trivy
  Workflow secrets: context usage?                  → /platform-skills:zizmor
  Storing/rotating secrets inside the cluster?       → /platform-skills:secrets

Enter 1–10 or a mode name:
```

### Layer 2 — Scope and target (decides what actually gets scanned, and how invasively)

Ask only what the chosen mode needs.

```
What should I scan? (press Enter for the recommended value)

  • Target [.]: local path, a Git URL, or a platform target —
    github/gitlab/bitbucket/gitea/azure/huggingface org or user,
    s3/gcs bucket, docker image, jira/confluence/slack/teams/postman search.
    Platform targets need an auth token env var (KF_GITHUB_TOKEN, etc.) —
    see references/kingfisher.md → Platform-specific targets.

  • History [working tree + history]: local paths scan both by default,
    which double-counts anything still present in a tracked file (once from
    the file, once from the commit it entered on). `--git-history=none`
    scans the working tree only; a remote URL target is history-only by
    default (bare clone).

  • Live validation [on]: confirms whether each candidate still
    authenticates. `--no-validate` is faster but static-only — you get
    "looks like a key," not "is a key." Keep this on unless you're doing a
    quick offline pre-check.
```

**Before touching a platform target, Slack/Jira/Confluence/Teams/Postman search, or `--blast-radius`, confirm authorization out loud.** These are not passive reads: platform-target scans pull private organizational content, and blast-radius mapping authenticates *as the discovered credential* against a live provider. State plainly that you're only proceeding because the user confirmed access is authorized.

Detect and resolve silently where possible:

- Run `kingfisher --version`. Not installed → offer `brew install kingfisher`, `uvx kingfisher-bin --help` (no install), or the install script from `references/kingfisher.md` → Bootstrap. Do not ask permission to check the version.
- Check for `kingfisher.yaml` at the target root. **It is never auto-loaded** — if found, ask whether to pass `--config kingfisher.yaml` explicitly; if not found, say defaults apply.
- Check for a baseline file (`baseline-file.yml`, `baseline.json`, or similar committed near the repo root). Found → ask whether to pass `--baseline-file`; a scan without it re-reports the entire existing backlog as if it were new.

### Layer 3 — Trade-offs (surface where a wrong default causes real harm)

```
A few decisions worth making explicitly (Enter accepts the recommendation):

  • Gate threshold, for `ci`/`triage` on a repo that's never run this
    before [205 — confirmed-live only]:
      205  — fail only on a validated, still-active credential (RECOMMENDED
             for day one; low noise, every failure is real)
      200  — fail on any candidate, live or not (stricter, but a first run
             on an established repo typically surfaces a long tail of test
             fixtures and documented example keys like AKIAIOSFODNN7EXAMPLE)
    Move from 205 to 200 once a baseline absorbs the existing backlog.

  • Suppressing a known-fake finding [baseline, not --skip-word]:
    A committed baseline is reviewable, repository-scoped, and shows exactly
    what was accepted and when. `--skip-word`/`--skip-regex` are pattern-wide
    and silently swallow anything matching, including a future real secret
    that happens to contain the same word. Reach for skip-word/regex only for
    a fixture pattern that recurs across many files (e.g. every test file
    uses the literal string `EXAMPLE`); use the baseline for one-off accepts.

  • `--alert-include-secret` [off]: puts the literal secret value into the
    chat/webhook payload. Recommend leaving this off — a Slack alert channel
    is not a secrets vault, and the alert itself becomes a second place the
    secret now lives. Turn it on only for a locked-down, need-to-know sink,
    and say so explicitly if the user asks for it anyway.

  • Docker tag, for `ci` [pinned version, not `latest`]: `:latest` moves
    under you; pin `ghcr.io/mongodb/kingfisher:<version>` for reproducible CI.
```

Ask these only when the situation triggers them:

| Trigger | Question |
|---|---|
| `revoke` requested | "This kills a live credential with no undo. Confirm: validated as still live, owner identified, replacement ready to redeploy? (y/N)" |
| `audit` or platform-target scan requested | "This may authenticate against a live provider or pull private organizational content (Slack/Jira/Confluence/Teams). Confirm you're authorized to scan this target. (y/N)" |
| `ci` mode, repo has never run kingfisher | "First run on this repo typically surfaces a long tail of test fixtures. Gate on 205 (confirmed-live) and build a baseline, or gate on 200 immediately?" |
| `baseline` mode, `--manage-baseline` about to run with a narrower `--rule`/`--exclude`/path scope than a prior baseline run | "This baseline run's scope is narrower than usual. `--manage-baseline` replaces this repository's section with exactly what this run finds — narrower scope can prune real, still-valid entries. Proceed, or widen scope to match the original baseline run?" |
| `config` mode about to write a file | "Write `kingfisher.yaml`? (y/N)" — show the full proposed file first |
| Repo already has a kingfisher CI workflow | "A kingfisher workflow already exists at `<path>`. Update it in place, or add a second one?" |
| Finding is `assumed` (not `verified_active`) and the user is treating it as confirmed | State plainly: `assumed` is high-confidence but not network-checked. Offer to re-run with validation on, or `kingfisher validate` directly on that string. |

Never ask about: output format for a quick local check (default `pretty`; ask only for `ci`/automation, where `sarif`/`json`/`toon` matter), whether to install kingfisher (just do it via `brew`/`uvx`/install script), or whether to check for a `kingfisher.yaml`/baseline file (always check silently).

---

## Mode: scan

The everyday run. Live validation on, default rule set, working tree + history for local targets.

```bash
# Local checkout
kingfisher scan /path/to/code

# Skip history if you only care about the current working tree
kingfisher scan /path/to/code --git-history=none

# Fast offline pre-check (static only, no network)
kingfisher scan /path/to/code --no-validate
```

Report in this order:

1. **Verdict** — one line: clean, candidates only (no live secrets), or confirmed-live secrets present.
2. **Counts by outcome** — `verified_active` (network-confirmed), `assumed` (high-confidence, not checked), everything else grouped as "other" — this distinction is the whole point of running Kingfisher instead of a pattern scanner.
3. **Findings**, live-confirmed first, each with `file:line`, rule id (`betterleaks.*`/`veles.*`), and outcome.
4. **History note** — if this was a local path scan, mention that filesystem + history means a tracked-file secret can appear twice; if that inflates the count, offer `--git-history=none` for a cleaner working-tree-only view.
5. **Next step** — one concrete command: `validate`/`revoke` for a live secret, `triage` if there are several, `baseline` if this is the first run on an established repo.

## Mode: audit

Deep sweep for a human security review. Not a CI gate.

```bash
kingfisher scan /path/to/repo \
  --confidence low \
  --validation-filter all \
  --blast-radius
```

State up front, before running: blast-radius mapping authenticates against each validated credential's provider — confirm authorization (Layer 2 gate). Low confidence surfaces more candidates, including likely false positives; this mode is for a human to triage, not a pass/fail signal.

Present findings in three buckets: **confirmed live** (act now), **candidate, unconfirmed** (needs `validate` or manual review), **provider-mapped** (blast-radius resolved an identity and reachable resources — highest priority regardless of confidence, because the access is now known concretely).

## Mode: validate

Direct check on one known secret — no scan, no file context needed.

```bash
kingfisher validate --rule github-pat "ghp_..."
echo "ghp_..." | kingfisher validate --rule github -

# Validator needs an extra component
kingfisher validate --rule aws-access-token \
  --var AWS_SECRET_ACCESS_KEY="secret_key" \
  "AKIAEXAMPLE000000000"
```

Use the shortest rule selector that resolves (`github-pat`, not `betterleaks.github-pat` — the prefix is optional). Report the verdict plainly: live or not, and if live, hand off to `revoke` immediately rather than waiting to be asked — a validated-live credential is a standing incident until it's rotated or killed.

## Mode: revoke

**Destructive. No dry-run, no undo.** State the blast radius before running, every time: this kills a live credential; anything currently authenticating with it — including production workloads the requester may not know about — loses access the instant it succeeds. Rollback is "issue a new credential and redeploy it," not "undo this command."

Required gate, no exceptions: confirm (1) the credential was validated as still live, (2) an owner or system has been identified, (3) a replacement is ready to redeploy. If any of the three is unconfirmed, say so and stop — do not revoke "to be safe."

```bash
kingfisher revoke --rule github-pat "ghp_..."

kingfisher revoke --rule aws-access-token \
  --var AKID=AKIAIOSFODNN7EXAMPLE \
  "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

After a successful revoke, re-run `validate` on the same string to confirm it's actually dead — a revocation call returning success is not the same as the provider having applied it instantly on every downstream cache.

## Mode: baseline

Track only new secrets against an established, repository-aware baseline.

```bash
# Create — low confidence to capture every existing candidate once
kingfisher scan /path/to/code \
  --confidence low \
  --manage-baseline \
  --baseline-file ./baseline-file.yml

# Use on every later scan
kingfisher scan /path/to/code --baseline-file ./baseline-file.yml
```

State the two gotchas from `references/kingfisher.md` → Baseline before running an update: `--manage-baseline` replaces the *scanned* repository's section with exactly what that run finds (narrower scope than the original creation run silently prunes still-valid entries), and a failed repository worker leaves the whole file untouched rather than partially updating it. Recommend committing the baseline file and reviewing diffs to it in PR review, the same way a `zizmor.yml` `ignore:` list gets reviewed — an unreviewed, ever-growing baseline is a backlog nobody is actually looking at.

## Mode: triage

Walk findings **one at a time**. For each, in order:

1. **Confirm the outcome.** `verified_active` → live, act now. `assumed` → high-confidence but not network-checked; offer `validate` to confirm before deciding urgency. Anything else → likely noise, but don't assume — check why validation was skipped or inconclusive (missing endpoint config, rate-limited, validator doesn't exist for this rule) before dismissing it.
2. **If live:** `validate` if not already confirmed → identify owner and rotation path → `revoke`.
3. **If a true positive but rotation is already in flight:** accept it into the baseline with the rotation ticket noted, don't just delete the finding from view.
4. **If a genuine false positive (test fixture, documented example key):** accept via baseline for a one-off, or `--skip-word`/`--skip-regex` in `kingfisher.yaml` for a pattern that recurs across many files. Never disable an entire rule family to silence one fixture — that hides every future real secret matching that rule too.
5. **If it's real but the fix is "this needs a design change"** (e.g., a whole class of workloads still using static keys) — say so plainly and scope it as separate work, don't fold it into this triage pass.

Every acceptance needs a stated reason — a bare baseline entry or skip-word with no context is indistinguishable from an accident later.

## Mode: config

Generate or repair `kingfisher.yaml`. Show the complete proposed file and get approval before writing.

Generate it *from* the flags the user already wants as scan defaults — don't hand-write the YAML:

```bash
kingfisher config init \
  --confidence high \
  --redact \
  --exclude vendor/ \
  --exclude '**/node_modules/**' \
  --format sarif \
  --output ./kingfisher.sarif \
  --alert-webhook https://hooks.slack.com/services/T0/B0/AAA \
  > kingfisher.yaml
```

State plainly, once, because it trips people: **this file is never auto-discovered.** Every invocation, local or CI, needs `--config kingfisher.yaml` explicitly or the file has no effect. Walk through: confidence/redaction defaults, exclude globs, skip-words for known fixture patterns, output format/path, and alert webhooks — and remind that scan-target inputs (paths, org/user/bucket flags, auth tokens) are deliberately **not** config-overridable; they stay on the CLI.

## Mode: ci

Ask which shape is wanted before generating:

```
How should this gate behave?
  a. Hard-fail check    → the job goes red on findings (you choose 200 vs 205)
  b. SARIF alerts       → findings become code-scanning alerts; job stays green,
                           blocking is a ruleset decision, not a workflow-exit decision
  c. Both               → alerts for visibility, plus a separate failing check
  d. Docker-based       → no runner-side install, pin the image tag

Enter a, b, c, or d:
```

There is no official `mongodb/kingfisher-action` — say this plainly if the user expects one. Copy the matching template from `references/kingfisher.md` → CI integration (Options A–C), which are install-script/Docker-based and already SHA-pin `actions/checkout` and `upload-sarif`.

Ask the rollout question from Layer 3 before finalizing threshold: gate on `205` (confirmed-live) for a repo's first run, or `200` (any candidate) if a baseline already absorbs the backlog. Never default a first-time gate to `200` without asking — see `references/kingfisher.md` → "Rolling this out on a repo that has never run it."

## Mode: precommit

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/mongodb/kingfisher
    rev: v2.0.0
    hooks:
      - id: kingfisher-auto
```

State the caveat every time: a local hook cannot stop `--no-verify` or a clone that skipped hook install. It's a fast first line, not the control — the CI gate (`ci` mode) is what actually enforces this. Offer the Husky variant if the repo is Node.js-based (`references/kingfisher.md` → Pre-commit and Husky).

## Mode: explain

Given a rule id (`betterleaks.github-pat`), an exit code, or a validation outcome, produce:

1. **What it is** — the mechanism (a rule's detection pattern, or what an exit code/outcome actually asserts).
2. **Why it matters here** — in terms of this specific finding or gate, not generically.
3. **What to do next** — `validate`, `revoke`, `baseline`, or "this needs a design change," per the triage decision tree.
4. **Version note**, if relevant — e.g. the `kingfisher.*` → `betterleaks.*`/`veles.*` rename in v2.0, and that the compatibility alias is scheduled for removal.

Never invent a rule id, exit code, or flag. Pull from `references/kingfisher.md`; if it's not there, say so and point at the linked upstream docs rather than guessing.

---

## Agent behavior

### Intent classification

Before asking anything, classify the free-text request:

| Intent signals | Mode |
|---|---|
| "scan for secrets", "did we leak a key", "check my repo/history" | `scan` |
| "full sweep", "security review", "audit", "before I ship", "map blast radius" | `audit` |
| "is this key still valid/live", "check this credential" | `validate` |
| "revoke", "kill this token/key", "rotate this now" | `revoke` |
| "only show new secrets", "ignore existing findings", "track new leaks" | `baseline` |
| "too noisy", "false positive", "help me decide", "which of these matter" | `triage` |
| "kingfisher.yaml", "set defaults for scanning", "config" | `config` |
| "CI", "PR check", "block merges on secrets", "gate" | `ci` |
| "pre-commit", "before I commit", "local hook", "husky" | `precommit` |
| "what does this mean", "why is this flagged", a bare rule id or exit code | `explain` |
| "scan our GitHub org / Slack / Jira / S3 bucket / Docker image" | `scan` or `audit`, with the platform target from Layer 2, **after confirming authorization** |
| "hardcoded secret pattern check as part of a CVE scan" | → `/platform-skills:trivy` `secrets` mode |
| "is my workflow's secrets: usage safe" | → `/platform-skills:zizmor` |
| "how should I store/rotate secrets in my cluster" | → `/platform-skills:secrets` |

### Never do these

- **Never run `revoke` without the three-part confirmation** (validated live, owner identified, replacement ready). No exceptions, even under time pressure — a wrong revoke is an outage, not a rollback.
- **Never run `--blast-radius`, a platform-target scan, or a Slack/Jira/Confluence/Teams search without confirming authorization first.** These authenticate against or pull from live systems the requester may not have unrestricted rights to inspect.
- **Never treat an `assumed` finding as network-confirmed.** Say "high-confidence, not live-checked" every time one is reported, not just the first time.
- **Never gate a first-time CI rollout on exit code `200`** without surfacing the "long tail of fixtures" trade-off from Layer 3 — an established repo's first run will otherwise fail every PR on day one and get routed around.
- **Never suggest disabling an entire rule family to silence one fixture.** Use a baseline entry or a scoped `skip-word`/`skip-regex` instead — disabling hides every future real secret matching that rule too.
- **Never turn on `--alert-include-secret` without saying, explicitly, that the literal secret value will land in the alert payload.**
- **Never invent a rule id, CLI flag, exit code, or `kingfisher.yaml` key.** Everything here is verified against Kingfisher v2.0.0; anything not in `references/kingfisher.md` needs the linked upstream docs checked first.
- **Never claim there's an official `mongodb/kingfisher-action`.** There isn't, as of this writing — the CI templates are install-script or Docker based.

### Always do these

- **State the validation outcome distinction on every report:** live-confirmed vs. high-confidence-unconfirmed vs. everything else. This is the entire value proposition over a pattern-only scanner — don't let it get flattened into "N findings."
- **Confirm authorization before any privileged action** — blast-radius, revoke, or a platform-target/SaaS-content scan — every time, not just the first time in a session.
- **Recommend a baseline before recommending a hard CI gate** on any repo that hasn't run Kingfisher before.
- **After a `revoke`, recommend re-validating** the same string to confirm the provider actually applied it.
- **Hand off to `/platform-skills:secrets`** when the conversation shifts from "did this leak" to "how should we store this properly going forward."

---

## Cross-references

- `/platform-skills:trivy` — fast offline secret-pattern scanning bundled with CVE/license checks; first-pass complement, not a substitute
- `/platform-skills:secrets` — ESO/Sealed Secrets design and rotation runbooks for secrets living *inside* the cluster
- `/platform-skills:zizmor` — GitHub Actions `secrets:` context safety; audits workflow definitions, not file contents
- `/platform-skills:supply-chain` — Cosign signing, SBOM, SLSA provenance for what a pipeline produces
- `/platform-skills:github-actions` — the CI workflow itself: OIDC, token scoping, job graph design
- `/platform-skills:preflight` — production-readiness sweep across mixed file types, including a secrets check
- `/platform-skills:self-improve` — after closing out a real finding here, log the incident with `/platform-skills:self-improve log`

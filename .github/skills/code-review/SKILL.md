---
name: code-review
description: Review pull requests to this repo (a Claude Code / Copilot / Cursor platform-engineering skill plugin) for technical accuracy, security posture, structural consistency with existing domains, and completeness. Use this for any PR touching commands/, references/, examples/, skills/platform-skills/SKILL.md, or the plugin catalog files (plugin.json, marketplace.json, COMMANDS.md, HOW_IT_WORKS.md, GETTING_STARTED.md).
---

This repo teaches platform engineering patterns (Kubernetes, Terraform, GitHub Actions, AWS, Azure, GitOps, secrets management, and related domains) as slash commands, reference guides, and worked examples. Review every PR against the priorities below, in order — correctness and security outrank style every time.

## 1. Correctness first

- Don't take a vendor API, SDK method, config schema, or CLI flag on faith — verify it against the vendor's actual current docs before approving a claim about it. A wrong schema in this repo doesn't just break a build once; every user who copies the example inherits the bug. If the PR can't be independently verified from the diff alone, say so explicitly rather than approving on trust.
- If a PR claims a behavior ("fails open", "fails closed", "denies", "logs X") for a script or workflow, trace the actual code path rather than trusting the prose describing it. Doc drift between what code does and what a comment/reference says it does is a common, real defect class here — flag it as a correctness issue, not a nitpick.
- Flag deprecated APIs, deprecated action versions, and end-of-life tool versions by name.

## 2. Security

- No wildcard IAM actions (`"*"`) or wildcard resources (`Resource: "*"`) without an explicit justification comment. Push for scoped ARNs and explicit action lists.
- GitHub Actions: `uses:` steps pinned to a full commit SHA (not a floating tag) unless the PR explicitly documents why not yet (e.g. "pin before use" on a new example). Least-privilege `permissions:` blocks — flag a job-level `write` scope that only one step needs.
- Any workflow step that interpolates `${{ github.* }}` directly into a `run:` shell block is a template-injection risk — it must be bound to an `env:` var first and referenced as a quoted shell variable.
- Secrets: no hardcoded credentials, no logging of raw secret values, and any new audit/log-writing code must state what it excludes (raw command text, tokens, etc.) — silence on this point is a gap, not a default-safe assumption.

## 3. Structural consistency with this repo's own conventions

New content must match the shape of existing sibling content, not invent a new one:

- A new `commands/<name>.md` needs front-matter matching existing commands (`name`, `description`, `argument-hint`, `title`, `sidebar_label`, `custom_edit_url`) and the Q1/Q2 interactive-wizard pattern already used elsewhere.
- A new command must be registered everywhere the catalog expects it, not just in `skills/platform-skills/SKILL.md`: `.claude-plugin/plugin.json` (`commands` array + keywords), root `SKILL.md` (must stay byte-identical to `skills/platform-skills/SKILL.md`), `COMMANDS.md`, `HOW_IT_WORKS.md`, `GETTING_STARTED.md`, and any repo-wide command-count reference (README badge/prose, `EDITOR_INTEGRATIONS.md`, `marketplace.json`). Run `bash tests/validate-skill.sh` and `bash tests/handbook-consistency.sh` and confirm both are clean before approving — a PR that adds a command but skips this registration sweep is incomplete, not just stylistically off. (This is not a hypothetical: a real PR to this repo shipped a fully-working command that failed exactly this check, caught only by a whole-diff review, not the per-file diff.)
- A new `examples/<domain>/` directory needs a `README.md` starting with a `Status: <Stable|Beta>` line, matching sibling example READMEs.
- Don't recreate a pattern that already has a home elsewhere in this repo (e.g. don't add ad-hoc IAM least-privilege prose inside an unrelated command when `references/aws.md`/`references/azure.md` or the IAM section of the top-level `CLAUDE.md` already own that guidance) — cross-reference it instead.

## 4. Completeness

- Every risky or destructive operation documented in this repo needs, at minimum: what it affects, how to verify the change worked, and how to roll it back. A PR introducing a new pattern without a rollback note is missing a required section, not offering an optional nice-to-have.
- Test/validation claims in a PR description must be checked against what actually ran — "tests pass" without a shown command and output is a claim, not evidence. If the PR touches a script with its own test suite (e.g. anything under `examples/*/tests/`), confirm that suite is wired into `tests/handbook-consistency.sh` or an equivalent CI gate, not just runnable by hand.
- If a script or workflow needs to work across environments (this repo's bash code targets bash 3.2 for macOS compatibility; CI runs on Ubuntu), don't assume a technique that works in the review environment (e.g. hiding a binary via a `PATH` restriction, or relying on `globstar`) generalizes — ask whether it's been verified on both, or flag it as unverified.

## 5. Maintainability

Only after the above are clean: check for premature abstraction, unnecessary refactors of unrelated code, comments that explain *what* instead of *why*, and scope creep beyond what the PR's stated purpose requires.

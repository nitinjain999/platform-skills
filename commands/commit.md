---
name: commit
description: Analyze git diffs or staged changes and generate conventional commit messages that explain WHY a change was made. Supports auto-detecting type and scope, intelligent file staging, and interactive overrides. Use when asked to "write a commit message", "generate a commit", "describe my changes", "commit this", "summarize my diff", or "/commit".
argument-hint: "[analyze|generate|stage|validate] [optional: type/scope override or description]"
---

Analyze changes and generate a Conventional Commits message explaining the motivation behind the change.

## Mode: analyze

Inspect staged or unstaged changes and classify the commit type and scope.

Steps:
1. Run `git diff --staged` — if empty, run `git diff HEAD` to capture unstaged changes
2. Group changed files by logical concern (feature, fix, refactor, docs, config, tests, ci)
3. Identify the type from the change pattern:
   - `feat` — new capability or behavior added
   - `fix` — corrects broken or incorrect behavior
   - `refactor` — restructures code without changing behavior
   - `perf` — measurably improves performance
   - `test` — adds or corrects tests only
   - `docs` — documentation only
   - `chore` — build tooling, dependency updates, config changes with no production effect
   - `ci` — changes to CI/CD pipelines or workflow files
   - `revert` — reverting a prior commit
4. Infer scope from the most specific common ancestor: module name, service name, directory, or filename
5. Check for breaking changes: API removals, signature changes, config renames, behavior inversions — flag with `!` and add `BREAKING CHANGE:` footer
6. Report: detected type, scope, whether breaking, and a one-line WHY summary

Reference: `references/conventional-commits.md` → Type Classification, Scope Rules

## Mode: generate

Generate a complete conventional commit message from diff or description.

Steps:
1. Run `analyze` mode first to determine type, scope, and breaking status
2. Write the subject line:
   - Format: `<type>(<scope>): <imperative verb> <what and why>`
   - Max 72 characters
   - Imperative mood: "add", "fix", "remove", "update", "extract" — not "added", "fixes"
   - Focus on the WHY, not just the what: "fix(auth): validate token expiry before redirect" not "fix(auth): update token check"
3. Write the body (when the subject line is insufficient):
   - Wrap at 72 characters
   - Explain the problem being solved and the approach chosen
   - One blank line between subject and body
4. Write footers:
   - `BREAKING CHANGE: <description>` for breaking changes (also add `!` to subject)
   - `Fixes #<issue>` or `Closes #<issue>` for linked issues
   - `Co-authored-by:` if applicable
5. Output the full message in a code block ready to copy

Message structure:
```
<type>(<scope>): <subject>

<body — optional, explains motivation and approach>

<footers — optional>
```

Reference: `references/conventional-commits.md` → Message Structure, Body and Footer Rules

## Mode: stage

Intelligently stage files for a logical, atomic commit.

Steps:
1. Run `git status` to list all modified, added, and deleted files
2. Group files by logical change:
   - Source files that implement a single feature or fix together
   - Test files that cover those source changes
   - Documentation that describes those changes
   - Config or build changes that support those changes
3. Separate unrelated changes into distinct groups — each group should be a separate commit
4. If multiple logical groups exist: present the groupings and ask which to stage first
5. Stage the chosen group: `git add <files>`
6. Confirm staged set with `git diff --staged --stat`
7. Run `generate` mode to produce the commit message for the staged group

Reference: `references/conventional-commits.md` → Atomic Commits

## Mode: validate

Validate an existing commit message against the Conventional Commits specification.

Steps:
1. Accept the message as input (or read from `git log -1 --format=%B`)
2. Check subject line:
   - Has valid type from the allowed list
   - Scope (if present) uses lowercase, no spaces
   - `!` before `:` only when `BREAKING CHANGE` footer is also present
   - Subject after `:` starts with lowercase, no period at end, ≤ 72 chars
3. Check body (if present):
   - Separated from subject by exactly one blank line
   - Lines wrap at 72 characters
4. Check footers (if present):
   - `BREAKING CHANGE:` value is non-empty
   - Issue references use correct format (`Fixes #N`, `Closes #N`)
5. Report: PASS or list of violations with the exact rule broken and the corrected line

Reference: `references/conventional-commits.md` → Validation Rules

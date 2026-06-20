---
title: Conventional Commits
custom_edit_url: null
---

# Conventional Commits Reference

Covers the Conventional Commits 1.0.0 specification, type classification, scope rules, breaking changes, message structure, atomic commit strategy, tooling, and validation.

---

## Message Structure

```
<type>[(<scope>)][!]: <subject>

[body]

[footers]
```

### Subject Line Rules

- **type** — required, lowercase, from the allowed list
- **scope** — optional, lowercase, no spaces, in parentheses: `fix(auth):`, `feat(api):`, `chore(deps):`
- **`!`** — marks a breaking change; requires a `BREAKING CHANGE:` footer
- **subject** — imperative mood, lowercase start, no trailing period, ≤ 72 characters total for the line
- Focus on **why**, not just what: `fix(auth): reject expired tokens before redirect` not `fix(auth): change token check`

### Body Rules

- Separated from subject by exactly one blank line
- Wrap lines at 72 characters
- Explain the **motivation** (what problem this solves) and the **approach** (why this solution over alternatives)
- Do not repeat the subject — add context that doesn't fit in 72 characters

### Footer Rules

- One blank line between body (or subject, if no body) and footers
- `BREAKING CHANGE: <description>` — mandatory when `!` is used; describes what breaks and how to migrate
- `Fixes #<N>` or `Closes #<N>` — closes GitHub/GitLab issues on merge
- `Co-authored-by: Name <email>` — credits additional authors
- Multiple footers allowed, one per line

---

## Type Classification

| Type | When to use | Example |
|------|-------------|---------|
| `feat` | New user-facing capability or behavior | `feat(orders): add bulk cancel endpoint` |
| `fix` | Corrects broken or incorrect behavior | `fix(auth): validate token expiry before redirect` |
| `refactor` | Restructures code without changing behavior | `refactor(payment): extract retry logic to helper` |
| `perf` | Measurably improves performance | `perf(db): replace N+1 query with single join` |
| `test` | Adds or corrects tests only | `test(orders): add edge cases for empty cart` |
| `docs` | Documentation only | `docs(api): document rate limit headers` |
| `chore` | Build tooling, dependency bumps, config with no production effect | `chore(deps): bump axios to 1.7.0` |
| `ci` | CI/CD pipeline or workflow changes | `ci(release): pin actions to SHA` |
| `revert` | Reverts a prior commit | `revert: feat(orders): add bulk cancel endpoint` |
| `style` | Formatting only (whitespace, semicolons) — no logic change | `style(api): apply prettier to routes` |
| `build` | Changes to build system or external dependencies | `build(webpack): enable tree-shaking for lodash` |

### Choosing Between Types

- `feat` vs `refactor` — does the user-visible API or behavior change? Yes → `feat`. No → `refactor`
- `fix` vs `refactor` — was something broken before? Yes → `fix`. No → `refactor`
- `chore` vs `ci` — does it affect the CI pipeline definition? Yes → `ci`. No → `chore`
- `perf` vs `refactor` — is there a measurable latency/throughput improvement? Yes → `perf`. No → `refactor`

---

## Scope Rules

- Use the most specific common ancestor of all changed files
- Good scopes: service name (`auth`, `orders`), module (`db`, `cache`), layer (`api`, `ui`), tool (`deps`, `helm`, `terraform`)
- Omit scope when changes span too many areas to name one meaningfully
- Lowercase only, no spaces, no slashes: `fix(auth-middleware):` not `fix(Auth/Middleware):`
- Keep scopes consistent across the team — add a `commitlint` scope allow-list to enforce

---

## Breaking Changes

A breaking change is any change that requires consumers to update their code, configuration, or deployment:

- Removing or renaming a public API, endpoint, or config key
- Changing the type or shape of a response/input
- Altering default behavior that existing users depend on
- Increasing the minimum required version of a dependency

```
feat(api)!: require Authorization header on all endpoints

Previously unauthenticated routes returned 200. This change returns 401
for all requests without a valid Bearer token to enforce zero-trust.

BREAKING CHANGE: Callers must include `Authorization: Bearer <token>` on
all requests. Update SDKs to v2.x which handle this automatically.
Closes #412
```

---

## Atomic Commits

Each commit should represent a single logical change that can be understood, reviewed, and reverted independently.

**Atomic — one concern per commit:**
```
feat(orders): add idempotency key validation
test(orders): cover duplicate idempotency key rejection
```

**Non-atomic — avoid:**
```
feat: add idempotency, fix auth bug, update README, bump deps
```

### How to split staged changes

```bash
# Stage specific files
git add src/orders/validator.ts src/orders/validator.test.ts

# Stage specific hunks interactively
git add -p src/orders/service.ts

# Check what will be committed
git diff --staged --stat
```

---

## Full Message Examples

### Simple fix

```
fix(cache): return 404 when key is missing instead of empty string

The cache client was returning an empty string for missing keys, causing
callers to silently treat cache misses as valid empty values. Returns null
now so callers can distinguish a miss from a cached empty value.

Fixes #87
```

### New feature with scope

```
feat(billing): add proration when upgrading mid-cycle

Calculates remaining days in the billing period and credits the unused
portion against the new plan price. Previously users were charged the
full new price regardless of when they upgraded.

Closes #201
```

### Breaking change

```
feat(config)!: rename DATABASE_URL to DB_CONNECTION_STRING

Aligns with the internal naming convention used across all other services.
The old variable name is no longer read.

BREAKING CHANGE: Rename DATABASE_URL to DB_CONNECTION_STRING in all
environment files and secrets managers before deploying.
```

### Chore (no body needed)

```
chore(deps): bump terraform-aws-modules/eks to 20.8.1
```

### CI change

```
ci(release): pin github/codeql-action to SHA

Floating tag @v3 caused an unexpected version jump during a release.
SHA pinning prevents supply-chain risk from mutable tags.
```

### Revert

```
revert: feat(orders): add bulk cancel endpoint

Reverts commit a3f8c2d. The bulk cancel endpoint caused a race condition
under high concurrency (see #318). Reverting while a proper fix is prepared.
```

---

## Tooling

### commitlint

Enforces Conventional Commits in CI and via git hooks.

```bash
npm install --save-dev @commitlint/cli @commitlint/config-conventional
```

```js
// commitlint.config.js
export default {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "scope-enum": [2, "always", ["auth", "api", "orders", "billing", "deps", "ci", "docs"]],
    "subject-max-length": [2, "always", 72],
    "body-max-line-length": [2, "always", 72],
  },
};
```

### husky (git hook)

```bash
npm install --save-dev husky
npx husky init
echo "npx --no -- commitlint --edit \$1" > .husky/commit-msg
```

### GitHub Actions — validate PR title

```yaml
name: Lint PR title
on:
  pull_request:
    types: [opened, edited, synchronize]

jobs:
  commitlint:
    runs-on: ubuntu-latest
    steps:
      - uses: amannn/action-semantic-pull-request@v5.5.3
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          types: |
            feat
            fix
            refactor
            perf
            test
            docs
            chore
            ci
            revert
            style
            build
```

### semantic-release

Automates versioning and changelog generation from commit history:

```bash
npm install --save-dev semantic-release \
  @semantic-release/commit-analyzer \
  @semantic-release/release-notes-generator \
  @semantic-release/changelog \
  @semantic-release/github
```

```json
// .releaserc.json
{
  "branches": ["main"],
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    ["@semantic-release/changelog", {"changelogFile": "CHANGELOG.md"}],
    "@semantic-release/github"
  ]
}
```

Version bump rules:
- `feat` → minor (`1.x.0`)
- `fix`, `perf`, `refactor` → patch (`1.0.x`)
- `BREAKING CHANGE` → major (`x.0.0`)
- `chore`, `docs`, `test`, `ci` → no release

---

## Validation Rules

A commit message is valid when all of the following pass:

| Rule | Check |
|------|-------|
| Type present | Subject starts with a known type |
| Type lowercase | No uppercase in type |
| Scope lowercase | Scope (if present) contains only `[a-z0-9-]` |
| Subject case | First character after `: ` is lowercase |
| Subject length | Full subject line ≤ 72 characters |
| No trailing period | Subject does not end with `.` |
| Body separator | Exactly one blank line between subject and body |
| Body wrap | No body line exceeds 72 characters |
| Breaking footer | `!` in subject → `BREAKING CHANGE:` footer is present and non-empty |
| Footer format | Footers follow `token: value` or `token #value` format |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| commitlint rejects message | Type not in allow-list | Check `commitlint.config.js` `scope-enum` or `type-enum` |
| semantic-release creates no release | All commits are `chore`/`docs`/`test` | Use `feat` or `fix` for releasable changes |
| PR title lint fails | Title doesn't start with a valid type | Rename PR title to `type(scope): subject` format |
| `!` present but no `BREAKING CHANGE` footer | Footer missing | Add `BREAKING CHANGE: <description>` as footer |
| Scope rejected by commitlint | Scope not in allowed list | Add scope to `scope-enum` in `commitlint.config.js` |

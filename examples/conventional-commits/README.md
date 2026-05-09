Status: Stable

# Conventional Commits Examples

Configuration for enforcing Conventional Commits via commitlint, husky git hooks, and a GitHub Actions PR title linter.

## Examples

| Example | Type | Description |
|---------|------|-------------|
| [commitlint/](commitlint/) | Config | commitlint + husky with scope allow-list and `commit-msg` hook |

## Quick Start

```bash
cd commitlint

# Install commitlint and husky
npm install

# Activate husky hooks (runs automatically on npm install via "prepare" script)
npx husky init
echo "npx --no -- commitlint --edit \$1" > .husky/commit-msg

# Test a valid message
echo "feat(auth): add OIDC login support" | npx commitlint

# Test an invalid message (missing type)
echo "updated auth service" | npx commitlint
# → ✖ subject-empty: subject may not be empty
# → ✖ type-empty: type may not be empty
```

## Commit Message Format

```
<type>(<scope>): <subject>

[optional body]

[optional footers]
```

### Allowed types

| Type | When to use |
|------|-------------|
| `feat` | New user-facing capability |
| `fix` | Corrects broken behavior |
| `refactor` | Restructures without behavior change |
| `perf` | Measurable performance improvement |
| `test` | Tests only |
| `docs` | Documentation only |
| `chore` | Deps, build tooling, no production effect |
| `ci` | CI/CD pipeline changes |
| `revert` | Reverts a prior commit |

### Examples

```bash
# ✅ Valid
git commit -m "feat(orders): add idempotency key validation"
git commit -m "fix(auth): reject expired tokens before redirect"
git commit -m "chore(deps): bump axios to 1.7.0"

# ✅ Breaking change
git commit -m "feat(api)!: require Authorization header on all endpoints

BREAKING CHANGE: All endpoints now require a Bearer token. Update clients to v2.x."

# ❌ Invalid — commitlint will reject these
git commit -m "updated stuff"
git commit -m "Fix bug"          # uppercase
git commit -m "feat: add thing." # trailing period
```

## Add a Scope

Edit `commitlint/commitlint.config.js` to add your service/module names to `scope-enum`:

```js
"scope-enum": [2, "always", [
  "api", "auth", "billing", "ci", "config",
  "db", "deps", "docs", "helm", "infra",
  "orders", "terraform", "ui",
]],
```

## GitHub Actions PR Title Lint

Add this to enforce Conventional Commits on PR titles:

```yaml
# .github/workflows/pr-title.yml
name: Lint PR title
on:
  pull_request:
    types: [opened, edited, synchronize]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: amannn/action-semantic-pull-request@v5.5.3
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## See Also

- [references/conventional-commits.md](../../references/conventional-commits.md) — full spec, type classification, breaking changes, semantic-release, validation rules
- `/platform-skills:commit` — analyze a diff and generate a commit message, stage files atomically, validate an existing message

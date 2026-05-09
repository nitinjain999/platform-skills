Status: Stable

# Conventional Commits Examples

Configuration and workflow examples for enforcing Conventional Commits.

## Examples

| Example | Type | Description |
|---------|------|-------------|
| [commitlint/](commitlint/) | Config | commitlint + husky setup with scope allow-list |

## Usage

```bash
# Install commitlint and husky
cd commitlint
npm install

# Test a commit message
echo "feat(auth): add OIDC login support" | npx commitlint

# Test a bad message
echo "updated stuff" | npx commitlint
```

## See Also

- [references/conventional-commits.md](../../references/conventional-commits.md) — spec, type classification, breaking changes, tooling, validation
- `/platform-skills:commit` — analyze diff, generate message, stage files, validate message

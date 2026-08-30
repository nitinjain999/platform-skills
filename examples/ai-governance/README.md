Status: Beta

# AI Governance Examples

Policy gate for AI coding agents (Copilot, Claude Code) — a real-time session hook that denies protected-path edits and dangerous commands, plus a merge-time GitHub Actions check that catches anything bypassing the hook.

## Examples

| Example | Description |
|---------|-------------|
| [ai-governance.yaml](ai-governance.yaml) | Sample policy — protected paths, denied commands, enforcement tier |
| [evaluate.sh](evaluate.sh) | The evaluator: one decision core, per-platform (Copilot/Claude/neutral) input normalization and output adapters |
| [tests/evaluate_test.sh](tests/evaluate_test.sh) | Table-driven bash tests, including documented `denied_commands` bypass cases. Wired into `tests/handbook-consistency.sh`, so it runs on every PR |
| [hooks/preToolUse.json](hooks/preToolUse.json) | Copilot session hook — real-time deny before a tool call executes |
| [hooks/postToolUse.json](hooks/postToolUse.json) | Copilot completion hook. The tool call has already run by this point, so no decision here can prevent it — `--event=postToolUse` short-circuits before the policy is read, appends one `completed` audit line, and exits 0. It does not re-evaluate the rules, which would otherwise double-count every violation under `audit`/`warn` |
| [claude-settings-snippet.json](claude-settings-snippet.json) | Claude Code hook entry — the three-level matcher-group shape `settings.json` actually requires. Merge into an existing `.claude/settings.json`, never overwrite |
| [ai-governance-check.yml](ai-governance-check.yml) | Merge-time required check — evaluates the PR diff using the **base branch's** evaluator and policy, not the PR's own copy. Also posts the `warn`-tier PR comment |

## Running it by hand

```bash
# Dry-run a rule against a would-be edit: neutral output, no audit-log write
echo '{"toolName":"edit","toolArgs":{"path":".github/workflows/release.yml","content":"x"}}' \
  | ./evaluate.sh --mode=hook --platform=none --policy=ai-governance.yaml

# Dry-run the whole diff in one pass
git diff -z --name-only main...HEAD \
  | ./evaluate.sh --mode=ci --platform=none --policy=ai-governance.yaml

bash tests/evaluate_test.sh
```

`protected_paths` only fires on write intent, so a `Read` against a protected path is allowed by design even under `enforcement: block`. Blocking reads is what gets a governance hook uninstalled.

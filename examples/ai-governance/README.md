Status: Beta

# AI Governance Examples

Policy gate for AI coding agents (Copilot, Claude Code) — a real-time session hook that denies protected-path edits and dangerous commands, plus a merge-time GitHub Actions check that catches anything bypassing the hook.

## Examples

| Example | Description |
|---------|-------------|
| [ai-governance.yaml](ai-governance.yaml) | Sample policy — protected paths, denied commands, enforcement tier |
| [evaluate.sh](evaluate.sh) | The evaluator: one decision core, per-platform (Copilot/Claude) input normalization and output adapters |
| [tests/evaluate_test.sh](tests/evaluate_test.sh) | Table-driven bash tests, including documented `denied_commands` bypass cases |
| [hooks/preToolUse.json](hooks/preToolUse.json) | Copilot session hook — real-time deny before a tool call executes |
| [hooks/postToolUse.json](hooks/postToolUse.json) | Copilot completion hook — the tool call has already run by this point, so a deny decision here can't prevent it; use `enforcement: audit`/`warn` if you only want this hook for completion logging, since `evaluate.sh` doesn't distinguish event types in its decision logic |
| [claude-settings-snippet.json](claude-settings-snippet.json) | Claude Code hook entry — merge into an existing `.claude/settings.json`, never overwrite |
| [ai-governance-check.yml](ai-governance-check.yml) | Merge-time required check — evaluates the PR diff using the **base branch's** evaluator and policy, not the PR's own copy |

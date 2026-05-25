# AWS Multi-Profile MCP Examples

**Status:** Stable

Working examples for managing AWS MCP servers across multiple accounts in VS Code and Claude Code.

## Files

| File | What it shows |
|------|--------------|
| `vscode-global-mcp.json` | `~/.vscode/mcp.json` — 1 always-on docs server, zero account risk |
| `vscode-workspace-mcp.json` | `.vscode/mcp.json` — eks-debug kit, hardcoded profile |
| `vscode-workspace-input-mcp.json` | `.vscode/mcp.json` — interactive profile picker via VS Code inputs |
| `vscode-mcp.json.template` | Commit this to git — placeholders, not real profile names |
| `claude-settings-snippet.json` | Paste into `~/.claude/settings.json` under `mcpServers` |
| `aws-config-credential-process.ini` | Add to `~/.aws/config` — structural fix for stale credentials |
| `.gitignore.snippet` | Add to your `.gitignore` |
| `starter-kits/eks-debug.json` | eks + cloudwatch, version-pinned |
| `starter-kits/observe.json` | cloudwatch + prometheus |
| `starter-kits/knowledge.json` | docs + bedrock-kb |
| `starter-kits/deploy.json` | aws-api + serverless |
| `starter-kits/cost.json` | billing (cost-management) |

## Quickstart

```bash
# 1. Discover your profiles
/platform-skills:aws-profile discover

# 2. Pick a starter kit and generate config
/platform-skills:mcp configure-aws eks-debug --profile dev-sandbox --region eu-west-1 --host both

# 3. Check credentials are healthy
/platform-skills:aws-profile status

# 4. When switching accounts
/platform-skills:aws-profile switch prod-platform-eu --scope workspace --confirm
```

## Team Onboarding

```bash
# Commit the template (not the real config)
git add .vscode/mcp.json.template
echo ".vscode/mcp.json" >> .gitignore
echo "!.vscode/mcp.json.template" >> .gitignore

# New engineer hydrates locally
AWS_PROFILE=dev-sandbox AWS_REGION=eu-west-1 \
  envsubst < .vscode/mcp.json.template > .vscode/mcp.json
```

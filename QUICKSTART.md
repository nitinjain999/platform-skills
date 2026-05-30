# Quick Start

Get platform-skills running in 2 minutes.

## Fastest path

```bash
git clone https://github.com/nitinjain999/platform-skills.git
cd platform-skills
./install.sh --all --target ../your-project
```

Use `--codex`, `--cursor`, `--copilot`, or `--claude` when you only want one integration.

---

## If you use GitHub Copilot (no Claude needed)

Copy one file into your project and commit it:

```bash
git clone https://github.com/nitinjain999/platform-skills.git
mkdir -p your-project/.github
cp platform-skills/.github/copilot-instructions.md your-project/.github/copilot-instructions.md
cd your-project && git add .github/copilot-instructions.md && git commit -m "chore: add platform-skills copilot instructions" && git push
```

Open Copilot Chat in VSCode (`Ctrl+Shift+I` / `Cmd+Shift+I`) and ask questions — the rules are active.

→ Full setup for Copilot, Cursor, JetBrains, and global vs project level: [EDITOR_INTEGRATIONS.md](EDITOR_INTEGRATIONS.md)

---

## If you use Claude Code

Install the plugin:

```bash
claude plugin marketplace add https://github.com/nitinjain999/platform-skills
claude plugin install platform-skills
```

Open Claude in your project:

```bash
cd your-project && claude
```

→ Full install options, verification, and troubleshooting: [INSTALLATION.md](INSTALLATION.md)

---

## If you use Codex

Install the repo as a local Codex skill:

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
git clone https://github.com/nitinjain999/platform-skills.git "${CODEX_HOME:-$HOME/.codex}/skills/platform-skills"
```

Open Codex in your project and ask:

```text
Use $platform-skills to review this Terraform change for ownership, blast radius, validation, and rollback.
```

→ Full install options, verification, and troubleshooting: [INSTALLATION.md](INSTALLATION.md)

---

## If you use Cursor

Copy the Cursor-native rules into your project and commit them:

```bash
git clone https://github.com/nitinjain999/platform-skills.git
cp platform-skills/.cursorrules your-project/.cursorrules
mkdir -p your-project/.cursor/rules
cp platform-skills/.cursor/rules/*.mdc your-project/.cursor/rules/
cd your-project && git add .cursorrules .cursor/rules && git commit -m "chore: add platform-skills cursor rules" && git push
```

Open Cursor Chat or Agent in that project and ask:

```text
Review this Kubernetes Deployment for production readiness.
```

→ Full Cursor setup, global rules, and troubleshooting: [EDITOR_INTEGRATIONS.md#cursor](EDITOR_INTEGRATIONS.md#cursor)

---

## First prompts to try

For a larger copy-paste library, see [PROMPTS.md](PROMPTS.md).

```
Review this Deployment for production readiness — flag security context, resource limits, and probe issues.
```

```
My Flux Kustomization is stuck NotReady. Help me debug it step by step.
```

```
Review this Terraform IAM policy for wildcard actions and SOC 2 gaps.
```

```
Generate a production-ready Helm chart for a Node.js service with HPA and NetworkPolicy.
```

---

## Where to go next

| I want to… | Go to |
|---|---|
| Use with Copilot, Cursor, or any IDE | [EDITOR_INTEGRATIONS.md](EDITOR_INTEGRATIONS.md) |
| Full install + troubleshooting | [INSTALLATION.md](INSTALLATION.md) |
| Understand how the skill works | [HOW_IT_WORKS.md](HOW_IT_WORKS.md) |
| Learn the ownership model | [GETTING_STARTED.md](GETTING_STARTED.md) |
| See all 31 commands with examples | [COMMANDS.md](COMMANDS.md) |
| Triage PR review comments | `/platform-skills:triage` |
| Scale workloads with KEDA | `/platform-skills:keda` |
| Browse reference guides | [references/](references/) |
| Copy working examples | [examples/](examples/) |

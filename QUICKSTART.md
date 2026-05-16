# Quick Start

Get platform-skills running in 2 minutes.

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

## First prompts to try

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
| See all 20 commands with examples | [COMMANDS.md](COMMANDS.md) |
| Triage PR review comments | `/platform-skills:triage` |
| Scale workloads with KEDA | `/platform-skills:keda` |
| Browse reference guides | [references/](references/) |
| Copy working examples | [examples/](examples/) |

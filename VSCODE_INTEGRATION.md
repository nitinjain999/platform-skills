# Platform Skills - VS Code Integration Guide

This guide shows how to use `platform-skills` in Visual Studio Code with Claude Code and, optionally, GitHub Copilot.

## Core Model

Use the tools for different jobs:

| Tool | Best for |
|------|----------|
| Claude Code + `platform-skills` | Architecture, troubleshooting, design reviews, GitOps boundaries, IAM, release flow |
| GitHub Copilot | Code completion, boilerplate, syntax help, repetitive edits |

## Install the Skill

Install `platform-skills` once. The same install works for terminal sessions and the VS Code extension.

### Marketplace install

Use this if the skill is already published:

```bash
claude-code skill search platform-skills
claude-code skill install platform-skills
```

### Local clone install

Use this if you want local customization or the skill is not yet published:

```bash
git clone https://github.com/nitinjain999/platform-skills.git
cd platform-skills
claude-code skill install .
```

## Option 1: Claude Code Extension in VS Code

1. Install the Claude Code extension from the VS Code extensions marketplace.
2. Open the Claude Code sidebar or command palette action.
3. Ask concrete platform questions against your repo.

Good prompts:

```text
Review this Kubernetes deployment for production readiness and point out the biggest operational risks first.
```

```text
My Flux reconciliation is failing in staging after a merge. Tell me the likely root causes and the first commands to run.
```

```text
Review this Terraform module for AWS IAM blast-radius problems and suggest safer defaults.
```

## Option 2: Copilot in Editor, Claude in Terminal

This is a strong default if you already use GitHub Copilot.

1. Use Copilot for code completion in the editor.
2. Open a split terminal in VS Code.
3. Run Claude in one terminal:

```bash
cd your-project
claude
```

4. Keep your normal shell workflow in the other terminal for `git`, `kubectl`, `terraform`, or `gh`.

Use Claude for:

- deciding whether Terraform or GitOps should own a change
- reviewing IAM or RBAC policy shape
- debugging Kubernetes, OpenShift, Flux, or Argo CD failures
- reviewing deployment workflow security

## Example Workflows

### Review a GitHub Actions workflow

1. Open the workflow in VS Code.
2. Ask Claude:

```text
Review this GitHub Actions workflow for OIDC, least privilege, and deployment safety issues. Tell me what should block merge versus what is advisory.
```

### Debug an Argo CD sync problem

1. Capture the app status and controller output.
2. Ask Claude:

```text
This Argo CD application is out of sync. Here is the manifest, sync status, and controller output. What is the most likely root cause and what evidence should I collect next?
```

### Design a multi-environment repo layout

1. Open your repo root in VS Code.
2. Ask Claude:

```text
I need a repo layout for AWS, Terraform, and either Flux or Argo CD across dev, staging, and production. Show me a structure with clear ownership boundaries.
```

## Recommended Prompt Pattern

Claude is most useful when you include:

- the platform you use
- the owning layer, if known
- the exact file or manifest
- the error text or risk
- the desired end state

## Troubleshooting

### The skill is not available in VS Code

Verify installation from a terminal:

```bash
claude-code skill search platform-skills
```

If the marketplace entry is not available yet, install from a local clone instead.

### Claude answers too generically

Provide more context:

- the file you are editing
- the namespace, cluster, or environment
- the exact failure message
- whether you use Flux or Argo CD

### Copilot and Claude feel redundant

Use Copilot for code generation and Claude for system judgment. If you ask both to do the same thing, the workflow gets noisy fast.

## Related Docs

- [GETTING_STARTED.md](GETTING_STARTED.md)
- [INSTALLATION.md](INSTALLATION.md)
- [README.md](README.md)
- [examples/](examples/)

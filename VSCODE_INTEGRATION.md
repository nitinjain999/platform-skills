# Platform Skills - VS Code Integration Guide

This guide shows how to use `platform-skills` in Visual Studio Code in two supported ways:

1. with Claude Code
2. without Claude, using GitHub Copilot plus the handbook

## Core Model

Use the tools for different jobs:

| Tool | Best for |
|------|----------|
| Claude Code + `platform-skills` plugin | Architecture, troubleshooting, design reviews, GitOps boundaries, IAM, release flow |
| GitHub Copilot + handbook | Code completion, scaffolding, repo-local generation guided by documented platform rules |

## Option 1: VS Code with Claude

Use this when Claude Code is allowed in your environment and you want interactive architecture and troubleshooting help inside the editor or terminal.

### Install the Plugin

Install `platform-skills` once. The same plugin install works for terminal sessions and the VS Code extension.

### Marketplace install

Use this if the plugin is already published:

```bash
claude plugin marketplace add https://github.com/nitinjain999/platform-skills
claude plugin install platform-skills
```

### Local clone install

Use this if you want local customization or the plugin is not yet published:

```bash
git clone https://github.com/nitinjain999/platform-skills.git
cd platform-skills
claude plugin install .
```

### Claude Code Extension in VS Code

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

### Copilot in Editor, Claude in Terminal

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

## Option 2: VS Code Without Claude

Use this when your team cannot use Claude, does not have access to Claude, or wants to standardize on GitHub Copilot only.

In this mode, `platform-skills` works as a handbook and prompt source:

1. Clone the repository locally:

```bash
git clone https://github.com/nitinjain999/platform-skills.git
cd platform-skills
code .
```

2. Use the handbook directly:

- [README.md](README.md) for navigation
- [references/](references/) for platform guidance
- [examples/](examples/) for manifests, workflows, and Terraform snippets
- [.github/copilot-instructions.md](.github/copilot-instructions.md) for GitHub Copilot guidance

3. Keep GitHub Copilot enabled in VS Code for:

- code completion
- manifest and workflow scaffolding
- adapting examples to your repo
- applying repo-local guidance from `.github/copilot-instructions.md`

### Copilot-only workflow

Open your project and this handbook side by side in VS Code. Then:

1. Read the relevant reference file first.
2. Open the matching example file.
3. Ask Copilot to adapt it to your repo, environment, and naming.
4. Review the generated output against the handbook rules before committing.

### Good Copilot prompts

Ask Copilot to use the repo rules explicitly.

```text
Using .github/copilot-instructions.md and references/terraform.md, generate a Terraform module layout for an EKS cluster with clear separation between reusable modules and environment state.
```

```text
Using examples/kubernetes/deployment-baseline.yaml and references/kubernetes.md, generate a production-ready Deployment for this service and keep the security context locked down.
```

```text
Using references/github-actions.md and .github/copilot-instructions.md, review this workflow for OIDC, permissions, and unsafe triggers.
```

### What Copilot can and cannot replace

Use Copilot for:

- generating first drafts
- refactoring boilerplate
- applying patterns from this repo to concrete files

Do not rely on Copilot alone for:

- final ownership-boundary decisions
- security-sensitive IAM design without review
- deciding whether Terraform, Kubernetes, Flux, or Argo CD should own a resource

For those decisions, use the handbook references as the source of truth.

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

Claude or Copilot is most useful when you include:

- the platform you use
- the owning layer, if known
- the exact file or manifest
- the error text or risk
- the desired end state

## Troubleshooting

### The plugin is not available in VS Code

Verify installation from a terminal:

```bash
claude plugin list
```

If `platform-skills` is not listed, install it:

```bash
claude plugin marketplace add https://github.com/nitinjain999/platform-skills
claude plugin install platform-skills
```

Or install from a local clone if it is not yet published.

### Claude is not available in my organization

Use the Copilot-only workflow in this guide.

The minimum setup is:

1. clone the repository
2. open it in VS Code
3. keep [references/](references/) and [examples/](examples/) open while working
4. let Copilot use [.github/copilot-instructions.md](.github/copilot-instructions.md) as the repo guidance file

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

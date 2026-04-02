# Platform Skills - Quick Start

## Step 1: Confirm Claude Code

```bash
claude --version
```

If Claude Code is not installed, visit: https://claude.ai/code

## Step 2: Install the Plugin

### From Marketplace

Add the marketplace, then install:

```bash
claude plugin marketplace add https://github.com/nitinjain999/platform-skills
claude plugin install platform-skills
```

### From Local Clone

Use this if you want the repo immediately or need local customization:

```bash
git clone https://github.com/nitinjain999/platform-skills.git
cd platform-skills
claude plugin install .
```

## Step 3: Use It

Open Claude Code in your project:

```bash
cd your-project
claude
```

Then ask a concrete prompt:

```text
Review this Terraform layout for EKS and tell me what should stay in Terraform versus GitOps.
```

```text
My Argo CD application is out of sync after a merge. Help me find the most likely cause first.
```

```text
Review this GitHub Actions workflow for deployment security issues.
```

## VS Code Workflow

- Use the Claude Code extension for chat and inline help inside VS Code.
- Use GitHub Copilot for code completion.
- Use Claude plus `platform-skills` for architecture, troubleshooting, and review.

See [VSCODE_INTEGRATION.md](VSCODE_INTEGRATION.md) for the full workflow.

## Need More?

- [GETTING_STARTED.md](GETTING_STARTED.md)
- [INSTALLATION.md](INSTALLATION.md)
- [README.md](README.md)
- [examples/](examples/)

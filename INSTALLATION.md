# Platform Skills - Installation Guide

This guide covers installation of `platform-skills` as a Claude plugin. If you only want to browse the handbook guides and examples, no installation is needed. Navigate directly to [references/](references/) or [examples/](examples/) on GitHub.

## Prerequisites

Confirm Claude Code is installed:

```bash
claude --version
```

If Claude Code is not installed, visit: https://claude.ai/code

## Installation Methods

### Method 1: Install from Marketplace

Add the marketplace, then install by name:

```bash
claude plugin marketplace add https://github.com/nitinjain999/platform-skills
claude plugin install platform-skills
```

**Upgrade** when a new version is released:

```bash
claude plugin marketplace update
claude plugin install platform-skills
```

**Uninstall:**

```bash
claude plugin uninstall platform-skills
```

### Method 2: Install from Local Clone

Use this when you want local customization or want the latest repo state before marketplace publication:

```bash
git clone https://github.com/nitinjain999/platform-skills.git
cd platform-skills
claude plugin install .
```

### Method 3: Use the Repo Without Installing

You can also use this repository directly as reference material:

- read [README.md](README.md)
- read [SKILL.md](SKILL.md)
- use the content under `references/`
- adapt examples from `examples/`

## Verify Installation

After installation, open Claude Code in your project:

```bash
cd your-project
claude
```

Then ask something concrete:

```text
Review this Terraform layout and tell me what Terraform should own versus what Flux or Argo CD should own.
```

```text
My OpenShift deployment is failing after a GitOps sync. Help me narrow the likely cause from the manifest and events.
```

```text
Review this GitHub Actions workflow for OIDC, least privilege, and unsafe trigger choices.
```

## Troubleshooting

### Marketplace Install Fails

If `claude plugin install platform-skills` fails with "not found":

1. Make sure the marketplace was added first:
   ```bash
   claude plugin marketplace add https://github.com/nitinjain999/platform-skills
   claude plugin install platform-skills
   ```
2. If the plugin is not yet published to the marketplace, install from a local clone:
   ```bash
   git clone https://github.com/nitinjain999/platform-skills.git
   cd platform-skills
   claude plugin install .
   ```

### Local Install Fails

Make sure you are running the install from the cloned repository root:

```bash
pwd
ls SKILL.md .claude-plugin/marketplace.json
```

Then run:

```bash
claude plugin install .
```

### The Plugin Feels Too Generic

Give Claude:

- the exact file or manifest
- the cluster or environment
- the tool boundary involved
- the exact error text
- the desired end state

## Related Docs

- [GETTING_STARTED.md](GETTING_STARTED.md)
- [QUICKSTART.md](QUICKSTART.md)
- [VSCODE_INTEGRATION.md](VSCODE_INTEGRATION.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

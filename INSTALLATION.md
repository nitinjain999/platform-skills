# Platform Skills - Installation Guide

This guide covers installation of `platform-skills` as a Claude Code skill. If you only want to browse the handbook guides and examples, no installation is needed — navigate directly to [references/](references/) or [examples/](examples/) on GitHub.

## Prerequisites

Confirm Claude Code is installed:

```bash
claude-code --version
```

If Claude Code is not installed, visit: https://claude.ai/code

## Installation Methods

### Method 1: Install from Marketplace

Use this when `platform-skills` is already published:

```bash
claude-code skill search platform-skills
claude-code skill install platform-skills
```

Update or remove it later with:

```bash
claude-code skill update platform-skills
claude-code skill uninstall platform-skills
```

### Method 2: Install from Local Clone

Use this when you want local customization or want the latest repo state before marketplace publication:

```bash
git clone https://github.com/nitinjain999/platform-skills.git
cd platform-skills
claude-code skill install .
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

If `claude-code skill install platform-skills` fails:

1. Check whether the skill is published:
   ```bash
   claude-code skill search platform-skills
   ```
2. If it is not available yet, install from a local clone:
   ```bash
   git clone https://github.com/nitinjain999/platform-skills.git
   cd platform-skills
   claude-code skill install .
   ```

### Local Install Fails

Make sure you are running the install from the cloned repository root:

```bash
pwd
ls SKILL.md .claude-plugin/marketplace.json
```

Then run:

```bash
claude-code skill install .
```

### The Skill Feels Too Generic

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

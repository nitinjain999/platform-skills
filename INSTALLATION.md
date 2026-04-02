# Platform Skills - Installation Guide

This guide will help you install and use Platform Skills, a comprehensive Claude Agent Skill for platform engineering.

## Prerequisites

You need Claude Code installed. Check your installation:

```bash
claude --version
```

If Claude Code is not installed, visit: https://claude.ai/code

## Installation Methods

### Method 1: From Personal Marketplace (Recommended)

This is the fastest way to install Platform Skills:

```bash
# Step 1: Add the marketplace
claude plugin marketplace add https://github.com/nitinjain999/platform-skills

# Step 2: Install the plugin
claude plugin install platform-skills

# Step 3: Verify installation
claude plugin list
```

You should see:
```
✔ platform-skills@platform-skills-marketplace
  Version: 1.0.0
  Status: enabled
```

### Method 2: From Local Clone

If you want to customize the plugin or install from a local copy:

```bash
# Clone the repository
git clone https://github.com/nitinjain999/platform-skills.git
cd platform-skills

# Install from local directory
claude plugin install .
```

### Method 3: Direct GitHub Repository

Claude Code can also install directly from GitHub:

```bash
claude plugin install https://github.com/nitinjain999/platform-skills
```

## Verify Installation

After installation, verify the plugin is active:

```bash
claude plugin list
```

You should see `platform-skills` in the list with status "enabled".

## Using Platform Skills

Once installed, Platform Skills automatically activates when you work with:

- **Kubernetes** - Cluster baselines, workload patterns, troubleshooting
- **OpenShift** - Routes, security contexts, operators
- **Argo CD** - Application design, sync policies, multi-cluster
- **Flux CD** - Reconciliation issues, GitOps patterns
- **AWS** - EKS, IAM policies, infrastructure design
- **Azure** - AKS, managed identities, resource management
- **Terraform** - Module design, state management, validation
- **GitHub Actions** - Workflow security, optimization

### Example Usage

Start Claude Code in your project directory:

```bash
cd your-project/
claude
```

Then ask questions like:

**Flux CD Troubleshooting:**
```
My HelmRelease is stuck in "Reconciling" state. 
The logs show "chart pull failed: failed to get chart version"
```

**AWS IAM Review:**
```
Review this IAM policy for security issues:
{
  "Effect": "Allow",
  "Action": "s3:*",
  "Resource": "*"
}
```

**Terraform Module Design:**
```
I'm building a reusable EKS module. Should I expose every parameter 
or have opinionated defaults? How do I handle optional add-ons?
```

**GitHub Actions Security:**
```
Is it safe to use pull_request_target for this workflow that 
runs linters on contributor PRs?
```

**Argo CD App Design:**
```
Should I use app-of-apps or ApplicationSet for multi-cluster platform add-ons,
and how do I keep Argo CD projects scoped safely?
```

Claude will automatically use Platform Skills to provide expert guidance with:
- Root-cause analysis
- Production-ready solutions
- Security best practices
- Rollback plans
- Prevention strategies

## Checking Plugin Status

```bash
# List all installed plugins
claude plugin list

# List available marketplaces
claude plugin marketplace list

# Update plugin to latest version
claude plugin update platform-skills
```

## Uninstalling

If you need to remove Platform Skills:

```bash
claude plugin uninstall platform-skills
```

To remove the marketplace:

```bash
claude plugin marketplace remove platform-skills-marketplace
```

## Updating to Latest Version

When a new version is released:

```bash
# Update the marketplace cache
claude plugin marketplace update

# Update the plugin
claude plugin update platform-skills
```

Or with Renovate (if configured), updates will be proposed automatically.

## Troubleshooting

### Plugin Not Found

If `claude plugin install platform-skills` fails with "plugin not found":

1. Ensure the marketplace is added:
   ```bash
   claude plugin marketplace add https://github.com/nitinjain999/platform-skills
   ```

2. Refresh marketplace cache:
   ```bash
   claude plugin marketplace update
   ```

3. Try installation again

### Plugin Not Activating

If the plugin is installed but not providing guidance:

1. Check plugin is enabled:
   ```bash
   claude plugin list
   ```

2. If disabled, enable it:
   ```bash
   claude plugin enable platform-skills
   ```

3. Restart Claude Code

### Permission Issues

If you get permission errors during installation:

1. Check you have write access to `~/.claude/plugins/`
2. Try with appropriate permissions
3. Contact your system administrator if needed

## Getting Help

- **Documentation**: https://github.com/nitinjain999/platform-skills
- **Issues**: https://github.com/nitinjain999/platform-skills/issues
- **Discussions**: https://github.com/nitinjain999/platform-skills/discussions
- **Examples**: See `examples/` directory in the repository

## What's Included

Platform Skills provides:

- **8 Domain Coverage**: Kubernetes, OpenShift, Argo CD, Flux CD, AWS, Azure, Terraform, GitHub Actions
- **Reference Guides**: Deep-dive documentation for each domain
- **Working Examples**: Copy-paste-able code for common patterns
- **Troubleshooting Framework**: Systematic approach to diagnosing issues
- **Security Patterns**: Least-privilege IAM, network policies, secret management
- **Production Best Practices**: Blast radius awareness, rollback plans, validation steps

## Contributing

Want to improve Platform Skills? See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Apache-2.0 - See [LICENSE](LICENSE) for details.

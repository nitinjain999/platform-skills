# Platform Skills - Quick Start (5 Minutes)

## Step 1: Install Claude Code CLI

Check if you have it:
```bash
claude --version
```

If not installed, visit: https://claude.ai/code

## Step 2: Install Platform Skills

Copy and paste these commands:

```bash
# Add the marketplace
claude plugin marketplace add https://github.com/nitinjain999/platform-skills

# Install the plugin
claude plugin install platform-skills

# Verify it worked
claude plugin list
```

✅ You should see: `platform-skills@platform-skills-marketplace` with status "enabled"

## Step 3: Use It!

**Option A: VSCode with Claude Code Extension** (Full integration)
1. Open VSCode
2. Install Claude Code extension from marketplace
3. Click Claude icon in sidebar or press Cmd+Shift+P → "Claude Code"
4. Start asking questions!

**Option B: VSCode with Just Copilot** (Split screen)
1. Open VSCode with GitHub Copilot
2. Split terminal (split icon in terminal)
3. Left terminal: your work (git, kubectl, etc)
4. Right terminal: `claude` for guidance
5. Use Copilot for code, Claude for architecture

**Option C: Terminal Only**
```bash
cd your-project/
claude
```

> **💡 Tip**: Works great with GitHub Copilot! Use Copilot for code completion, Claude + Platform Skills for architecture and troubleshooting. See [VSCODE_INTEGRATION.md](VSCODE_INTEGRATION.md) for detailed workflows.

## Try These Examples

**Example 1: Fix a Flux CD Issue**
```
My HelmRelease won't deploy. It's stuck showing:
"Reconciling" status for 10+ minutes
Error in logs: "chart pull failed"
```

**Example 2: Review IAM Security**
```
Review this IAM policy for security issues:
{
  "Effect": "Allow", 
  "Action": "s3:*",
  "Resource": "*"
}
```

**Example 3: Terraform Module Help**
```
I need to build a reusable EKS module.
Should I expose all parameters or use opinionated defaults?
```

**Example 4: GitHub Actions Security**
```
Is pull_request_target safe for running linters on external PRs?
```

## What You Get

Platform Skills provides expert guidance for:

- ☸️ **Kubernetes** - Baselines, workloads, policies
- 🟥 **OpenShift** - Routes, SCCs, operators  
- 🔄 **Flux CD** - GitOps troubleshooting
- 🚢 **Argo CD** - Application design, sync control
- ☁️ **AWS** - EKS, IAM hardening, service selection
- 🌐 **Azure** - AKS, managed identities, RBAC
- 🏗️ **Terraform** - Module design, state management
- 🚀 **GitHub Actions** - Security, optimization

## How It Works

The plugin activates automatically when you:
- Work with Kubernetes/OpenShift manifests
- Troubleshoot GitOps reconciliation
- Write Terraform modules
- Review GitHub Actions workflows
- Design AWS/Azure infrastructure
- Debug platform issues

You get:
- ✅ Root-cause analysis (not just symptoms)
- ✅ Production-ready solutions
- ✅ Security best practices
- ✅ Rollback plans for risky changes
- ✅ Working code examples

## Need More?

- **Full Guide**: See [INSTALLATION.md](INSTALLATION.md)
- **Documentation**: https://github.com/nitinjain999/platform-skills
- **Examples**: Browse `examples/` directory
- **Issues**: Report at https://github.com/nitinjain999/platform-skills/issues

---

That's it! You're ready to use Platform Skills. 🚀

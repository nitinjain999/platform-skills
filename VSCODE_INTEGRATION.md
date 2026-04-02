# Platform Skills - VSCode Integration Guide

This guide shows how to use Platform Skills in Visual Studio Code, both with Claude Code extension and alongside GitHub Copilot.

## Overview

**Platform Skills** provides expert platform engineering guidance through Claude Code, while **GitHub Copilot** offers code completion. They complement each other:

| Tool | Purpose | Use For |
|------|---------|---------|
| **Claude Code + Platform Skills** | Architecture, troubleshooting, design decisions | System design, debugging complex issues, reviewing IAM policies, GitOps patterns |
| **GitHub Copilot** | Code completion, snippets | Writing individual functions, boilerplate code, quick syntax help |

## Option 1: Claude Code VSCode Extension (Recommended)

### Installation

1. **Install Claude Code Extension**
   - Open VSCode
   - Go to Extensions (Cmd+Shift+X / Ctrl+Shift+X)
   - Search for "Claude Code"
   - Click Install
   - Sign in with your Anthropic account

2. **Install Platform Skills Plugin**

   Open VSCode Terminal (Ctrl+` or Cmd+`) and run:

   ```bash
   # Add marketplace
   claude plugin marketplace add https://github.com/nitinjain999/platform-skills
   
   # Install plugin
   claude plugin install platform-skills
   
   # Verify
   claude plugin list
   ```

3. **Verify Installation**
   
   The plugin is now available in all Claude Code sessions within VSCode.

### Using in VSCode

#### Method A: Claude Code Panel (Recommended)

1. **Open Claude Code Panel**:
   - Click the Claude icon in the VSCode sidebar
   - Or press: `Cmd+Shift+P` → "Claude Code: Open Chat"

2. **Ask Platform Engineering Questions**:

   **Example 1: Review Kubernetes Manifest**
   ```
   Review this deployment.yaml for production readiness:
   [Select code and paste or reference file]
   ```

   **Example 2: Troubleshoot Flux CD**
   ```
   My Flux HelmRelease in staging namespace is failing.
   Here are the logs: [paste logs]
   What's the root cause?
   ```

   **Example 3: Design IAM Policy**
   ```
   I need an IAM policy for an EKS pod to read from S3 bucket "prod-configs".
   Show me a least-privilege policy using IRSA.
   ```

#### Method B: Inline with Cmd+K (Quick Edits)

1. Select code in your editor
2. Press `Cmd+K` (Mac) or `Ctrl+K` (Windows/Linux)
3. Type your request:
   ```
   Make this Terraform module follow AWS best practices
   ```

#### Method C: Context Menu

1. Right-click on a file or selected code
2. Choose "Ask Claude Code"
3. Ask questions like:
   ```
   Explain how this Argo CD ApplicationSet works
   ```

### Workflow Examples in VSCode

#### Workflow 1: Debugging Kubernetes Issues

```
1. Terminal shows pod crash
2. Open Claude Code panel
3. Ask: "Pod my-app in namespace staging is CrashLoopBackOff. 
   How do I systematically debug this?"
4. Platform Skills provides structured troubleshooting
5. Execute suggested commands in VSCode terminal
6. Iterate with Claude based on results
```

#### Workflow 2: Reviewing Infrastructure Code

```
1. Open terraform/main.tf
2. Select IAM policy code
3. Cmd+K → "Review this IAM policy for security issues"
4. Claude highlights wildcard resources
5. Suggests least-privilege alternatives
6. Apply fixes inline
```

#### Workflow 3: Designing GitOps Structure

```
1. Create new flux/ directory
2. Open Claude Code chat
3. Ask: "I need to structure a Flux CD monorepo for 3 environments.
   Show me the directory layout with Kustomize overlays."
4. Claude provides structure based on examples/
5. Create files following guidance
6. Ask follow-up: "How do I handle secrets with SOPS?"
```

---

## Option 2: VSCode with Just Copilot (No Claude Extension)

If you prefer to use only GitHub Copilot in VSCode and access Platform Skills separately, here's the workflow:

### Setup

1. **Install GitHub Copilot** (if not already installed):
   - VSCode Extensions → Search "GitHub Copilot"
   - Install and sign in

2. **Install Platform Skills CLI**:
   
   Open VSCode Terminal (Ctrl+` or Cmd+`):
   ```bash
   # Install plugin
   claude plugin marketplace add https://github.com/nitinjain999/platform-skills
   claude plugin install platform-skills
   ```

### Workflow: Split Screen Approach

**Layout:**
```
┌─────────────────────┬─────────────────────┐
│                     │                     │
│   VSCode Editor     │  Terminal: Claude   │
│   (with Copilot)    │  (Platform Skills)  │
│                     │                     │
└─────────────────────┴─────────────────────┘
```

**Steps:**

1. **Split VSCode Terminal**:
   - Open terminal: Ctrl+` or Cmd+`
   - Click split terminal icon (+▼ dropdown → Split)
   - Left terminal: Your work (git, kubectl, terraform)
   - Right terminal: `claude` for guidance

2. **Start Claude in Right Terminal**:
   ```bash
   claude
   ```

3. **Work in Editor with Copilot**:
   - Write code with Copilot autocomplete
   - When you need architecture/design help, ask Claude in right terminal
   - Copy Claude's suggestions back to editor

### Example Workflows

#### Workflow 1: Building Terraform Module

**VSCode Editor (Left):**
```hcl
# main.tf - Type with Copilot
resource "aws_eks_cluster" "main" {
  # Copilot suggests fields
}
```

**Claude Terminal (Right):**
```
Me: I'm building an EKS module. Should I expose all AWS parameters 
    or use opinionated defaults?

Claude: [Platform Skills guidance]
- Expose: cluster_version, instance_types, min/max sizes
- Default: encryption (always enabled), logging (all types)
- Reason: Balance flexibility with safety...
```

**Back to Editor:** Implement based on guidance, use Copilot for syntax

#### Workflow 2: Debugging Kubernetes

**VSCode Editor:** View pod YAML

**Left Terminal:**
```bash
kubectl logs my-pod -n production
# Copy error output
```

**Claude Terminal (Right):**
```
Me: My pod shows this error:
[paste error]

Claude: [Structured troubleshooting]
Symptom: ImagePullBackOff
Evidence to collect: kubectl describe pod...
Root cause: ...
Fix: ...
```

**Left Terminal:** Execute suggested commands

#### Workflow 3: Reviewing IAM Policy

**VSCode Editor:** Select IAM policy code

**Claude Terminal:**
```
Me: Review this IAM policy:
{
  "Effect": "Allow",
  "Action": "s3:*",
  "Resource": "*"
}

Claude: [Security analysis]
🚨 Issues:
1. Wildcard action (s3:*) grants excessive permissions
2. Wildcard resource allows access to all buckets
...
```

**VSCode Editor:** Fix with Copilot autocomplete

### Alternative: Browser + VSCode

**Layout:**
```
┌─────────────────────┬─────────────────────┐
│                     │                     │
│   VSCode Editor     │  Browser: claude.ai │
│   (with Copilot)    │  (Platform Skills)  │
│                     │                     │
└─────────────────────┴─────────────────────┘
```

1. **Open claude.ai in browser**
2. **Install Platform Skills** (same commands in your terminal)
3. **Use browser for Claude conversations**
4. **Use VSCode + Copilot for coding**

**Benefits:**
- No VSCode extension needed
- Easier to copy/paste large code blocks
- Can save conversation history in browser
- Works on any device

### Keyboard Workflow Tips

**For Quick Context Switching:**

1. **VSCode → Terminal**: Ctrl+` or Cmd+`
2. **Focus Right Terminal**: Ctrl+Shift+5 (or click)
3. **Copy from Terminal**: Select text, Ctrl+C
4. **Paste to Editor**: Click editor, Ctrl+V

**Custom VSCode Tasks** (optional):

Create `.vscode/tasks.json`:
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Ask Claude",
      "type": "shell",
      "command": "echo 'Type your question:' && read question && echo \"$question\" | claude --print",
      "presentation": {
        "reveal": "always",
        "panel": "dedicated"
      }
    }
  ]
}
```

### When to Use Which Tool

**Use Copilot for:**
- ✅ Autocompleting resource blocks
- ✅ Generating YAML structure
- ✅ Writing function implementations
- ✅ Quick syntax help
- ✅ Boilerplate code

**Ask Claude (Platform Skills) for:**
- ✅ "Should I use Flux or Argo CD?"
- ✅ "How do I structure my Terraform state?"
- ✅ "What's wrong with this IAM policy?"
- ✅ "Why is my HelmRelease failing?"
- ✅ "Design a multi-region EKS architecture"

### Pros and Cons

**Pros of Copilot-Only Approach:**
- ✅ Lighter VSCode (no Claude extension)
- ✅ Copilot is faster for code completion
- ✅ Can use Claude in browser or separate terminal
- ✅ More screen real estate for code

**Cons:**
- ❌ Context switching between windows
- ❌ Manual copy/paste of code
- ❌ No inline Claude suggestions in editor
- ❌ Claude can't automatically see your files

**Best For:**
- Developers who prefer minimal extensions
- Those already using claude.ai in browser
- Teams with Copilot licenses but evaluating Claude
- When you want separation between coding and architecture discussions

---

## Option 3: Claude Code CLI in VSCode Terminal (Full Integration)

For complete integration without leaving VSCode, use Claude CLI directly in terminal:

### Setup

1. **Open VSCode Terminal**: `Ctrl+\`` or `Cmd+\``

2. **Start Claude Code**:
   ```bash
   claude
   ```

3. **Ask Questions**:
   ```
   How should I structure my Terraform modules for a multi-account AWS setup?
   ```

### Benefits of CLI Approach

- Full conversation history
- Better for complex multi-step tasks
- Can execute commands and show output to Claude
- Persistent sessions with `claude --continue`

---

## Using with GitHub Copilot (Complementary)

Platform Skills and GitHub Copilot work great together! Here's how:

### Division of Labor

**Use GitHub Copilot for:**
- ✅ Writing individual Terraform resources
- ✅ Generating Kubernetes YAML boilerplate
- ✅ Quick function implementations
- ✅ Autocompleting configurations

**Use Claude Code + Platform Skills for:**
- ✅ Designing overall architecture
- ✅ Troubleshooting complex issues
- ✅ Reviewing security policies
- ✅ Explaining root causes
- ✅ Multi-file refactoring
- ✅ System design decisions

### Example Combined Workflow

**Scenario: Building an EKS Cluster with Terraform**

1. **Design with Claude Code** (Cmd+Shift+P → Claude):
   ```
   I need to build a production EKS cluster with:
   - Private subnets
   - IRSA for pod authentication
   - Managed node groups
   - EBS CSI driver
   
   What's the recommended module structure?
   ```
   
   Claude provides architecture guidance using Platform Skills patterns.

2. **Implement with Copilot**:
   - Create `main.tf`
   - Start typing: `resource "aws_eks_cluster" "main" {`
   - Copilot suggests the resource block
   - Continue with Copilot autocomplete for standard fields

3. **Review with Claude Code**:
   - Select the completed Terraform code
   - Cmd+K → "Review this EKS configuration for production readiness"
   - Claude checks: security groups, encryption, logging, IAM roles
   - Identifies issues: missing KMS encryption, wildcard security groups

4. **Fix with Copilot**:
   - Add KMS block (Copilot suggests structure)
   - Tighten security groups (Copilot completes)

5. **Validate with Claude Code**:
   ```
   Does this configuration follow AWS best practices?
   Are there any security risks?
   ```

---

## Keyboard Shortcuts (VSCode)

Configure these for faster access:

### Recommended Shortcuts

```json
// In VSCode: Preferences → Keyboard Shortcuts → Open JSON
{
  // Open Claude Code chat
  "key": "cmd+shift+c",
  "command": "claude.openChat"
},
{
  // Quick inline edit
  "key": "cmd+k",
  "command": "claude.quickEdit",
  "when": "editorTextFocus"
},
{
  // Explain selected code
  "key": "cmd+shift+e",
  "command": "claude.explainCode",
  "when": "editorHasSelection"
}
```

---

## Workspace-Specific Configuration

You can configure Claude Code per workspace:

### Create `.vscode/settings.json`:

```json
{
  "claude.plugins": {
    "platform-skills": {
      "enabled": true
    }
  },
  "claude.context": {
    "includeFiles": [
      "**/*.yaml",
      "**/*.yml", 
      "**/*.tf",
      "**/*.hcl",
      "**/Dockerfile",
      "**/.github/workflows/*.yml"
    ]
  }
}
```

This ensures Claude has relevant context for platform engineering tasks.

---

## Team Setup (Share with Colleagues)

### Create `.vscode/extensions.json`:

```json
{
  "recommendations": [
    "anthropic.claude-code",
    "github.copilot",
    "hashicorp.terraform",
    "redhat.vscode-yaml",
    "ms-kubernetes-tools.vscode-kubernetes-tools"
  ]
}
```

### Create `docs/CLAUDE_SETUP.md` in your repo:

```markdown
# Team Claude Code Setup

## Install Platform Skills

\`\`\`bash
claude plugin marketplace add https://github.com/nitinjain999/platform-skills
claude plugin install platform-skills
\`\`\`

## Usage
- Use Claude Code for architecture decisions and troubleshooting
- Use GitHub Copilot for code completion
- See [VSCODE_INTEGRATION.md](../VSCODE_INTEGRATION.md) for details
```

---

## Common Workflows

### 1. Reviewing Pull Requests

```
1. Open PR diff in VSCode
2. Select changed Terraform/Kubernetes files
3. Ask Claude: "Review these changes for security and best practices"
4. Claude identifies issues using Platform Skills knowledge
5. Add review comments or fix inline
```

### 2. Debugging Production Issues

```
1. Terminal: kubectl logs my-pod
2. Copy error logs
3. Claude chat: "This pod is failing with [paste logs]. 
   What's the root cause and how do I fix it?"
4. Get structured troubleshooting with blast radius awareness
```

### 3. Creating New Infrastructure

```
1. Claude chat: "I need a Terraform module for RDS with:
   - Multi-AZ
   - Encrypted
   - Read replicas
   What's the best structure?"
2. Claude provides module design
3. Use Copilot to implement the code
4. Claude reviews the final code
```

---

## Troubleshooting

### Plugin Not Activating in VSCode

**Issue**: Claude doesn't seem to use Platform Skills

**Solutions**:

1. **Verify plugin is installed**:
   ```bash
   claude plugin list
   ```

2. **Restart VSCode** after plugin installation

3. **Check VSCode Output**:
   - View → Output
   - Select "Claude Code" from dropdown
   - Look for plugin loading messages

4. **Manually trigger**:
   - In chat, explicitly say: "Using platform-skills patterns, help me..."

### VSCode Extension vs CLI

**Issue**: Plugin works in CLI but not VSCode extension

**Solution**: Both share the same plugin installation. If it works in CLI, it should work in extension. Try:

```bash
# Reinstall
claude plugin uninstall platform-skills
claude plugin install platform-skills

# Restart VSCode
```

---

## Best Practices

### 1. Start Sessions with Context

```
I'm working on:
- EKS cluster in eu-central-1
- Flux CD for GitOps
- Terraform for infrastructure
- Need help with [specific issue]
```

### 2. Use Copilot for Syntax, Claude for Decisions

**Bad**:
- Asking Copilot: "Should I use Flux or Argo CD?"
- Asking Claude: "Complete this YAML syntax"

**Good**:
- Asking Claude: "Should I use Flux or Argo CD for my multi-tenant platform?"
- Using Copilot: To autocomplete YAML structure

### 3. Reference Files

```
See flux/kustomization.yaml in this workspace.
How do I add a new application following the same pattern?
```

---

## Resources

- **Claude Code Docs**: https://docs.anthropic.com/claude/docs
- **Platform Skills Repo**: https://github.com/nitinjain999/platform-skills
- **VSCode Extension**: Search "Claude Code" in VSCode marketplace
- **Keyboard Shortcuts**: VSCode → Preferences → Keyboard Shortcuts → Search "claude"

---

## Summary

**For Developers Using VSCode:**

1. ✅ Install Claude Code extension
2. ✅ Install platform-skills plugin via CLI
3. ✅ Use Claude for architecture/design decisions
4. ✅ Use Copilot for code completion
5. ✅ Leverage both together for maximum productivity

**Quick Command Reference:**

```bash
# Install
claude plugin marketplace add https://github.com/nitinjain999/platform-skills
claude plugin install platform-skills

# Use in VSCode
- Open Claude chat: Cmd+Shift+P → "Claude Code"
- Quick edit: Select code → Cmd+K
- CLI mode: Terminal → claude

# Verify
claude plugin list
```

Happy platform engineering! 🚀

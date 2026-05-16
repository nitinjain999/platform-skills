# Using Platform Skills in Your Editor

Platform skills works with any editor and any AI assistant. Pick your setup below.

**No Claude required** — all options below work with GitHub Copilot alone.

---

## Quick start — 2 minutes, any OS

The fastest way to get platform engineering rules into any Copilot Chat session:

```bash
# 1. Clone platform-skills
git clone https://github.com/nitinjain999/platform-skills.git

# 2. Copy the instructions file into your project
# macOS / Linux
cp platform-skills/.github/copilot-instructions.md your-project/.github/copilot-instructions.md

# Windows (Command Prompt)
copy platform-skills\.github\copilot-instructions.md your-project\.github\copilot-instructions.md

# Windows (PowerShell)
Copy-Item platform-skills\.github\copilot-instructions.md your-project\.github\copilot-instructions.md

# 3. Commit it so every team member gets it automatically
cd your-project
git add .github/copilot-instructions.md
git commit -m "chore: add platform-skills copilot instructions"
git push
```

Done. Open Copilot Chat in any editor — the rules are active.

---

## GitHub Copilot in VSCode

### Project level — one file, all team members

Copilot reads `.github/copilot-instructions.md` from your repository root automatically.
Every developer who opens the repo gets the platform rules with zero setup.

**Setup:**

```bash
mkdir -p your-project/.github
cp platform-skills/.github/copilot-instructions.md your-project/.github/copilot-instructions.md
```

Commit and push. That's it.

**Using it in Copilot Chat:**

Open the Copilot Chat panel (`Ctrl+Shift+I` on Windows/Linux, `Cmd+Shift+I` on macOS):

```
Review this Deployment for production readiness
```

```
Generate a Terraform module for an EKS cluster with KMS encryption and least-privilege IAM
```

```
My Flux Kustomization is stuck NotReady — context deadline exceeded. How do I debug it?
```

```
Write a ValidatingPolicy that requires team labels on all Deployments
```

The rules apply automatically — no need to mention "platform-skills" in the prompt.

### Global level — applies to every project on your machine

Add the instructions as a global VSCode setting so it fires in every workspace, not just repos that have the file committed.

**Step 1: Create the global instructions file**

macOS / Linux:
```bash
mkdir -p ~/.vscode
cp platform-skills/.github/copilot-instructions.md ~/.vscode/platform-skills-copilot.md
```

Windows (PowerShell):
```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.vscode"
Copy-Item platform-skills\.github\copilot-instructions.md "$env:USERPROFILE\.vscode\platform-skills-copilot.md"
```

**Step 2: Wire it into VSCode settings**

Open VSCode → `Ctrl+Shift+P` / `Cmd+Shift+P` → **Open User Settings (JSON)** → add:

```json
{
  "github.copilot.chat.codeGeneration.instructions": [
    {
      "file": "${userHome}/.vscode/platform-skills-copilot.md"
    }
  ]
}
```

Reload VSCode (`Ctrl+Shift+P` → **Developer: Reload Window**).
The rules now apply in every project, regardless of whether the repo has `.github/copilot-instructions.md`.

### Upgrade

```bash
# Pull latest
cd platform-skills && git pull origin main

# Update project level
cp .github/copilot-instructions.md your-project/.github/copilot-instructions.md
cd your-project && git add .github/copilot-instructions.md
git commit -m "chore: update platform-skills to v$(grep 'Version:' .github/copilot-instructions.md | head -1 | awk '{print $3}')"

# Update global level
# macOS / Linux
cp platform-skills/.github/copilot-instructions.md ~/.vscode/platform-skills-copilot.md
# Windows (PowerShell)
Copy-Item platform-skills\.github\copilot-instructions.md "$env:USERPROFILE\.vscode\platform-skills-copilot.md"
```

---

## GitHub Copilot in JetBrains (IntelliJ, GoLand, PyCharm, WebStorm)

Works identically to VSCode — Copilot reads `.github/copilot-instructions.md` from the project root.

**Setup:**
1. Install the **GitHub Copilot** plugin from the JetBrains marketplace
2. Copy `platform-skills/.github/copilot-instructions.md` into your project's `.github/` folder
3. Open **Tools → GitHub Copilot → Open Chat** and ask questions as normal

No global setting is needed — the project-level file is sufficient.

---

## Cursor

### Project level

Cursor reads `.cursorrules` from your project root, and `.cursor/rules/*.mdc` for scoped rules (Cursor 0.44+).

```bash
# Copy the Cursor-specific rules file (NOT the Copilot file — different format)
cp platform-skills/.cursorrules your-project/.cursorrules
```

Commit it so all team members get it.

For scoped rules that fire only on specific file types:

```bash
# macOS / Linux
mkdir -p your-project/.cursor/rules
cp platform-skills/.cursor/rules/*.mdc your-project/.cursor/rules/

# Windows (PowerShell)
New-Item -ItemType Directory -Force your-project\.cursor\rules
Copy-Item platform-skills\.cursor\rules\*.mdc your-project\.cursor\rules\
```

### Global level — every Cursor workspace

```bash
# macOS / Linux
mkdir -p ~/.cursor/rules
cp platform-skills/.cursor/rules/platform-skills.mdc ~/.cursor/rules/platform-skills.mdc

# Windows (PowerShell)
New-Item -ItemType Directory -Force "$env:USERPROFILE\.cursor\rules"
Copy-Item platform-skills\.cursor\rules\platform-skills.mdc "$env:USERPROFILE\.cursor\rules\platform-skills.mdc"
```

In Cursor settings (`Ctrl+Shift+J`), confirm Rules for AI is enabled under **Features**.

### Using it in Cursor Chat

```
Review this Terraform module for blast radius and IAM least privilege
```

```
@docs platform-skills How should I structure a Flux monorepo with three environments?
```

```
Generate a Kyverno ValidatingPolicy that requires team labels on all Deployments
```

---

## Neovim, Emacs, or any other editor

For editors without a native Copilot extension, use the GitHub Copilot CLI:

```bash
# Install
npm install -g @githubnext/github-copilot-cli

# Ask platform engineering questions from the terminal
gh copilot suggest "write a Kyverno ValidatingPolicy that requires team labels on all Deployments"
gh copilot explain "what does prune: true do in a Flux Kustomization"
```

The `copilot-instructions.md` file is not used by the CLI — paste context directly into your prompt instead:

```bash
gh copilot suggest "$(cat your-deployment.yaml) — review this for production readiness"
```

---

## Example prompts that work well

Once the instructions file is active, these prompts produce structured, platform-engineering-quality answers in Copilot Chat:

**Kubernetes:**
```
Review this Deployment — flag any missing security context, resource limits, or probe issues
```

**Terraform:**
```
Review this IAM policy for wildcard actions and missing condition keys
```
```
What is the blast radius of changing this aws_db_subnet_group?
```

**GitOps:**
```
My HelmRelease is stuck in upgrade retries exhausted — how do I diagnose it?
```

**GitHub Actions:**
```
Review this workflow — flag any actions not pinned to a SHA, unsafe permissions, or OIDC gaps
```

**Helm:**
```
Review this values.yaml for the ingress-nginx chart — are resource limits set?
```

**Kyverno:**
```
Write a MutatingPolicy that adds default resource limits to any container missing them
```

**PR review:**
```
Review this diff for rollback feasibility — we are renaming a Deployment and adding an RDS storage increase
```

---

## File reference

| File | Purpose | Who uses it |
|---|---|---|
| `.github/copilot-instructions.md` | Platform rules for Copilot Chat | VSCode Copilot, JetBrains Copilot, GitHub.com Copilot |
| `.cursorrules` | Cursor-native rules (all files) | Cursor |
| `.cursor/rules/platform-skills.mdc` | Cursor always-on umbrella rule | Cursor 0.44+ |
| `.cursor/rules/kubernetes.mdc` | Scoped to `*.yaml` / `*.yml` | Cursor 0.44+ |
| `.cursor/rules/terraform.mdc` | Scoped to `*.tf` / `*.tfvars` | Cursor 0.44+ |

---

## Upgrade reference

| Setup | Command |
|---|---|
| Project Copilot | `git pull` in platform-skills clone → copy `copilot-instructions.md` → commit |
| Global VSCode | `git pull` → copy to `~/.vscode/platform-skills-copilot.md` |
| Cursor project | `git pull` → copy `.cursorrules` and `.cursor/rules/*.mdc` → commit |
| Cursor global | `git pull` → copy `.cursor/rules/platform-skills.mdc` to `~/.cursor/rules/` |

Check [CHANGELOG.md](CHANGELOG.md) to see what changed before upgrading.

---

## Troubleshooting

**Copilot Chat is not applying the rules**
- Confirm `.github/copilot-instructions.md` exists at the root of the open workspace folder
- In VSCode: open the file, check it is not empty
- Reload: `Ctrl+Shift+P` / `Cmd+Shift+P` → **Developer: Reload Window**

**Global instructions not applying**
- Confirm the path in `settings.json` is correct — use `${userHome}` not `~` in the JSON value
- Open **User Settings (JSON)** and verify the `codeGeneration.instructions` key exists

**Cursor rules not loading**
- Confirm `.cursorrules` is in the workspace root, not a subdirectory
- For `.mdc` files: Cursor 0.44+ required — check **Help → About** for your version

**Answers feel too generic**
- Paste the actual file or manifest into the chat — the more concrete the input, the better the output
- Specify versions: `kubernetes 1.29`, `terraform aws provider 5.x`, `flux v2.3`

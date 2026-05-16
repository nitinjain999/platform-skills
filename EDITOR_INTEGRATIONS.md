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

## Skill commands in Copilot Chat

Platform skills ships 18 command workflows. In Claude Code they are slash commands (`/platform-skills:review`). In Copilot Chat you phrase them as natural language — the instructions file makes Copilot apply the same structured output.

### review — production-readiness check on any file

Paste the file content directly after the prompt. Works on Kubernetes manifests, Terraform, GitHub Actions workflows, Helm values, Dockerfiles.

```
Review this for production readiness. Flag issues as Critical / Improvement / Note.
[paste file content]
```

```
Review this Deployment — check security context, resource limits, probes, and image pinning.
[paste YAML]
```

```
Review this GitHub Actions workflow — flag actions not pinned to a SHA, unsafe permissions, and OIDC gaps.
[paste workflow YAML]
```

---

### debug — structured troubleshooting

Describe the symptom and paste any relevant output. Copilot returns: layer classification → evidence to collect → root cause → fix → validation → rollback.

```
Debug this symptom using the troubleshooting framework: [describe error or paste output]
```

```
My orders-service pod is in CrashLoopBackOff with exit code 137. What are the likely causes and how do I confirm each?
```

```
Flux Kustomization is NotReady: "context deadline exceeded". Changes merged 20 minutes ago but cluster not updated.
```

```
GitHub Actions OIDC error: "not authorized to perform sts:AssumeRoleWithWebIdentity". What evidence should I collect first?
```

---

### terraform — blast radius + security review

Paste the Terraform code or plan output. Copilot returns: validation pipeline status, blast radius, IAM/security findings, state impact, recommended fixes.

```
Review this Terraform for blast radius, IAM least privilege, and SOC 2 compliance.
[paste HCL]
```

```
What gets replaced (forces new resource) in this terraform plan output?
[paste plan output]
```

```
Review this Terraform module for variable validation, provider placement, and output types.
[paste module files]
```

---

### gitops — Flux CD / Argo CD reconciliation

```
Troubleshoot this Flux issue. Classify by layer (source / artifact / reconciliation / runtime) and give evidence commands.
[describe symptom or paste flux get output]
```

```
My HelmRelease is stuck in "upgrade retries exhausted". How do I diagnose and safely roll back?
```

```
Argo CD application is perpetually OutOfSync despite successful manual sync. What causes this?
```

---

### helmcheck — Helm chart scaffold, review, security

**Create a new chart:**
```
Generate a production-ready Helm chart for a Node.js web service. Include Deployment, Service, Ingress, HPA, PDB, and NetworkPolicy. Apply security defaults from the platform rules.
```

**Review an existing chart:**
```
Review this Helm chart for Critical and High severity issues — missing helpers, hardcoded secrets, missing probes, label immutability.
[paste chart files or describe the chart]
```

**Security audit:**
```
Run a Helm security audit on this chart. Check pod security, RBAC, network policy, and secrets handling.
[paste values.yaml and deployment.yaml]
```

---

### kyverno — admission policy generation and testing

```
Write a ValidatingPolicy (apiVersion: policies.kyverno.io/v1) that requires all Deployments to have app.kubernetes.io/team and app.kubernetes.io/name labels. Start in Audit mode.
```

```
Write a MutatingPolicy that adds default resource limits to any container that omits them.
```

```
Write a GeneratingPolicy that creates a default-deny NetworkPolicy in every new namespace.
```

```
Migrate this legacy kyverno.io/v1 ClusterPolicy to the new policies.kyverno.io/v1 ValidatingPolicy format.
[paste ClusterPolicy YAML]
```

```
My ValidatingPolicy is in Audit mode but policyreport shows no violations for existing Deployments. Why?
```

---

### opa — Rego policy generation and debugging

```
Write a Rego policy (import rego.v1) that denies Kubernetes Deployments without resource limits. Include the METADATA block and a deny rule with a descriptive message.
```

```
Write unit tests for this Rego policy — one passing and one failing fixture per rule.
[paste policy]
```

```
Explain this Rego policy rule by rule in plain English. Map each input field to the resource attribute it checks.
[paste policy]
```

```
My deny rule produces no output when I run conftest test. What are the common causes and how do I check each?
```

---

### compliance — SOC 2 gap analysis and remediation

```
Run a SOC 2 gap analysis on this Terraform module. Map each finding to the Trust Services Criterion (CC6.1–CC8.1) and rate severity.
[paste Terraform]
```

```
Implement CC6.7 encryption at rest for this RDS instance in Terraform. Show the before and after, blast radius, and Checkov rule IDs.
```

```
What AWS CLI commands do I run to prove to auditors that all S3 buckets have encryption enabled (CC6.7)?
```

```
Fix this Checkov finding: CKV_AWS_18 — S3 bucket does not have access logging enabled.
[paste resource block]
```

---

### pr-review — six-dimension pre-merge risk check

**Cost:**
```
Review this diff for cost impact. Check replica count changes, instance type changes, new storage resources, and NAT Gateways.
[paste git diff or PR description]
```

**Drift:**
```
Check if dev and prod are aligned. I changed values-dev.yaml — does values-prod.yaml need a matching change?
[paste both files]
```

**Ownership:**
```
Review this PR for ownership gaps. Is CODEOWNERS covering all changed paths? Are team labels present on new resources?
[paste changed files list]
```

**Compliance:**
```
Review this PR for SOC 2 impact. A new IAM role and S3 bucket are added — check CC6.1, CC6.2, and CC6.7.
[paste diff]
```

**Upgrade:**
```
Review this PR for deprecated APIs. Check Kubernetes API versions, Terraform provider constraints, and GitHub Actions versions.
[paste manifests or workflows]
```

**Rollback:**
```
Score the rollback feasibility of each change in this PR: FULL / PARTIAL / MANUAL / NONE. We are renaming a Deployment and increasing RDS storage.
[paste diff]
```

**Full review:**
```
Run a full pre-merge review across all six dimensions: cost, drift, ownership, compliance, upgrade, and rollback. Summarize as Merge Ready / Needs Fix / Blocked.
[paste diff]
```

---

### observability — instrument, alert, dashboard

```
Add structured logging, Prometheus RED metrics, and OpenTelemetry tracing to this Node.js Express service.
[paste service file]
```

```
Write Prometheus alerting rules for the orders-service. SLO is 99.9% availability, p99 < 500ms. Use burn-rate alerts.
```

```
Generate a Grafana dashboard for the orders-service using the RED method. Include request rate, error rate, p50/p95/p99 latency panels.
```

```
Write a k6 load test for POST /orders. Peak 500 RPS, p95 must be under 200ms, error rate under 0.1%.
```

---

### commit — conventional commit messages

```
Analyze this git diff and generate a conventional commit message. Focus on WHY the change was made, not what files changed.
[paste git diff]
```

```
Validate this commit message against the Conventional Commits 1.0.0 spec. Report any violations with the corrected line.
"Fix: updated auth service"
```

---

### debug — domain-specific troubleshooting

**Linux / DNS / networking:**
```
A pod cannot resolve payments-service.checkout.svc.cluster.local. Walk me through the DNS resolution path and give exact dig commands to find the break.
```

```
ALB returning 502 — target group shows healthy. What is the most likely cause and how do I confirm it?
```

**Linkerd:**
```
linkerd viz edges shows plaintext between orders-service and payments-service. How do I diagnose why mTLS is not working?
```

**Datadog:**
```
APM traces are missing for the payments-service. The agent shows healthy. What are the common causes and evidence commands?
```

**Dynatrace:**
```
OneAgent is not injecting into pods in the checkout namespace. How do I diagnose the injection failure?
```

---

### product — DevEx, RFC/ADR, post-mortems

```
Write a blameless post-mortem for this incident. Database failover at 02:15 UTC caused 18 minutes of downtime for checkout. Root cause was a missing health check on the standby.
```

```
Draft an RFC for migrating from Argo CD to Flux CD. 15 teams affected, GitOps repo restructure required.
```

```
Audit our developer experience using the SPACE framework. Engineers spend 45 minutes to get a new service to production on day 1.
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

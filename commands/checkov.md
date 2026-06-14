---
name: checkov
description: Bootstrap Checkov on a developer laptop, run static or plan-level Terraform security scanning for AWS/Azure/GCP/EKS, resolve private GitHub modules via gh CLI, generate pre-commit hooks, produce multi-format output (cli/json/sarif/junit), and fix violations with AI-generated patches. Use when asked to "scan my Terraform", "run checkov", "check my IaC for security issues", "set up checkov pre-commit", or "fix checkov findings".
argument-hint: "[static|plan|secrets|audit|multi|baseline|fix|scaffold] [path]"
---

Bootstrap Checkov and scan Terraform code for security misconfigurations — locally, before CI catches them.

Read `references/checkov.md` before responding. It contains all mode logic, bootstrap steps, provider detection, and fix patterns.

## Mode dispatch

Parse the first word of `$ARGUMENTS` as the mode. When `$ARGUMENTS` is empty, run the interactive wizard.

| Mode | What it does |
|---|---|
| `static` | Scan `.tf` source files with `--download-external-modules true` |
| `plan` | `terraform init` → plan → JSON → Checkov `--deep-analysis` (use `--upgrade` flag to also upgrade providers) |
| `secrets` | Scan entire repo for hardcoded secrets (`--framework secrets --enable-secret-scan-all-files`) |
| `audit` | One-time secrets history scan across all commits (`--scan-secrets-history`) |
| `multi` | Scan Terraform + GitHub Actions + Dockerfiles + Helm in a single run |
| `baseline` | Create `.checkov.baseline` to snapshot existing violations |
| `fix` | Re-run scan and apply AI-generated patches to `.tf` files |
| `scaffold` | Generate `.checkov.yaml` config (SOC 2 / CIS / PCI / HIPAA variants) and/or `custom-checks/` |
| _(empty)_ | Interactive wizard — ask Q1 (mode) then Q2 (path/context) |

## Interactive Wizard

**Q1 — Mode?**
```
What do you need?
  1. static    — scan .tf source files  [default]
  2. plan      — terraform plan → Checkov deep analysis
  3. secrets   — scan entire repo for hardcoded secrets and tokens
  4. audit     — one-time scan of git commit history for leaked secrets
  5. multi     — scan Terraform + GitHub Actions + Dockerfiles + Helm together
  6. baseline  — snapshot existing violations (first-run brownfield)
  7. fix       — scan and apply AI-generated fixes to .tf files
  8. scaffold  — generate .checkov.yaml (SOC 2 / CIS / PCI / HIPAA) or custom-checks/

Enter 1–8 or mode name:
```

**Q2 — Path?** (ask after Q1)
```
Terraform root directory, or press Enter to scan current directory [default: .]:
```

Then proceed into the relevant mode section in `references/checkov.md`.

## Agent behavior

### Intent classification

Before asking any question, classify the user's intent from their free-text request:

| Intent signals | Mode |
|---|---|
| "scan", "check", "lint", "review my Terraform", "check my IaC" | `static` |
| "plan", "deep analysis", "live values", "against real state" | `plan` |
| "secrets", "hardcoded", "leaked credentials", "tokens in code", "secret scan" | `secrets` |
| "git history", "scan history", "ever committed", "old commits", "audit history" | `audit` |
| "scan everything", "multi-framework", "github actions", "dockerfiles", "helm" | `multi` |
| "existing repo", "too many findings", "noisy", "brownfield", "baseline" | `baseline` |
| "fix", "remediate", "resolve", "CKV_*" | `fix` |
| "set up", "configure", "pre-commit", "custom checks", ".checkov.yaml", "scaffold" | `scaffold` |

### Ask only for missing high-risk inputs

Do not pepper the user with questions. Only prompt for inputs where getting it wrong causes real harm:

| When to ask | Question |
|---|---|
| Multiple Terraform roots detected | "Which root? (1. terraform/aws/ 2. terraform/azure/ 3. All)" |
| Plan mode, multiple `*.tfvars` found | "Which var file? (1. staging.tfvars 2. production.tfvars 3. None)" |
| Plan mode, non-default workspace detected | "Currently on workspace '<name>' — continue? (y/N)" |
| Fix → Apply mode | "Apply these changes? (y/N)" — show unified diff first |
| scaffold writes a new file | "Write .checkov.yaml to <path>? (y/N)" |

Never ask about: output format (default to `cli`), whether to run bootstrap (always do it), whether to gitignore output files (always do it), or pre-commit detection (always check silently).

## Cross-references

- `/platform-skills:terraform` — full validation pipeline (fmt → validate → tflint → checkov → plan)
- `/platform-skills:compliance` — SOC 2 control mapping and Checkov check IDs by TSC criterion
- `/platform-skills:supply-chain` — image signing, SBOM, and CVE scanning beyond IaC

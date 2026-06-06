---
name: terraform
description: Runs through the full Terraform validation pipeline — fmt, validate, tflint, security scan — and reviews a module or plan for blast radius, IAM risk, and state impact.
argument-hint: "[paste terraform code, plan output, or describe the change]"
---

---

## Interactive Wizard (fires when $ARGUMENTS is empty)

When invoked with no arguments, ask before reviewing:

**Q1 — What to review?**
```
Paste the Terraform code or plan output, or describe the change
(e.g. "adding an aws_rds_instance", "plan shows 3 resources destroyed", "here's my EKS module"):
```

**Q2 — Focus area?** (ask after Q1)
```
Any specific focus, or full review?
  1. Full review     — validation pipeline + blast radius + IAM + state impact
  2. IAM / security  — least privilege, wildcard actions, sensitive vars
  3. Blast radius    — what gets replaced vs updated, downstream impact
  4. Module design   — variable validation, output types, provider config

Enter 1–4 [default: 1]:
```

Then proceed with the review framework below.

---

You are a senior platform engineer reviewing Terraform.

The input is: $ARGUMENTS

## 1. Validation Pipeline

Walk through each gate in order. For each, state whether it would pass or fail based on the provided code, and why:

1. **`terraform fmt -check -recursive`** — formatting and style
2. **`terraform validate`** — syntax, type correctness, reference integrity (note: use `-backend=false` in CI)
3. **`tflint --recursive`** — provider-specific rules (invalid instance types, deprecated arguments, missing required_version)
4. **`tfsec . --minimum-severity HIGH`** or **`checkov -d . --framework terraform --compact`** — security misconfigurations

   > **tfsec version note:** Flag syntax changed in v1.0+. Check with `tfsec --version`.
   > - `< v1.0`: use `--minimum-severity HIGH`
   > - `>= v1.0`: use `--severity HIGH`
   > - Drop-in alternative: `trivy config . --severity HIGH`

## 2. Blast Radius

- What cloud resources does this create, modify, or destroy?
- Which resources will be **replaced** (destroyed and recreated) vs updated in-place?
- What downstream systems depend on these resources?
- What is the impact if this apply fails halfway?

**Pre-merge validation:** Run against a test workspace before merging:
```bash
terraform workspace select <test-workspace>
terraform plan -out=tfplan
# Review the plan output for unexpected resource replacements (lines marked with -/+)
# Any replacement of stateful resources (RDS, ElastiCache, EKS node group) requires explicit approval
```

## 3. IAM and Security

- Are IAM policies least-privilege? Flag any wildcard actions or resources.
- Are tags enforced via `default_tags` (AWS) or `merge(local.common_tags, {...})` (Azure)?
- Are secrets passed via variables marked `sensitive = true`?
- Is the state backend encrypted?

## 4. State Impact

- Does this change require a state migration or `terraform state mv`?
- Are there resources that Terraform does not manage that could conflict?
- Is state isolated by environment and blast radius?

## 5. Module Design (if reviewing a module)

- Are variables validated with `validation` blocks?
- Are outputs documented and typed?
- Is the provider configured in the caller, not the module?

## 6. Recommended Actions

List exact fixes with the corrected HCL snippet where applicable.

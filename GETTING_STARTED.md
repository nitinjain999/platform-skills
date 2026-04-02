# Getting Started with Claude and Platform Skills

This guide is for people who are new to Claude and want to start using this repository quickly.

## What This Repository Is

`platform-skills` is a platform engineering knowledge pack for Claude.

It helps with:

- Kubernetes and OpenShift platform patterns
- Flux or Argo CD GitOps design and troubleshooting
- Terraform module and environment structure
- AWS and Azure platform decisions
- GitHub Actions workflow design and review

You can use it in four ways:

1. Read the examples and references directly on GitHub.
2. Install it from the Claude marketplace (easiest).
3. Clone locally for templates and patterns.
4. Install from local clone so Claude can reference your customized version.

## Fastest Path

If you want the shortest route, do this:

```bash
git clone https://github.com/nitinjain999/platform-skills.git
cd platform-skills
```

Then:

1. Read [README.md](README.md).
2. Read [SKILL.md](SKILL.md).
3. Pick the reference that matches your task under `references/`.
4. Copy or adapt an example from `examples/`.

If you are using Claude Code, install the skill locally:

```bash
claude-code skill install ./platform-skills
```

## Install from Claude Marketplace (Recommended)

**Check if published:**

```bash
# Search for the skill in marketplace
claude-code skill search platform-skills
```

If `platform-skills` is available in the Claude marketplace, install it:

```bash
claude-code skill install platform-skills
```

This is the easiest way to get started. Claude will automatically reference these patterns while you work.

To update to the latest version:

```bash
claude-code skill update platform-skills
```

To uninstall:

```bash
claude-code skill uninstall platform-skills
```

**If not yet published:** Use the local clone method below.

## Install from Local Clone (For Customization)

If you want to customize the patterns or test unreleased changes:

```bash
# Clone the repository
git clone https://github.com/nitinjain999/platform-skills.git

# Install from local clone
claude-code skill install ./platform-skills
```

**Use local install when:**
- You're customizing patterns for your organization
- You want to test unreleased changes
- You need to modify reference guides

**Use marketplace install when:**
- You want the easiest setup
- You want automatic updates
- You're onboarding teammates

## How to Think About It

Do not ask Claude about every tool in isolation. Ask from the platform point of view.

Use this rough ownership model:

1. `Terraform` creates cloud foundations, clusters, identity, networking, and shared services.
2. `Kubernetes` or `OpenShift` defines the runtime rules and workload model.
3. `Flux` or `Argo CD` reconciles in-cluster state after bootstrap.
4. `GitHub Actions` validates, packages, and promotes changes.

Important rule:

- Choose either `Flux` or `Argo CD` for a given ownership boundary unless you are explicitly planning a migration.

## What to Ask Claude

Good prompts are concrete. Include:

- What you are trying to do
- Which platform you use
- Which tool owns the change
- What error or risk you see
- What constraints matter

Good examples:

```text
Review this Terraform layout for a multi-environment EKS platform. I want clear separation between reusable modules and live environment state.
```

```text
My Argo CD application is out of sync after a merge. Help me debug the likely cause and tell me what evidence to collect first.
```

```text
I run OpenShift on AWS. Should ingress, cert-manager, and observability be managed by Terraform or GitOps?
```

```text
Review this GitHub Actions workflow for security issues. It assumes AWS OIDC and deploys to Kubernetes after PR merge.
```

## Where to Look in This Repo

Start here based on your need:

- [SKILL.md](SKILL.md): the core operating model
- [references/platform-operating-model.md](references/platform-operating-model.md): ownership boundaries and repo topology
- [references/terraform.md](references/terraform.md): Terraform module and environment guidance
- [references/kubernetes.md](references/kubernetes.md): Kubernetes baseline guidance
- [references/openshift.md](references/openshift.md): OpenShift-specific patterns
- [references/flux.md](references/flux.md): Flux GitOps patterns
- [references/argocd.md](references/argocd.md): Argo CD patterns
- [references/aws.md](references/aws.md): AWS platform guidance
- [references/azure.md](references/azure.md): Azure platform guidance
- [references/github-actions.md](references/github-actions.md): CI/CD and workflow guidance

Examples live under `examples/` and are meant to be adapted, not copied blindly into production.

## First Tasks for a New User

If you are unsure where to begin, start with one of these:

1. Ask Claude to review your Terraform structure.
2. Ask Claude to review your GitOps repo layout.
3. Ask Claude to review a GitHub Actions workflow for security and promotion flow.
4. Ask Claude whether a change belongs in Terraform, Kubernetes/OpenShift, or GitOps.

## Common Mistakes

Avoid these early mistakes:

- Mixing Terraform and GitOps ownership for the same resource set
- Using both Flux and Argo CD against the same boundary without a migration plan
- Asking broad questions without sharing the actual repo layout, YAML, workflow, or error
- Treating examples in this repo as complete production systems without adapting them
- Putting environment truth into GitHub Actions workflow YAML

## A Simple Workflow

Use this loop:

1. Start with the platform problem.
2. Identify the owning layer.
3. Open the matching reference file.
4. Ask Claude for a concrete recommendation or review.
5. Apply the smallest useful change first.
6. Validate before expanding the pattern.

## If You Are Completely New to Claude

Keep your first sessions simple.

Good pattern:

```text
I am new to this repo. I use Azure + AKS + Argo CD + GitHub Actions.
Help me decide:
1. what Terraform should own
2. what Argo CD should own
3. what GitHub Actions should do
4. which reference files in this repo I should read first
```

Claude works best when you give it:

- your current architecture
- the files you are working on
- the exact error text
- the desired end state

## Next Step

After this guide, read:

1. [README.md](README.md)
2. [SKILL.md](SKILL.md)
3. the one reference file closest to your current task

That is enough to start using `platform-skills` productively.

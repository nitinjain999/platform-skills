# Platform Skills

> **A comprehensive Claude Agent Skill for platform engineering**  
> Production-ready patterns for Kubernetes, OpenShift, Argo CD, Flux CD, AWS, Azure, Terraform, and GitHub Actions

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude-Code%20Skill-purple)](https://claude.ai/code)

## Overview

Platform Skills is a specialized Claude Agent Skill designed for platform engineers, SREs, and DevOps practitioners working with modern cloud-native infrastructure. It provides expert guidance on troubleshooting, architecture decisions, and production best practices across Kubernetes platforms, GitOps systems, cloud foundations, and CI/CD workflows.

## What Problems Does This Solve?

### ☸️ Kubernetes
- **Baseline standards**: Define namespace, RBAC, resource, and policy defaults
- **Workload patterns**: Standardize deployments, probes, budgets, and service accounts
- **Security controls**: Apply network policy, pod security, and secret handling practices
- **Operational consistency**: Keep Git, rollout, and rollback flows explicit

### 🟥 OpenShift
- **Route patterns**: Expose services with OpenShift-native ingress models
- **Security adaptation**: Make workloads compatible with SCC and restricted execution defaults
- **Operator usage**: Prefer operator-managed platform services where OpenShift already provides the control plane
- **Tenant isolation**: Structure projects, quotas, and RBAC for shared clusters

### 🔄 Flux CD & GitOps
- **Reconciliation failures**: Quickly diagnose source, artifact, and kustomization errors
- **Multi-tenancy patterns**: Structure repositories for teams, environments, and applications
- **Progressive delivery**: Implement canary deployments and automated rollbacks
- **Image automation**: Set up automated image updates with policy enforcement

### 🚢 Argo CD
- **App-of-apps design**: Structure root applications and project boundaries safely
- **ApplicationSet patterns**: Manage repeated cluster onboarding and multi-cluster fleets
- **Sync control**: Tune prune, self-heal, and wave behaviors to match risk tolerance
- **Promotion flows**: Move versions through Git without imperative cluster changes

### ☁️ AWS
- **EKS architecture**: Design production-ready cluster configurations
- **IAM hardening**: Transform wildcard policies into least-privilege configurations
- **Service selection**: Choose the right AWS service with confidence
- **Cost optimization**: Identify and eliminate resource waste

### 🌐 Azure
- **AKS operations**: Troubleshoot networking, RBAC, and scaling issues
- **ARM/Bicep patterns**: Structure templates for reusability and maintainability
- **Azure security**: Implement security baselines and policy enforcement
- **Managed identities**: Eliminate service principal sprawl

### 🏗️ Terraform
- **Module design**: Build reusable, testable infrastructure modules
- **State management**: Avoid conflicts, handle drift, manage workspaces
- **Testing strategies**: Choose between native tests, Terratest, and policy-as-code
- **CI/CD integration**: Build safe, automated infrastructure pipelines

### 🚀 GitHub Actions
- **Workflow security**: Identify and fix security vulnerabilities
- **Performance optimization**: Reduce workflow run times with caching and parallelization
- **Secret management**: Implement secure secret handling patterns
- **Action maintenance**: Update deprecated actions and pin versions correctly

## CI/CD & Automation

This repository uses GitHub Actions for quality assurance and Renovate for dependency management:

- **Continuous Validation**: Every PR and push validates structure, syntax, and security
- **Automated Releases**: Tag-based releases with automatic GitHub Release creation
- **Dependency Updates**: Renovate automatically creates PRs for:
  - GitHub Actions (SHA-pinned for security)
  - Terraform providers and modules
  - Helm chart versions
  - Container images
  - Security vulnerability patches
- **Quality Checks**: 
  - **Blocking**: YAML syntax, Terraform validation, secret detection, and repository workflow security
  - **Advisory**: Markdown structure and example workflow pinning recommendations

See [.github/workflows/](.github/workflows/) for workflow details and [renovate.json](renovate.json) for dependency automation configuration.

## Installation & Usage

New to Claude or using this repo for the first time? Start with [GETTING_STARTED.md](GETTING_STARTED.md).

> **Note:** This repository provides reference patterns and examples for platform engineering with Kubernetes, OpenShift, Argo CD, Flux CD, AWS, Azure, Terraform, and GitHub Actions. It can be used as:
> 1. **Reference Documentation** - Browse examples and guides directly on GitHub
> 2. **Claude Code Skill** - Install from marketplace if published, or locally for interactive guidance
> 3. **Cloned Repository** - Clone locally for templates and customization

### As Reference Documentation

Browse the repository on GitHub:
- [Examples](examples/) - Working code you can copy
- [References](references/) - Deep-dive guides
- [SKILL.md](SKILL.md) - Core patterns

### Clone for Local Use

```bash
git clone https://github.com/nitinjain999/platform-skills.git
cd platform-skills

# Copy examples to your project
cp -r examples/flux/basic-monorepo/* your-project/
cp -r examples/terraform/eks-cluster/* your-terraform-modules/
```

### Claude Code Integration (Optional)

If using Claude Code, install this as a skill:

**From Marketplace (If Published):**
```bash
claude-code skill search platform-skills
claude-code skill install platform-skills
```

**From Local Clone (For Customization):**
```bash
git clone https://github.com/nitinjain999/platform-skills.git
claude-code skill install ./platform-skills
```

**Usage:**
The skill provides context-aware guidance when working with platform engineering tasks. Claude will reference these patterns automatically when relevant.

### Example Scenarios

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

## Repository Structure

```
platform-skills/                   # Root repository
├── .claude-plugin/
│   └── marketplace.json           # Metadata for Claude Code
├── .github/workflows/
│   ├── release.yml                # Automated releases
│   └── validate.yml               # CI/CD validation
├── examples/                      # Working code examples
│   ├── flux/
│   │   └── basic-monorepo/        # Complete Flux CD structure
│   ├── kubernetes/
│   │   └── README.md              # Cluster baseline patterns
│   ├── openshift/
│   │   └── README.md              # OpenShift operating patterns
│   ├── argocd/
│   │   ├── README.md              # Argo CD design patterns
│   │   └── app-of-apps/           # Root application example
│   ├── aws/
│   │   └── README.md              # IAM, VPC, EKS patterns
│   ├── azure/
│   │   └── README.md              # AKS, workload identity
│   ├── terraform/
│   │   ├── eks-cluster/           # Production EKS module
│   │   └── multi-env-structure/   # Environment patterns
│   └── github-actions/
│       ├── terraform-cicd.yml     # Complete CI/CD pipeline
│       ├── flux-sync.yml          # Flux CD validation
│       └── container-build.yml    # Container workflows
├── references/                    # Deep-dive guides
│   ├── platform-operating-model.md
│   ├── kubernetes.md
│   ├── openshift.md
│   ├── argocd.md
│   ├── flux.md
│   ├── aws.md
│   ├── azure.md
│   ├── terraform.md
│   └── github-actions.md
├── SKILL.md                       # Core skill patterns
├── README.md                      # This file
├── GETTING_STARTED.md             # Quick start guide for new users
├── CONTRIBUTING.md                # Contribution + release guide
├── CLAUDE.md                      # Development philosophy
├── CHANGELOG.md                   # Version history
├── LICENSE                        # Apache-2.0
└── NOTICE                         # Copyright attribution

**Note:** Current structure is flat (single-skill repository). SKILL.md defines patterns that reference examples/ and references/ directories.
```

## Key Features

### 🎯 Production-First Approach
- Root-cause analysis over quick workarounds
- Explicit blast radius for all changes
- Rollback plans for risky operations
- Security and compliance by default

### 🔍 Structured Troubleshooting
Every issue follows a consistent framework:
1. **Symptom**: Exact error and observable behavior
2. **Evidence**: Logs, events, status output
3. **Hypothesis**: Most likely root cause
4. **Diagnosis**: Commands to confirm hypothesis
5. **Fix**: Specific change with justification
6. **Validation**: Verification steps
7. **Prevention**: Future avoidance strategy
8. **Rollback**: Safe undo path

### 📚 Progressive Disclosure
- Essential patterns in main skill file
- Deep dives in reference documents
- Practical examples in examples directory
- Context-aware guidance based on your question

### 🔐 Security-Focused
- IAM least-privilege patterns
- Kubernetes and OpenShift platform baselines
- Argo CD or Flux GitOps operating models
- GitHub Actions security best practices
- Secret management strategies
- Compliance and policy enforcement

## Roadmap

- [ ] Expand GCP coverage
- [ ] Add observability patterns (Prometheus, Grafana, Loki)
- [ ] Include service mesh guidance (Istio, Linkerd)
- [ ] Add policy-as-code examples (OPA, Kyverno, Gatekeeper)
- [ ] Add OpenShift operator lifecycle examples
- [ ] Expand Argo CD ApplicationSet fleet patterns
- [ ] Expand cost optimization patterns
- [ ] Add disaster recovery patterns
- [ ] Include multi-cloud networking patterns

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- How to propose new patterns
- Code of conduct
- Development workflow
- Testing guidelines

## Related Resources

- [AWS Samples](https://github.com/aws-samples) - AWS reference architectures
- [Argo CD](https://github.com/argoproj/argo-cd) - Argo CD documentation and controller source
- [Flux CD](https://github.com/fluxcd/flux2) - Flux documentation and controller source
- [GitHub Actions Documentation](https://docs.github.com/actions) - Workflow design and security guidance

## License

Apache-2.0. See [LICENSE](LICENSE) for the full license text and [NOTICE](NOTICE) for copyright attribution.

If you create derivative works or skills based on this project, include the Apache 2.0 license text, retain existing copyright and attribution notices, and clearly mark any files you changed.

## Support

- **Issues**: [GitHub Issues](https://github.com/nitinjain999/platform-skills/issues)
- **Discussions**: [GitHub Discussions](https://github.com/nitinjain999/platform-skills/discussions)
- **Discord**: [Claude Code Community](#)

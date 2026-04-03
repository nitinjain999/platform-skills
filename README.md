# Platform Skills

> A practical handbook for developers and DevOps engineers working with Kubernetes, GitOps, Terraform, GitHub Actions, cloud infrastructure, and secrets management — with an optional Claude plugin layer for interactive guidance.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude-Code%20Skill-purple)](https://claude.ai/code)

## What is this?

This repository is a reference handbook for developers, DevOps engineers, SREs, and platform teams. It is structured in two independent layers:

- **Handbook** — `references/` and `examples/` are the main product. Every domain has a deep-dive guide and working example assets you can copy directly into your project. Use it on GitHub, from a local clone, or as a team knowledge base.
- **Claude plugin** — `SKILL.md` and `.claude-plugin/marketplace.json` add an optional routing layer so Claude surfaces the right section of the handbook when you ask platform engineering questions interactively.

Both layers work independently. The plugin is optional.

## Navigate

| I want to... | Go to |
|---|---|
| Get started in 5 minutes | [QUICKSTART.md](QUICKSTART.md) |
| Full installation guide and troubleshooting | [INSTALLATION.md](INSTALLATION.md) |
| Read a domain guide | [references/](references/) |
| Copy a working example | [examples/](examples/) |
| Install as a Claude plugin | [Installation](#installation) |
| Set up VSCode with or without Claude | [VSCODE_INTEGRATION.md](VSCODE_INTEGRATION.md) |
| Contribute a pattern | [CONTRIBUTING.md](CONTRIBUTING.md) |

## Domains

| Domain | Reference guide | What it covers |
|---|---|---|
| ☸️ Kubernetes | [references/kubernetes.md](references/kubernetes.md) | Cluster baseline, workload patterns, network policy, RBAC, pod security |
| 🟥 OpenShift | [references/openshift.md](references/openshift.md) | Routes, SCC compatibility, operator usage, tenant isolation |
| 🚢 Argo CD | [references/argocd.md](references/argocd.md) | App-of-apps design, ApplicationSet, sync control, promotion flows |
| 🔄 Flux CD | [references/flux.md](references/flux.md) | Monorepo structure, reconciliation, multi-tenancy, image automation |
| ☁️ AWS | [references/aws.md](references/aws.md) | IAM least-privilege, IRSA, EKS, resource tagging, cost allocation |
| 🌐 Azure | [references/azure.md](references/azure.md) | Workload identity, AKS, RBAC, resource tagging, Azure Policy |
| 🏗️ Terraform | [references/terraform.md](references/terraform.md) | Module design, state management, testing, CI/CD integration |
| 🚀 GitHub Actions | [references/github-actions.md](references/github-actions.md) | Security hardening, OIDC, SHA pinning, reusable workflows |
| 🗺️ Platform model | [references/platform-operating-model.md](references/platform-operating-model.md) | Ownership boundaries, promotion flows, cross-tool design |
| 🔐 Secrets | [references/secrets.md](references/secrets.md) | External Secrets Operator, Sealed Secrets, provider setup, troubleshooting |
| 🔗 Linkerd | [references/linkerd.md](references/linkerd.md) | mTLS, proxy injection, AuthorizationPolicy, observability, multi-cluster |
| 🐧 Linux & Networking | [references/linux-networking.md](references/linux-networking.md) | Linux admin, DNS, load balancing, VPC/VNet design, connectivity troubleshooting |
| 🧠 Platform Mindset | [references/platform-mindset.md](references/platform-mindset.md) | DevEx, friction audits, RFC/ADR, incident comms, post-mortems, capacity planning |

## Core principles

Every pattern in this handbook follows the same ground rules:

- **Production-first** — patterns are battle-tested, not theoretical
- **Root-cause over symptom** — troubleshooting works backwards from evidence to fix
- **Explicit blast radius** — every risky operation documents scope and rollback
- **Security by default** — least-privilege IAM, restricted pod security, SHA-pinned actions
- **Rollback plans are mandatory** — if you cannot safely undo it, the guide is incomplete

### Troubleshooting structure

Every troubleshooting section in the handbook follows this consistent framework — from quick diagnosis to safe resolution:

| Step | What it answers |
|---|---|
| **Symptom** | Exact error and observable behavior |
| **Evidence** | Commands to run: logs, events, status |
| **Hypothesis** | Most likely root cause |
| **Diagnosis** | Commands that confirm or rule out the hypothesis |
| **Fix** | Specific change with justification |
| **Validation** | Post-fix verification steps |
| **Prevention** | How to avoid it next time |
| **Rollback** | Safe undo path if the fix makes things worse |

## Installation

### Browse on GitHub

No installation needed. Navigate directly:

- [examples/](examples/) — copy-paste examples for all domains
- [references/](references/) — deep-dive domain guides
- [SKILL.md](SKILL.md) — core patterns and routing logic

### Clone for local templates

```bash
git clone https://github.com/nitinjain999/platform-skills.git
cd platform-skills

# Copy examples directly into your project
cp -r examples/flux/basic-monorepo/*          your-gitops-repo/
cp -r examples/terraform/eks-cluster/*         your-terraform-modules/
cp    examples/kubernetes/deployment-baseline.yaml  your-k8s-manifests/
```

### Install as a Claude plugin

The plugin adds interactive guidance on top of the handbook. Claude will reference the right section automatically when you ask platform engineering questions in your editor, terminal, or browser.

**From marketplace:**
```bash
claude plugin marketplace add https://github.com/nitinjain999/platform-skills
claude plugin install platform-skills
```

**From local clone (for customisation):**
```bash
git clone https://github.com/nitinjain999/platform-skills.git
cd platform-skills
claude plugin install .
```

For VS Code workflows with Claude or with Copilot only, see [VSCODE_INTEGRATION.md](VSCODE_INTEGRATION.md).

## Repository structure

```
platform-skills/
├── references/                         # Deep-dive guides — one per domain
│   ├── platform-operating-model.md
│   ├── kubernetes.md
│   ├── openshift.md
│   ├── argocd.md
│   ├── flux.md
│   ├── aws.md
│   ├── azure.md
│   ├── terraform.md
│   ├── github-actions.md
│   ├── secrets.md
│   ├── linkerd.md
│   ├── linux-networking.md
│   └── platform-mindset.md
│
├── examples/                           # Working examples and handbook snippets
│   ├── flux/basic-monorepo/            # Complete Flux CD monorepo structure
│   ├── kubernetes/                     # Namespace, deployment, network policy, PDB
│   ├── openshift/                      # Route, ResourceQuota, LimitRange
│   ├── argocd/app-of-apps/             # Root application manifest
│   ├── aws/iam/                        # Least-privilege IAM policy examples
│   ├── azure/workload-identity/        # Managed identity + federated credential
│   ├── terraform/eks-cluster/          # Production EKS Terraform module
│   └── github-actions/                 # CI/CD, Flux sync, container build workflows
│
├── SKILL.md                            # Claude plugin routing and patterns
├── .claude-plugin/marketplace.json     # Marketplace metadata
├── .github/workflows/                  # Validation and release automation
├── tests/validate-skill.sh             # Skill structure consistency checks
└── renovate.json                       # Automated dependency updates
```

## Roadmap

**Completed**
- [x] v1.3.0 — Linkerd: mTLS, observability, traffic management, multi-cluster
- [x] v1.5.0 — Linux & Networking: Linux admin, DNS, load balancing, VPC/VNet
- [x] v1.5.0 — Platform Mindset: DevEx, RFC/ADR, incident comms, post-mortems

**Planned**
- [ ] GCP: landing zone, GKE, and IAM patterns
- [ ] Observability: Prometheus, Grafana, Loki
- [ ] Service mesh: Istio
- [ ] Policy-as-code: OPA, Kyverno, Gatekeeper
- [ ] OpenShift operator lifecycle patterns
- [ ] Argo CD ApplicationSet fleet patterns
- [ ] Disaster recovery runbooks for platform components
- [ ] Multi-cloud networking patterns

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to propose new patterns, the development workflow, and release guidelines.

## Related resources

- [AWS EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [Argo CD documentation](https://github.com/argoproj/argo-cd)
- [Flux CD documentation](https://github.com/fluxcd/flux2)
- [GitHub Actions security hardening](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)

## License

Apache-2.0. See [LICENSE](LICENSE) for the full text and [NOTICE](NOTICE) for attribution.

If you create derivative works based on this project, retain the Apache 2.0 license text, existing copyright and attribution notices, and clearly mark any files you changed.

## Support

- [GitHub Issues](https://github.com/nitinjain999/platform-skills/issues)
- [GitHub Discussions](https://github.com/nitinjain999/platform-skills/discussions)
- [Claude Code Community Discord](https://discord.gg/anthropic)

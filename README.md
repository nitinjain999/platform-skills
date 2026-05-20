# Platform Skills

> A practical handbook for developers and DevOps engineers working with Kubernetes, GitOps, Terraform, GitHub Actions, cloud infrastructure, and secrets management — with an optional Claude plugin layer for interactive guidance.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Domains](https://img.shields.io/badge/Domains-30-4c8eda)](references/)
[![Commands](https://img.shields.io/badge/Commands-25-e87c2b)](commands/)
[![Examples](https://img.shields.io/badge/Examples-26-6f42c1)](examples/)
[![Editors](https://img.shields.io/badge/Editors-VSCode%20%7C%20Cursor%20%7C%20Copilot-2ea44f)](EDITOR_INTEGRATIONS.md)
[![GitHub Stars](https://img.shields.io/github/stars/nitinjain999/platform-skills?style=flat&label=Stars&color=0e1117)](https://github.com/nitinjain999/platform-skills/stargazers)
[![Skill Check](https://img.shields.io/badge/SkillCheck-Validated-brightgreen)](tests/validate-skill.sh)

---

If this handbook saves you time, [give it a star](https://github.com/nitinjain999/platform-skills/stargazers) — it helps others find it.
Found a gap or a better pattern? [Contributions are welcome](CONTRIBUTING.md) — open an issue, improve a reference guide, or add an example.

---

## What is this?

This repository is a reference handbook for developers, DevOps engineers, SREs, and platform teams. It is structured in two independent layers:

- **Handbook** — `references/` and `examples/` are the main product. Every domain has a deep-dive guide and working example assets you can copy directly into your project. Use it on GitHub, from a local clone, or as a team knowledge base.
- **Claude plugin** — `SKILL.md` and `.claude-plugin/marketplace.json` add an optional routing layer so Claude surfaces the right section of the handbook when you ask platform engineering questions interactively.

Both layers work independently. The plugin is optional.

## Navigate

| I want to... | Go to |
|---|---|
| Get started in 5 minutes | [QUICKSTART.md](QUICKSTART.md) |
| Understand how AI agents and skills work | [HOW_IT_WORKS.md](HOW_IT_WORKS.md) |
| Full installation guide and troubleshooting | [INSTALLATION.md](INSTALLATION.md) |
| Read a domain guide | [references/](references/) |
| Copy a working example | [examples/](examples/) |
| Install as a Claude plugin | [Installation](#installation) |
| Learn how to use each slash command | [COMMANDS.md](COMMANDS.md) |
| Set up VSCode, Copilot, or Cursor | [EDITOR_INTEGRATIONS.md](EDITOR_INTEGRATIONS.md) |
| Contribute a pattern | [CONTRIBUTING.md](CONTRIBUTING.md) |

## Domains

| Domain | Reference guide | What it covers |
|---|---|---|
| <img src="https://cdn.simpleicons.org/kubernetes/326CE5" width="16" height="16" alt="Kubernetes"> Kubernetes | [references/kubernetes.md](references/kubernetes.md) | Cluster baseline, workload patterns, network policy, RBAC, pod security |
| 🛡️ Kyverno | [references/kyverno.md](references/kyverno.md) | Validate/mutate/generate/verifyImages policies, Audit→Deny promotion, PolicyException, PolicyReport, kyverno-cli testing, PSP/Gatekeeper migration |
| <img src="https://cdn.simpleicons.org/redhatopenshift/EE0000" width="16" height="16" alt="OpenShift"> OpenShift | [references/openshift.md](references/openshift.md) | Routes, SCC compatibility, operator usage, tenant isolation |
| <img src="https://cdn.simpleicons.org/argo/EF7B4D" width="16" height="16" alt="Argo CD"> Argo CD | [references/argocd.md](references/argocd.md) | App-of-apps design, ApplicationSet, sync control, promotion flows |
| <img src="https://cdn.simpleicons.org/flux/5468FF" width="16" height="16" alt="Flux CD"> Flux CD | [references/flux.md](references/flux.md) | Monorepo structure, reconciliation, multi-tenancy, image automation |
| <img src="https://cdn.simpleicons.org/amazonaws/FF9900" width="16" height="16" alt="AWS"> AWS | [references/aws.md](references/aws.md) | IAM least-privilege, IRSA, EKS, resource tagging, cost allocation |
| <img src="https://cdn.simpleicons.org/microsoftazure/0078D4" width="16" height="16" alt="Azure"> Azure | [references/azure.md](references/azure.md) | Workload identity, AKS, RBAC, resource tagging, Azure Policy |
| <img src="https://cdn.simpleicons.org/terraform/844FBA" width="16" height="16" alt="Terraform"> Terraform | [references/terraform.md](references/terraform.md) | Module design, state management, testing, CI/CD integration |
| <img src="https://cdn.simpleicons.org/githubactions/2088FF" width="16" height="16" alt="GitHub Actions"> GitHub Actions | [references/github-actions.md](references/github-actions.md) | Security hardening, OIDC, SHA pinning, reusable workflows |
| 🗺️ Platform model | [references/platform-operating-model.md](references/platform-operating-model.md) | Ownership boundaries, promotion flows, cross-tool design |
| 🔐 Secrets | [references/secrets.md](references/secrets.md) | External Secrets Operator, Sealed Secrets, provider setup, troubleshooting |
| <img src="https://cdn.simpleicons.org/linkerd/2BEDA7" width="16" height="16" alt="Linkerd"> Linkerd | [references/linkerd.md](references/linkerd.md) | mTLS, proxy injection, AuthorizationPolicy, observability, multi-cluster |
| <img src="https://cdn.simpleicons.org/linux/FCC624" width="16" height="16" alt="Linux"> Linux & Networking | [references/linux-networking.md](references/linux-networking.md) | Linux admin, DNS, load balancing, VPC/VNet design, connectivity troubleshooting |
| 🧠 Platform Mindset | [references/platform-mindset.md](references/platform-mindset.md) | DevEx, friction audits, RFC/ADR, incident comms, post-mortems, capacity planning |
| 🔒 Compliance | [references/compliance.md](references/compliance.md) | SOC 2 Trust Services Criteria in Terraform: IAM, encryption, detection, audit logging, backup, Checkov enforcement |
| <img src="https://cdn.simpleicons.org/helm/0F1689" width="16" height="16" alt="Helm"> Helm | [references/helm.md](references/helm.md) | Chart scaffolding, values design, template patterns, security hardening, lint/validation pipeline, GitOps integration |
| 🔌 MCP | [references/mcp.md](references/mcp.md) | Model Context Protocol server/client development, TypeScript and Python SDKs, stdio/SSE transports, security, testing |
| <img src="https://cdn.simpleicons.org/prometheus/E6522C" width="16" height="16" alt="Prometheus"> Observability | [references/observability.md](references/observability.md) | Structured logging, Prometheus metrics, OpenTelemetry tracing, Grafana dashboards, alerting rules, k6 load testing, capacity planning |
| 📝 Documentation | [references/documentation.md](references/documentation.md) | Docstrings (Google/NumPy/JSDoc), OpenAPI 3.1 specs, doc sites (MkDocs/TypeDoc), developer guides |
| <img src="https://cdn.simpleicons.org/datadog/632CA6" width="16" height="16" alt="Datadog"> Datadog | [references/datadog.md](references/datadog.md) | Agent Helm setup, APM instrumentation, log management, monitors/dashboards/SLOs as Terraform, pup CLI, Datadog Labs skills |
| 🤖 LLM Observability | [references/llm-observability.md](references/llm-observability.md) | Datadog LLMObs instrumentation (Python/Node.js), eval bootstrap, trace RCA, experiment analysis |
| <img src="https://cdn.simpleicons.org/dynatrace/1496FF" width="16" height="16" alt="Dynatrace"> Dynatrace | [references/dynatrace.md](references/dynatrace.md) | OneAgent Kubernetes Operator, custom metrics, SLOs, dashboards and alerting via Terraform provider |
| <img src="https://cdn.simpleicons.org/git/F05032" width="16" height="16" alt="Git"> Conventional Commits | [references/conventional-commits.md](references/conventional-commits.md) | Message structure, type classification, atomic staging, commitlint/husky/semantic-release tooling |
| 📋 OPA / Conftest | [references/opa.md](references/opa.md) | Rego v1 syntax, rule types, unit tests, fmt/regal/verify validation pipeline, GitHub Actions integration |
| 🔍 PR Review | [references/pr-review.md](references/pr-review.md) | Cost impact, environment drift, ownership gaps, SOC 2 compliance, deprecated API / version hygiene, rollback feasibility |
| 🧵 PR Comment Triage | [commands/triage.md](commands/triage.md) | `/platform-skills:triage` classifies PR comments, applies valid fixes, replies, and resolves review threads |
| ⚡ KEDA | [references/keda.md](references/keda.md) | ScaledObject, ScaledJob, TriggerAuthentication, Prometheus/SQS/Kafka/Redis/Cron/HTTP/Azure scalers, scale-to-zero, IRSA, GitOps integration, troubleshooting — `/platform-skills:keda` |
| 🤖 Agent Self-Improvement | [references/agent-self-improve.md](references/agent-self-improve.md) | `.learnings/` directory setup, LRN/ERR/FEAT entry lifecycle, WAL protocol, working buffer, VFM scoring, ADL decision logic, Six Operating Pillars, heartbeat, reverse prompting, proactive agent behavior — `/platform-skills:self-improve` |
| 🔗 Supply Chain Security | [references/supply-chain.md](references/supply-chain.md) | Cosign keyless signing, Syft SBOM generation and attestation, Trivy/Grype CVE scanning with severity gates, SLSA Level 2 provenance, Kyverno ImageValidatingPolicy enforcement — `/platform-skills:supply-chain` |
| 🦅 Runtime Security | [references/runtime-security.md](references/runtime-security.md) | Falco eBPF deployment on EKS/GKE, custom rule authoring, Falcosidekick alert routing, rule debugging, bridging Falco signals to Kyverno admission enforcement — `/platform-skills:runtime-security` |
| 💥 Chaos Engineering | [references/chaos.md](references/chaos.md) | Litmus Chaos v3 and Chaos Mesh v2 fault injection, steady-state hypothesis (httpProbe/promProbe), blast radius scoping, GameDay workflow, recurring schedules, DORA feedback loop — `/platform-skills:chaos` |
| 📊 DORA Metrics | [references/dora.md](references/dora.md) | Deployment Frequency, Lead Time, Change Failure Rate, MTTR — GitHub Actions + Prometheus Pushgateway instrumentation, recording rules, Grafana dashboards, SaaS decision matrix, anti-pattern detection — `/platform-skills:dora` |

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

For VSCode, Copilot, Cursor, and JetBrains setup — project level and global level — see [EDITOR_INTEGRATIONS.md](EDITOR_INTEGRATIONS.md).

## Repository structure

```
platform-skills/
├── references/                         # Deep-dive guides — one per domain
│   ├── platform-operating-model.md
│   ├── kubernetes.md
│   ├── kyverno.md                      # Kyverno admission policies (v1.11.0)
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
│   ├── platform-mindset.md
│   ├── compliance.md                   # SOC 2 controls in Terraform (v1.6.0)
│   ├── helm.md                         # Helm chart patterns, lint pipeline, values design
│   ├── pr-review.md                    # PR review: cost, drift, ownership, compliance, upgrade, rollback (v1.12.0)
│   ├── keda.md                         # KEDA event-driven autoscaling (v1.14.0)
│   └── llm-observability.md                # Datadog LLMObs: instrumentation, evals, trace RCA (v1.20.0)
│
├── examples/                           # Working examples and handbook snippets
│   ├── flux/basic-monorepo/            # Complete Flux CD monorepo structure
│   ├── kubernetes/                     # Namespace, deployment, network policy, PDB
│   ├── kyverno/                        # ValidatingPolicy, GeneratingPolicy examples + kyverno-cli test manifest (v1.11.0)
│   ├── openshift/                      # Route, ResourceQuota, LimitRange
│   ├── argocd/app-of-apps/             # Root application manifest
│   ├── aws/iam/                        # Least-privilege IAM policy examples
│   ├── azure/workload-identity/        # Managed identity + federated credential
│   ├── terraform/eks-cluster/          # Production EKS Terraform module
│   ├── github-actions/                 # CI/CD, Flux sync, container build workflows
│   ├── helm/web-service/               # Production Helm chart: Deployment, HPA, PDB, NetworkPolicy, schema
│   ├── triage/                         # PR comment triage scenarios and fixtures (v1.13.0)
│   ├── keda/                           # ScaledObject, ScaledJob, TriggerAuthentication examples (v1.14.0)
│   └── compliance/                     # SOC 2 Terraform examples (v1.6.0)
│       ├── checkov-config.yaml         # Checkov config grouped by SOC 2 criterion
│       ├── iam/                        # CC6.1/CC6.2: IAM, IRSA, OIDC, SCPs
│       ├── logging/                    # CC7.2: CloudTrail, Config, VPC flow logs
│       ├── network/                    # CC6.6: WAF, security groups, flow logs
│       ├── encryption-data-services/   # CC6.7: DynamoDB, ECR, ElastiCache, OpenSearch, Kinesis, EFS, Redshift
│       ├── vulnerability/              # CC6.8: Inspector v2, ECR scanning, SSM patching
│       ├── detection/                  # CC7.1: GuardDuty, CIS CloudWatch alarms, Security Hub
│       ├── incident-response/          # CC7.3: SNS, EventBridge, PagerDuty
│       └── backup/                     # A1.2/A1.3: Backup Plan, vault lock, cross-region DR
│
├── SKILL.md                            # Claude plugin routing and patterns
├── .claude-plugin/marketplace.json     # Marketplace metadata
├── .github/workflows/                  # Validation and release automation
├── tests/validate-skill.sh             # Skill structure consistency checks
└── renovate.json                       # Automated dependency updates
```

## Roadmap

**Current release: v1.20.0** — 25 commands, 31 domain reference guides, 50+ wiki pages.

Full version history is in [CHANGELOG.md](CHANGELOG.md).

**Planned**
- [ ] GCP: landing zone, GKE, Workload Identity, and IAM patterns
- [ ] Istio: traffic management, mTLS, telemetry (counterpart to Linkerd domain)
- [ ] SOC 2 for Kubernetes: Kyverno policies mapped to TSC criteria, pod security admission, `kube-bench` CIS Benchmark integration
- [ ] OpenShift operator lifecycle: OLM, CatalogSource, operator upgrade patterns
- [ ] Argo CD ApplicationSet fleet patterns: cluster generators, matrix strategies, progressive rollout
- [ ] Multi-cloud networking: Transit Gateway, VNet peering, PrivateLink, cross-cloud DNS

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

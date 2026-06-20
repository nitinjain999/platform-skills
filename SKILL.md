---
name: platform-skills
description: "Use when troubleshooting, implementing, reviewing, or auditing platform infrastructure as a system — where Kubernetes, GitOps, CI/CD, and security concerns intersect. Provides structured diagnosis with blast radius, validation steps, and rollback plan for: Kubernetes, Flux CD, Argo CD, Terraform, GitHub Actions (composite actions, OIDC, SHA pinning), AWS, Azure, GKE, Linkerd, KEDA, Karpenter, supply chain security (Cosign, SBOM, SLSA), Falco, Chaos Engineering, DORA metrics, Datadog/Dynatrace/LLM observability, SOC 2, and PR review."
---

# Platform Skills

Use this skill for hands-on help with Kubernetes, GitOps, cloud infrastructure, CI/CD, secrets management, service mesh, Linux administration, networking, and platform product thinking — whether you are a solo developer or part of a large platform team.

## Pick the right tool for the job

| Layer | When to use |
|---|---|
| `Terraform` | Cloud primitives, cluster bootstrap, IAM, networking, secrets backends |
| `Kubernetes` | Workload, RBAC, network policy, platform baseline across distributions |
| `OpenShift` | Kubernetes patterns adapted to OpenShift routing, SCC, and OLM |
| `Flux` / `Argo CD` | In-cluster reconciliation, Helm releases, workload promotion |
| `GitHub Actions` | Validate, package, gate, and promote. Keep workflows declarative. |
| `AWS` / `Azure` / `GKE` | Provider-specific account, identity, and governance patterns |
| `Linkerd` | Automatic mTLS, golden-signal observability, traffic management |
| `Linux & Networking` | DNS, load balancer routing, VPC/VNet, kernel tuning, connectivity |
| `Compliance` | SOC 2 controls in Terraform — IAM, encryption, audit logging, Checkov |
| `Helm (Helmcheck)` | Chart scaffolding, lint/validate pipeline, values design, security hardening |
| `MCP` | Build/debug MCP servers — tools, resources, transports, auth |
| `AWS MCP Profiles` | Discover/switch AWS profiles across VS Code + Claude Code MCP configs — multi-account, SSO, Granted, credential_process |
| `Observability` | Prometheus, OpenTelemetry, Grafana, alerting, k6 load tests, capacity |
| `Documentation` | Docstrings (Google/NumPy/JSDoc), OpenAPI 3.1, MkDocs, guides |
| `Datadog` | Agent on Kubernetes, APM, monitors, dashboards, SLOs, LLMObs |
| `Dynatrace` | OneAgent Operator, auto-instrumentation, anomaly detection, SLOs |
| `Conventional Commits` | Generate WHY-driven commit messages, atomic staging, validate |
| `OPA / Conftest` | Rego policies, unit tests, fmt/regal/verify pipeline, debug |
| `Kyverno` | CEL-based ValidatingPolicy, MutatingPolicy, ImageValidatingPolicy |
| `PR Review` | Cost, drift, ownership, SOC 2, deprecated APIs, rollback feasibility |
| `PR Triage` | Classify comments ACTIONABLE_FIX/INFORMATIONAL/NOT_APPLICABLE, fix, reply |
| `KEDA` | ScaledObject/ScaledJob, all scalers, TriggerAuthentication, scale-to-zero |
| `Karpenter` | NodePool/EC2NodeClass design, Spot diversity, disruption strategy, capacity planning, audit, CA migration, v0→v1 upgrade |
| `Agent Self-Improvement` | `.learnings/` workspace, LRN/ERR lifecycle, WAL, VFM, ADL |
| `Supply Chain Security` | Cosign signing, Syft SBOM, Trivy/Grype CVE gates, SLSA Level 2 |
| `Runtime Security` | Falco eBPF, custom rules, Falcosidekick routing, Kyverno enforcement |
| `Awesome Docs` | Animated SVG Markdown — README, runbook, RFC, architecture, post-mortem |
| `Composite Actions` | Full action repo scaffold, SHA pinning, secrets-as-inputs, actionlint |
| `GitOps debug` | 5-workflow structured debug → 5-section report with root cause |
| `GitOps audit` | 6-phase repo audit → prioritized Critical/Warning/Info report |
| `Platform Mindset` | DevEx, friction audits, RFC/ADR, incident communication, post-mortems |
| `Renovate` | Dependency update automation — generate renovate.json from repo scan, emit GHA validation workflow |
| `Setup Agents` | Scaffold multi-agent AI configs for any repo — interview-driven, specific to this codebase |

If a task spans multiple areas, decide which layer owns the source of truth and keep the other layers consumers of that state.

## Apply These Platform Rules

- Separate reusable platform building blocks from live environment configuration.
- Prefer GitOps pull-based reconciliation for cluster state and CI push-based automation for validation and packaging.
- Choose either Flux or Argo CD for a given ownership boundary unless the task is explicitly about migration between them.
- Keep Terraform responsible for bootstrapping clusters, cloud resources, secrets backends, and access primitives. Do not let Flux or Argo CD recreate those foundations unless there is a deliberate controller-based design.
- Use Flux or Argo CD for in-cluster add-ons, workloads, Helm releases, and app-level environment promotion after bootstrap.
- Use GitHub Actions for checks, plans, policy gates, artifact publishing, and promotion orchestration. Do not store long-lived environment truth in workflow YAML.
- Prefer OIDC or workload identity over static cloud credentials.
- Model environments explicitly. Promotion should be visible in Git history and reversible by commit rollback.
- For Linux and networking changes, validate at each layer before escalating: confirm the process is listening (`ss -tulnp`), then L3 reachability (`ping`), L4 connectivity (`nc -zv`), L7 response (`curl -v`), and security group / NACL rules last. Do not skip layers.
- For every Terraform change, enforce in order: `terraform fmt -check -recursive`, `terraform validate`, `conftest test` (OPA/Rego policy gates — runs **after validate, before plan** as a blocking gate), `tflint --recursive`, security scan (`tfsec` or `checkov`), then `plan`. Do not let format, lint, or policy failures reach the plan step.
- For every Helm chart change, enforce in order: `helm lint --strict`, `helm template --debug`, `kubeconform -strict -summary` on rendered output, `checkov` on rendered manifests, then `helm test` in-cluster. Fail CI on any `helm lint --strict` warning.
- Enforce a tag baseline on all cloud resources. The specific keys are an organizational decision. Use AWS `default_tags` (provider level) or Azure `merge(local.common_tags, {...})` (module local) so the baseline is applied once, not repeated per resource. Back it with AWS Tag Policies or Azure Policy so resources created outside Terraform are also covered.

## Structure the Response

For design or implementation work, provide output in this order:

1. Target architecture and ownership boundaries
2. Repository or directory layout
3. Identity, secrets, and promotion model
4. Validation and deployment workflow
5. Risks, tradeoffs, and migration path

When asked to generate code, start from the thinnest useful slice that proves the pattern and note which layer remains intentionally out of scope.

## Pick the Right Reference Files

Load only the files needed for the current request.

| File | Scope |
|---|---|
| references/platform-operating-model.md | Repo topology, ownership boundaries, promotion flow |
| references/terraform.md | Module patterns, environments, state, testing |
| references/checkov.md | Checkov bootstrap, scan modes, provider detection, private module auth, output formats, fix mode, custom checks |
| references/kubernetes.md | Cluster baseline, workload, RBAC, policy |
| references/openshift.md | OpenShift routing, SCC, OLM, tenancy |
| references/fluxcd.md | Bootstrap, reconciliation, FluxInstance, ResourceSet, image automation |
| references/fluxcd-sources.md | GitRepository, OCIRepository, HelmRepository, Bucket, ArtifactGenerator |
| references/fluxcd-resourcesets.md | ResourceSet templating, input strategies, gitless fleet patterns |
| references/fluxcd-notifications.md | Provider, Alert, Receiver, Slack/Datadog/GitHub commit status |
| references/fluxcd-operator.md | FluxInstance sizing, multi-tenancy, kustomize patches, FluxReport |
| references/fluxcd-kustomization.md | CEL readyExpr, postBuild substitution, SOPS, SSA annotations |
| references/fluxcd-helmrelease.md | chartRef vs chart.spec, drift detection, post-renderers, CRD lifecycle |
| references/fluxcd-terraform.md | Flux Operator bootstrap via Terraform |
| references/fluxcd-mcp.md | AI-assisted FluxCD debugging via Flux MCP server |
| references/fluxcd-migration.md | v2.7/v2.8 API removals, CLI and Operator upgrade paths |
| references/fluxcd-security.md | Secrets, source auth, OCI supply chain, RBAC, image automation security |
| references/fluxcd-troubleshooting.md | Incident cheat-sheet — symptom → cause → fix per controller |
| references/argocd.md | App delivery, ApplicationSet, sync policies |
| references/aws.md | Landing zones, IAM, EKS patterns |
| references/aws-mcp-profiles.md | AWS MCP profile management — multi-account SSO, Granted, credential_process, context budget, starter kits |
| references/azure.md | Management groups, identity, AKS patterns |
| references/aws-cloudfront.md | CloudFront distributions, OAC, Lambda@Edge, security headers |
| references/aws-waf.md | Web ACLs, managed rules, rate limiting, Firewall Manager |
| references/github-actions.md | Reusable workflows, OIDC, delivery controls |
| references/composite-actions.md | Composite action scaffold, SHA pinning, secrets-as-inputs, actionlint |
| references/secrets.md | External Secrets Operator, Sealed Secrets, secrets strategy |
| references/linkerd.md | mTLS, observability, traffic management, multi-cluster |
| references/linux-networking.md | DNS, load balancing, VPC/VNet, kernel tuning, connectivity |
| references/platform-mindset.md | DevEx, friction audits, RFC/ADR, incident communication, post-mortems |
| references/compliance.md | SOC 2 controls, IAM, encryption, audit logging, Checkov evidence |
| references/helm.md | Chart scaffolding, lint pipeline, values design, GitOps integration |
| references/mcp.md | MCP protocol, SDKs, transports, schema validation, auth, testing |
| references/observability.md | Prometheus, OpenTelemetry, Grafana, alerting, k6, capacity |
| references/documentation.md | Docstrings, OpenAPI 3.1, MkDocs, developer guides |
| references/datadog.md | Agent, APM, monitors, dashboards, SLOs, LLMObs, FluxCD monitoring |
| references/llm-observability.md | LLMObs instrumentation, eval bootstrap, trace RCA |
| references/dynatrace.md | OneAgent, auto-instrumentation, anomaly detection, SLOs, Terraform |
| references/conventional-commits.md | Commit message structure, atomic staging, commitlint, semantic-release |
| references/opa.md | Rego v1 syntax, rule types, unit tests, fmt/regal/verify pipeline |
| references/kyverno.md | ValidatingPolicy, MutatingPolicy, ImageValidatingPolicy, CEL, kyverno-cli |
| references/pr-review.md | Cost, drift, ownership, compliance, deprecated APIs, rollback scoring |
| references/keda.md | ScaledObject, ScaledJob, scalers, TriggerAuthentication, scale-to-zero |
| references/karpenter.md | NodePool, EC2NodeClass, NodeClaim, IAM, Spot, disruption, private cluster, CA migration |
| references/agent-self-improve.md | `.learnings/` workspace, WAL, VFM, ADL, status/migrate |
| references/supply-chain.md | Cosign, Syft SBOM, Trivy/Grype, SLSA Level 2, ImageValidatingPolicy |
| references/trivy.md | Trivy bootstrap, image/fs/repo/secrets/sbom/k8s modes, severity gating, Trivy Operator via Flux HelmRelease |
| references/runtime-security.md | Falco eBPF, custom rules, Falcosidekick, Kyverno enforcement |
| references/chaos.md | Litmus Chaos, Chaos Mesh, steady-state hypothesis, GameDay |
| references/dora.md | Deployment Frequency, Lead Time, CFR, MTTR, Prometheus instrumentation |
| references/awesome-docs.md | Animated SVG Markdown — architecture flow, lifecycle, carousel, timeline |
| references/setup-agents.md | Mode routing table, signal→roster decisions, manifest format |
| references/setup-agents-build.md | Generate/upgrade step-by-step build guide (language scan, interview, render, verify) |
| references/setup-agents-add.md | Add a new agent or tool target to an existing setup |
| references/setup-agents-review.md | Audit existing agent files for staleness, misalignment, missing sections |
| references/setup-agents-schemas.md | Per-tool frontmatter schemas, managed-file markers, MCP wiring |
| references/setup-agents-template.md | AGENTS.md template pointer and render.sh invocation |

## Slash Commands

For explicit, repeatable workflows use these commands:

- `/platform-skills:debug` — structured troubleshooting for any platform symptom
- `/platform-skills:audit` — production-readiness review of any manifest, Terraform, or workflow
- `/platform-skills:terraform` — full fmt/validate/tflint/security pipeline + blast radius review
- `/platform-skills:checkov` — Checkov bootstrap, static and plan-level Terraform scanning for AWS/Azure/GCP/EKS, private GitHub module auth via `gh` CLI, pre-commit generation, multi-format output, baseline, and AI-generated fix mode
- `/platform-skills:trivy` — scan container images, filesystems, git repos, and existing SBOMs for CVEs, secrets, and license violations; three-layer wizard routes intent → goal → tuned scan; continuous cluster monitoring via Trivy Operator (Flux HelmRelease); hard handoffs to Checkov (IaC), Kyverno (admission), and supply-chain (SBOM generation/signing)
- `/platform-skills:fluxcd` — FluxCD entry point: routes to debug (live cluster issue), audit (repo health check), or helm (chart review) based on your input
- `/platform-skills:gitops debug` — Flux CD and Argo CD live cluster troubleshooting (5-workflow structured debug)
- `/platform-skills:gitops audit` — Flux CD GitOps repository 6-phase audit (discovery, validation, API compliance, best practices, security, report)
- `/platform-skills:linkerd` — Linkerd mTLS, injection, policy, and multi-cluster diagnostics
- `/platform-skills:linux` — Linux administration, DNS, load balancing, VPC/VNet, and connectivity troubleshooting
- `/platform-skills:product` — product thinking, friction audits, DevEx, RFC/ADR, incident updates, post-mortems
- `/platform-skills:compliance` — SOC 2 gap analysis, control implementation, evidence collection, and Checkov remediation for Terraform
- `/platform-skills:helmchart` — Helm chart scaffolding, structural review, and security audit with full lint/validation pipeline
- `/platform-skills:mcp` — MCP server/client scaffolding, protocol review, and integration debugging
- `/platform-skills:aws-profile` — discover, switch, and validate AWS profiles for MCP servers across VS Code and Claude Code
- `/platform-skills:observability` — instrument services, build dashboards, write alerts, run load tests, plan capacity
- `/platform-skills:document` — generate docstrings, OpenAPI specs, documentation sites, and getting started guides
- `/platform-skills:datadog` — Datadog Agent setup, APM instrumentation, monitors, dashboards, SLOs, pup CLI operations, LLM Observability instrumentation, evaluators, and debugging
- `/platform-skills:dynatrace` — OneAgent deployment, instrumentation, anomaly detection, SLOs, and debugging
- `/platform-skills:commit` — analyze diff, generate conventional commit message, stage files atomically, validate message
- `/platform-skills:opa` — generate Rego policies, write unit tests, run fmt/regal/verify pipeline, explain or debug policies
- `/platform-skills:kyverno` — generate, test, audit, debug, or migrate Kyverno CEL-based admission policies
- `/platform-skills:pr-review` — comprehensive PR review: cost, drift, ownership, compliance, upgrade, rollback
- `/platform-skills:triage` — triage a PR comment (bot or human): classify as ACTIONABLE_FIX / INFORMATIONAL / NOT_APPLICABLE, produce the exact fix if needed, and write the thread reply
- `/platform-skills:keda` — design, generate, debug, or review KEDA ScaledObject/ScaledJob autoscaling
- `/platform-skills:karpenter` — install, generate NodePool/EC2NodeClass, debug provisioning, plan capacity before rollout, audit scale history, migrate from Cluster Autoscaler, or upgrade (including v0→v1 CRD migration)
- `/platform-skills:self-improve` — bootstrap global or project-local `.learnings/` workspace (`init global`/`init local`), log/review/promote learnings and errors, status overview, and migrate between scopes
- `/platform-skills:supply-chain` — sign images, generate and attest SBOMs, run CVE severity gates, enforce image signatures in Kubernetes, and generate SLSA Level 2 provenance
- `/platform-skills:runtime-security` — deploy Falco with eBPF, write custom rules, route alerts, debug why a rule is not firing, and bridge Falco signals to Kyverno admission enforcement
- `/platform-skills:chaos` — install Litmus Chaos or Chaos Mesh, generate fault experiments, schedule recurring chaos, run structured GameDay, debug stuck experiments, report results
- `/platform-skills:dora` — instrument DORA metrics in GitHub Actions, generate Grafana dashboards, benchmark against performance bands, debug missing metric data
- `/platform-skills:awesome-docs` — generate any animated Markdown document (README, architecture guide, runbook, tutorial, RFC, post-mortem, or custom), convert existing Markdown to animated, update diagrams, diff for staleness, audit quality, preview locally, or export to Confluence/Notion HTML
- `/platform-skills:aws` — CloudFront distributions, WAF web ACLs, Lambda@Edge, CloudFront Functions, Firewall Manager multi-account enforcement, and Terraform module generation with best practices
- `/platform-skills:composite-actions` — generate a full composite action repo scaffold, review an existing action.yml, harden with SHA pinning and env isolation, or generate a test workflow
- `/platform-skills:renovate` — generate renovate.json for any repo, or emit a GHA workflow to validate it on PR
- `/platform-skills:setup-agents` — scaffold multi-agent AI configs for any repo: ranked scan, interview-driven, generate/upgrade/add/review
- Working Flux CD examples: examples/fluxcd/

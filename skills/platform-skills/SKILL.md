---
name: platform-skills
description: Hands-on guidance for platform and DevOps engineers working with Kubernetes, Terraform, GitOps, GitHub Actions, AWS, Azure, Linkerd, Linux, networking, compliance, KEDA event-driven autoscaling, and self-improving agent patterns. Use when designing or troubleshooting Kubernetes workloads and RBAC, writing Terraform modules, configuring Flux or Argo CD, setting up CI/CD pipelines, managing cloud identity and IAM, handling secrets, diagnosing DNS or VPC connectivity, operating a service mesh, applying product thinking to developer experience, implementing SOC 2 compliance controls in Terraform, scaling workloads with KEDA scalers (SQS, Kafka, Prometheus, Cron, HTTP), or bootstrapping .learnings/ directories, WAL protocol, VFM scoring, and proactive agent behavior — at any scale, for any team size, supply chain security (Cosign, Syft, Trivy, SLSA, image signing enforcement), Kubernetes runtime security (Falco eBPF, custom rules, Falcosidekick alert routing), and Chaos Engineering (Litmus Chaos v3, Chaos Mesh v2, steady-state hypothesis, GameDay workflow), and DORA metrics (Deployment Frequency, Lead Time, Change Failure Rate, MTTR — GitHub Actions instrumentation, Prometheus recording rules, Grafana dashboards)
---

# Platform Skills

Use this skill for hands-on help with Kubernetes, GitOps, cloud infrastructure, CI/CD, secrets management, service mesh, Linux administration, networking, and platform product thinking — whether you are a solo developer or part of a large platform team.

## Pick the right tool for the job

Match the task to the right layer:

1. `Terraform`: Provision cloud primitives, cluster bootstrap, shared services, identity, networking, and policy foundations.
2. `Kubernetes`: Define workload, namespace, RBAC, service, policy, and platform baseline patterns that apply across distributions.
3. `OpenShift`: Adapt Kubernetes patterns to OpenShift-native routing, security, operator, and tenancy constraints.
4. `Flux` or `Argo CD`: Reconcile in-cluster desired state after bootstrap and manage promotion of workloads or platform add-ons.
5. `GitHub Actions`: Validate, package, test, and promote changes. Keep workflows declarative and reusable.
6. `AWS` or `Azure`: Apply provider-specific account, subscription, identity, and governance patterns.
7. `Linkerd`: Apply service mesh for automatic mTLS, golden-signal observability, and traffic management between workloads.
8. `Linux & Networking`: Diagnose Linux systems and network problems — DNS resolution, load balancer routing, VPC/VNet design, kernel tuning, and connectivity troubleshooting.
9. `Platform Mindset`: Treat developers as customers. Apply product thinking, friction audits, DevEx metrics, RFC/ADR processes, incident communication, and blameless post-mortems.
10. `Cross-platform`: Design repo boundaries, ownership, promotion flows, and security controls first.
11. `Compliance`: Implement SOC 2 Trust Services Criteria controls in Terraform — IAM least privilege, encryption, audit logging, network security, and change management. Run Checkov for continuous enforcement and collect evidence for auditors.
12. `Helm (Helmcheck)`: Build, lint, and audit Helm charts — scaffolding, values design, template patterns, dependency management, security hardening, and the full lint/validation pipeline.
13. `MCP (Model Context Protocol)`: Build, review, and debug MCP servers and clients — tool and resource handlers, Zod/Pydantic schema validation, stdio/HTTP/SSE transports, protocol compliance, auth, and rate limiting.
14. `Observability`: Instrument services with structured logging, Prometheus metrics, and OpenTelemetry tracing. Build Grafana dashboards, write alerting rules, run k6 load tests, and plan capacity.
15. `Documentation`: Generate and validate inline docstrings (Google/NumPy/JSDoc), OpenAPI 3.1 specs, documentation sites (MkDocs, TypeDoc), and getting started guides.
16. `Datadog`: Deploy and configure the Datadog Agent on Kubernetes, instrument services with APM and log correlation, write monitors, dashboards, SLOs, and synthetic tests — all as Terraform-managed resources.
17. `Dynatrace`: Deploy OneAgent via the Kubernetes Operator with automatic injection, configure anomaly detection, ingest custom metrics, define SLOs, and manage dashboards and alerting profiles with the Dynatrace Terraform provider.
18. `Conventional Commits`: Analyze git diffs, generate commit messages that explain WHY a change was made, intelligently stage files for atomic commits, and validate messages against the Conventional Commits specification.
19. `OPA / Conftest`: Generate Rego policies with correct rule types and namespacing, write unit tests, run the full validation pipeline (fmt → regal lint → conftest verify → integration test), explain existing policies, and debug why a rule is not firing.
20. `Kyverno`: Write and maintain Kubernetes-native admission policies using the CEL-based types — ValidatingPolicy, MutatingPolicy, GeneratingPolicy, ImageValidatingPolicy (all `policies.kyverno.io/v1`). Covers matchConstraints, matchConditions, CEL validations/mutations, generator.Apply(), Audit→Deny promotion, PolicyException, and kyverno-cli testing.
21. `PR Review`: Comprehensive pre-merge risk review across six dimensions — cost impact, environment drift, ownership and governance gaps, SOC 2 compliance, deprecated API / version hygiene, and rollback feasibility scoring.
22. `PR Comment Triage`: Triage bot or human PR comments, classify them as ACTIONABLE_FIX / INFORMATIONAL / NOT_APPLICABLE, make the minimal fix when valid, reply on the thread, and resolve it through `gh`.
23. `KEDA`: Design, generate, debug, and review KEDA ScaledObject and ScaledJob resources. Covers all major scalers (Prometheus, SQS, Kafka, Redis, Cron, HTTP Add-on, Azure Service Bus), TriggerAuthentication with IRSA/Workload Identity, scaling lifecycle tuning, scale-to-zero patterns, and GitOps integration.
24. `Agent Self-Improvement`: Bootstrap and operate self-improving, proactive agent workspaces. Covers `.learnings/` directory setup, LRN/ERR/FEAT entry lifecycle, recurring pattern detection, promotion to project memory, WAL protocol, working buffer, VFM scoring, ADL decision logic, Six Operating Pillars, heartbeat, and reverse prompting.
25. `Supply Chain Security`: Secure the build pipeline and image lifecycle with Cosign keyless signing (Sigstore/Rekor), Syft SBOM generation and attestation, Trivy/Grype CVE scanning with severity gates, SLSA Level 2 provenance, and Kyverno ImageValidatingPolicy admission enforcement. All open-source, no license cost.
26. `Runtime Security`: Detect in-container threats at the syscall level with Falco (eBPF driver, CNCF, no license cost). Covers eBPF driver deployment on EKS/GKE, custom rule authoring, Falcosidekick alert routing to Slack/PagerDuty/webhook, rule debugging, and bridging runtime signals to Kyverno admission enforcement.

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
- For every Terraform change, enforce in order: `terraform fmt -check -recursive`, `terraform validate`, `tflint --recursive`, security scan (`tfsec` or `checkov`), then `plan`. Do not let format or lint failures reach the plan step.
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

- For repo topology, boundaries, and promotion flow, read [references/platform-operating-model.md](references/platform-operating-model.md).
- For Terraform module, environment, testing, and state guidance, read [references/terraform.md](references/terraform.md).
- For cluster baseline, workload, RBAC, and policy guidance, read [references/kubernetes.md](references/kubernetes.md).
- For OpenShift-specific operating patterns, read [references/openshift.md](references/openshift.md).
- For Flux bootstrap, reconciliation, image automation, and app delivery guidance, read [references/flux.md](references/flux.md).
- For Argo CD app delivery and application set patterns, read [references/argocd.md](references/argocd.md).
- For AWS landing zones, IAM, and EKS-oriented patterns, read [references/aws.md](references/aws.md).
- For Azure management groups, identity, and AKS-oriented patterns, read [references/azure.md](references/azure.md).
- For reusable workflows, OIDC, and delivery controls, read [references/github-actions.md](references/github-actions.md).
- For secrets strategy, External Secrets Operator, and Sealed Secrets patterns, read [references/secrets.md](references/secrets.md).
- For Linkerd service mesh, mTLS, observability, traffic management, and multi-cluster, read [references/linkerd.md](references/linkerd.md).
- For Linux administration, DNS, load balancing, VPC/VNet design, kernel tuning, and network troubleshooting, read [references/linux-networking.md](references/linux-networking.md).
- For product mindset, developer experience, friction audits, RFC/ADR, incident communication, post-mortems, and capacity planning, read [references/platform-mindset.md](references/platform-mindset.md).
- For SOC 2 Trust Services Criteria controls in Terraform — IAM, encryption, audit logging, network security, change management, Checkov enforcement, and audit evidence — read [references/compliance.md](references/compliance.md).
- For Helm chart scaffolding, template patterns, values design, lint pipeline, and GitOps integration, read [references/helm.md](references/helm.md).
- For MCP server and client development — protocol, TypeScript/Python SDKs, schema validation, transports, security, and testing — read [references/mcp.md](references/mcp.md).
- For observability instrumentation, Prometheus metrics, OpenTelemetry tracing, alerting rules, Grafana dashboards, load testing, and capacity planning, read [references/observability.md](references/observability.md).
- For code documentation — Python docstrings, JSDoc, OpenAPI 3.1 specs, documentation sites, and developer guides — read [references/documentation.md](references/documentation.md).
- For Datadog Agent setup, APM, log management, monitors, dashboards, SLOs, and synthetic tests — read [references/datadog.md](references/datadog.md).
- For Dynatrace OneAgent Operator, auto-instrumentation, custom metrics, SLOs, anomaly detection, and Terraform provider — read [references/dynatrace.md](references/dynatrace.md).
- For Conventional Commits — type classification, scope rules, breaking changes, message structure, atomic commits, commitlint, husky, semantic-release, and validation rules — read [references/conventional-commits.md](references/conventional-commits.md).
- For OPA / Conftest — Rego v1 syntax, rule types, package namespacing, input shapes, unit tests, validation pipeline (fmt/regal/verify), GitHub Actions integration, and troubleshooting — read [references/opa.md](references/opa.md).
- For Kyverno CEL-based admission policies — ValidatingPolicy, MutatingPolicy, GeneratingPolicy, ImageValidatingPolicy, matchConstraints, matchConditions, Audit→Deny promotion, PolicyException, kyverno-cli testing, and migration from legacy ClusterPolicy — read [references/kyverno.md](references/kyverno.md).
- For comprehensive PR review — cost impact, environment drift, ownership gaps, SOC 2 compliance, deprecated APIs, version hygiene, rollback feasibility, and bot comment triage — read [references/pr-review.md](references/pr-review.md).
- For KEDA event-driven autoscaling — ScaledObject, ScaledJob, TriggerAuthentication, IRSA, scalers (Prometheus, SQS, Kafka, Redis, Cron, HTTP Add-on, Azure Service Bus), scaling lifecycle, security patterns, and troubleshooting — read [references/keda.md](references/keda.md).
- For agent self-improvement patterns — `.learnings/` directory, WAL protocol, VFM scoring, ADL Protocol, working buffer, and proactive agent behavior — read [references/agent-self-improve.md](references/agent-self-improve.md).
- For supply chain security — Cosign keyless signing, Syft SBOM generation and attestation, Trivy/Grype CVE scanning, SLSA Level 2 provenance, and Kyverno ImageValidatingPolicy enforcement — read [references/supply-chain.md](references/supply-chain.md).
- For Kubernetes runtime security — Falco eBPF deployment on EKS/GKE, custom rule authoring, Falcosidekick alert routing, and bridging Falco signals to Kyverno admission enforcement — read [references/runtime-security.md](references/runtime-security.md).
- For Chaos Engineering — Litmus Chaos v3 and Chaos Mesh v2 fault injection, steady-state hypothesis, blast radius scoping, GameDay workflow, and DORA feedback loop — read [references/chaos.md](references/chaos.md).
- For DORA metrics — Deployment Frequency, Lead Time for Changes, Change Failure Rate, and MTTR instrumentation via GitHub Actions and Prometheus, SaaS tool selection, and anti-pattern detection — read [references/dora.md](references/dora.md).

Load only the files needed for the current request.

## Slash Commands

For explicit, repeatable workflows use these commands:

- `/platform-skills:debug` — structured troubleshooting for any platform symptom
- `/platform-skills:review` — production-readiness review of any manifest, Terraform, or workflow
- `/platform-skills:terraform` — full fmt/validate/tflint/security pipeline + blast radius review
- `/platform-skills:gitops` — Flux CD and Argo CD reconciliation troubleshooting
- `/platform-skills:linkerd` — Linkerd mTLS, injection, policy, and multi-cluster diagnostics
- `/platform-skills:linux` — Linux administration, DNS, load balancing, VPC/VNet, and connectivity troubleshooting
- `/platform-skills:product` — product thinking, friction audits, DevEx, RFC/ADR, incident updates, post-mortems
- `/platform-skills:compliance` — SOC 2 gap analysis, control implementation, evidence collection, and Checkov remediation for Terraform
- `/platform-skills:helmcheck` — Helm chart scaffolding, structural review, and security audit with full lint/validation pipeline
- `/platform-skills:mcp` — MCP server/client scaffolding, protocol review, and integration debugging
- `/platform-skills:observability` — instrument services, build dashboards, write alerts, run load tests, plan capacity
- `/platform-skills:document` — generate docstrings, OpenAPI specs, documentation sites, and getting started guides
- `/platform-skills:datadog` — Datadog Agent setup, APM instrumentation, monitors, dashboards, SLOs, and debugging
- `/platform-skills:dynatrace` — OneAgent deployment, instrumentation, anomaly detection, SLOs, and debugging
- `/platform-skills:commit` — analyze diff, generate conventional commit message, stage files atomically, validate message
- `/platform-skills:opa` — generate Rego policies, write unit tests, run fmt/regal/verify pipeline, explain or debug policies
- `/platform-skills:kyverno` — generate, test, audit, debug, or migrate Kyverno CEL-based admission policies
- `/platform-skills:pr-review` — comprehensive PR review: cost, drift, ownership, compliance, upgrade, rollback
- `/platform-skills:triage` — triage a PR comment (bot or human): classify as ACTIONABLE_FIX / INFORMATIONAL / NOT_APPLICABLE, produce the exact fix if needed, and write the thread reply
- `/platform-skills:keda` — design, generate, debug, or review KEDA ScaledObject/ScaledJob autoscaling
- `/platform-skills:self-improve` — bootstrap `.learnings/` directory, log learnings/errors/feature requests, review recurring patterns, and promote entries to project memory
- `/platform-skills:supply-chain` — sign images, generate and attest SBOMs, run CVE severity gates, enforce image signatures in Kubernetes, and generate SLSA Level 2 provenance
- `/platform-skills:runtime-security` — deploy Falco with eBPF, write custom rules, route alerts, debug why a rule is not firing, and bridge Falco signals to Kyverno admission enforcement
- `/platform-skills:chaos` — install Litmus Chaos or Chaos Mesh, generate fault experiments, schedule recurring chaos, run structured GameDay, debug stuck experiments, report results
- `/platform-skills:dora` — instrument DORA metrics in GitHub Actions, generate Grafana dashboards, benchmark against performance bands, debug missing metric data

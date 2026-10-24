# Platform Skills

Production-grade platform engineering workflows for Claude Code: Kubernetes, GitOps with Flux CD and Argo CD, Terraform, GitHub Actions, AWS, Azure, OpenShift, secrets, policy as code, supply chain security, observability and incident practice. Every answer includes the blast radius, validation steps and a rollback plan.

## How it works

The plugin is skills, reference guides and examples. It has no hooks and no MCP servers, starts no background process and changes no Claude Code setting.

- **Router skill.** `platform-skills` activates when you work on platform infrastructure and sends Claude to the matching reference guide.
- **Slash commands.** Each command below is an interactive workflow: it asks a few questions, then diagnoses, generates or reviews.
- **Subagent.** `platform-bulk-reader` answers one read-only discovery question across many files, with the Read, Grep and Glob tools only.
- **Bundled files.** `references/` holds the guides the skills read, `examples/` the manifests, Terraform, workflows and scripts they adapt, and `assets/` the templates that `setup-agents` renders.

## What it runs, sends and fetches

- **Commands go through Claude Code's Bash tool**, so your permission settings apply to each one. Skills run the CLIs you already use, such as `kubectl`, `helm`, `flux`, `terraform`, `gh`, `aws` and `az`, against the context, profile or account you have selected.
- **`triage` runs a bundled helper**, `examples/triage/scripts/triage_helper.py`, with your `python3`.
- **Authentication uses the service you select.** CLIs use their configured profile or session; tools such as `zizmor` and `trivy` can use a service-specific variable you exported. Direct API examples use a key you supplied for that service. Skills must not extract Claude Code login credentials, read raw credential caches, or print secret values into the conversation. AWS profile checks use configuration metadata and STS; TTL is `unknown` unless you share an expiration timestamp without credentials.
- **Pull request comments are posted only when you run the workflow.** `triage` and `pr-review` reply and resolve review threads with `gh`, as the account you are signed in with.
- **Installs happen only on request.** Workflows that install a tool, such as the Kubescape CLI or a Helm chart, do it when you ask, through commands you approve. Nothing is downloaded when the plugin loads.

## Configuration

All settings are optional and none is secret: the GitOps engine (`flux`, `argocd` or `none`), the primary cloud, your AWS CLI profile naming pattern, the tag keys every resource must carry, and your GitHub organisation. Skills use them to choose defaults for examples and printed commands.

Configure service authentication in the selected CLI or tool before using its workflow. Do not put a secret in these settings: Claude Code substitutes only non-sensitive `userConfig` values into skill text; sensitive values are available to configured server and hook processes instead. See the [plugin configuration reference](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value). This plugin has no server or hook process to receive a sensitive option.

## Commands

- `/platform-skills:ai-governance`: Generate and enforce policy gates for AI coding agents (Copilot, Claude Code) — real-time session hooks that deny protected-path edits and dangerous commands, plus a merge-time backstop for anything that bypasses them.
- `/platform-skills:awesome-docs`: Generate, convert, and maintain animated GitHub-safe Markdown documents with animated SVG diagrams.
- `/platform-skills:aws`: Structured guidance for AWS CloudFront distributions, WAF web ACLs, Lambda@Edge, CloudFront Functions, Firewall Manager multi-account enforcement, and IAM/IRSA patterns.
- `/platform-skills:aws-profile`: Manage AWS profiles for MCP servers — discover SSO, Granted and role-chain profiles, check authentication with STS, switch configured profiles, and scan AWS Organization accounts.
- `/platform-skills:azure`: Azure identity (Workload Identity, OIDC, Entra ID), resource tagging, AKS platform patterns, RBAC scoping, and production-readiness review — with Terraform generation.
- `/platform-skills:backup-dr`: Back up and restore Kubernetes workloads with Velero, and prove recovery works.
- `/platform-skills:chaos`: Design, run, and debug Chaos Engineering experiments on Kubernetes using Litmus Chaos v3 and Chaos Mesh v2.
- `/platform-skills:checkov`: Bootstrap Checkov on a developer laptop, run static or plan-level Terraform security scanning for AWS/Azure/GCP/EKS, resolve private GitHub modules with a GITHUB_PAT you export, generate pre-commit hooks, produce multi-format output (cli/json/sarif/junit), and fix violations with AI-generated patches.
- `/platform-skills:cluster-upgrade`: Plan, run and roll back a Kubernetes minor-version upgrade, EKS first.
- `/platform-skills:commit`: Analyze git diffs or staged changes and generate conventional commit messages that explain WHY a change was made.
- `/platform-skills:compliance`: SOC 2 compliance for Terraform — gap analysis, control implementation, evidence collection, and remediation guidance mapped to SOC 2 Trust Services Criteria.
- `/platform-skills:composite-actions`: Generate, review, secure, and test composite GitHub Actions following best practices — full repo scaffold, interview-driven generation, PR creation on existing repos, SHA pinning, secrets-as-inputs, job summaries, and actionlint validation.
- `/platform-skills:datadog`: Set up and troubleshoot Datadog — Agent deployment on Kubernetes, APM instrumentation, Log Management, Monitors, Dashboards, SLOs, Synthetic tests, and live incident investigation using the Datadog MCP server.
- `/platform-skills:debug`: Structured platform troubleshooting — classifies the problem layer, collects evidence, forms a root-cause hypothesis, and proposes a fix with validation and rollback steps.
- `/platform-skills:document`: Generate, format, and validate code documentation — docstrings, JSDoc, OpenAPI/Swagger specs, documentation sites, and developer guides.
- `/platform-skills:dora`: Measure, benchmark, instrument, and debug DORA metrics (Deployment Frequency, Lead Time for Changes, Change Failure Rate, MTTR) for production engineering teams.
- `/platform-skills:dynatrace`: Deploy and configure Dynatrace — OneAgent Kubernetes Operator, code-level instrumentation, Log Monitoring, custom metrics, SLOs, Dashboards, anomaly detection, Davis AI, and live incident investigation using the Dynatrace MCP server.
- `/platform-skills:finops`: Cost visibility and tag governance for platform changes.
- `/platform-skills:fluxcd`: FluxCD entry point — routes to the right workflow based on what you need.
- `/platform-skills:gateway-api`: Migrate from the retired ingress-nginx controller to Kubernetes Gateway API, and design, debug, and review Gateway API ingress.
- `/platform-skills:github-actions`: Design, review, secure, and debug GitHub Actions workflows — reusable workflows, OIDC federation, SHA pinning, token scoping, promotion orchestration, and CI failure diagnosis.
- `/platform-skills:gitops`: Flux CD and Argo CD — two modes.
- `/platform-skills:helmchart`: Scaffold, lint, review, security-audit, test, and upgrade-verify Helm charts.
- `/platform-skills:karpenter`: Design, install, debug, review, plan capacity, audit scaling history, migrate from Cluster Autoscaler, and upgrade Karpenter v1.x on EKS.
- `/platform-skills:keda`: Design, debug, and review KEDA ScaledObject/ScaledJob autoscaling.
- `/platform-skills:kingfisher`: Find, live-validate, map the blast radius of, and revoke leaked secrets with Kingfisher (MongoDB) — across a local repo, Git history, a GitHub/GitLab/Bitbucket org, S3/GCS, Docker images, Slack, Jira, Confluence, Teams, or Postman.
- `/platform-skills:kubernetes`: Cluster baseline scaffolding, RBAC diagnosis and generation, workload hardening, and structured pod/scheduling debug for plain Kubernetes across all distributions.
- `/platform-skills:kubescape`: Check Kubernetes manifests, Helm charts, Kustomize overlays and live clusters against NSA-CISA, MITRE ATT&CK, CIS (EKS, AKS, GKE, vanilla) and SOC2 with the Kubescape CLI.
- `/platform-skills:kubescape-operator`: Install, tune and troubleshoot the Kubescape operator for continuous in-cluster security — posture scans on every change, vulnerabilities filtered to packages that actually load (relevancy), eBPF runtime threat detection against learned container profiles, NetworkPolicies generated from observed traffic, SecurityException resources with an expiry, and Prometheus metrics and alerts.
- `/platform-skills:kyverno`: Generate, test, audit, debug, and migrate Kyverno policies using the new CEL-based policy types (ValidatingPolicy, MutatingPolicy, GeneratingPolicy, ImageValidatingPolicy — all apiVersion policies.kyverno.io/v1).
- `/platform-skills:linkerd`: Linkerd-specific diagnostics — mTLS verification, proxy injection issues, authorization policy debugging, traffic management, and multi-cluster connectivity problems.
- `/platform-skills:linux`: Linux administration and networking diagnostics — DNS, load balancing, VPCs, kernel tuning, and connectivity troubleshooting.
- `/platform-skills:mcp`: MCP server and client development — scaffold, implement tools/resources/prompts, validate schemas, debug protocol compliance, and deploy with auth and rate limiting.
- `/platform-skills:observability`: Instrument services with structured logging, Prometheus metrics, and OpenTelemetry tracing.
- `/platform-skills:opa`: Generate, test, validate, explain, and debug OPA (Open Policy Agent) Rego policies and Conftest configurations.
- `/platform-skills:openshift`: OpenShift SCC diagnosis and hardening, Route TLS patterns, OpenShift GitOps app delivery, and cluster upgrade validation.
- `/platform-skills:pr-review`: Comprehensive PR review across six dimensions — cost impact, environment drift, ownership gaps, SOC 2 compliance, deprecated API / version hygiene, and rollback feasibility.
- `/platform-skills:preflight`: Production-readiness preflight check for a directory, repo, or single file.
- `/platform-skills:product`: Apply product thinking to platform work — DevEx audits, friction analysis, RFC/ADR drafting, incident communication, post-mortems, capacity planning, cost optimisation, and platform health review.
- `/platform-skills:progressive-delivery`: Canary releases with automatic promotion and rollback using Flagger on Flux.
- `/platform-skills:renovate`: Generate renovate.json covering all dependency file types used in a repo, emit a GitHub Actions workflow that validates renovate.json on every PR, or generate a pre-commit hook for local validation.
- `/platform-skills:runtime-security`: Detect and respond to in-container threats at the syscall level using Falco (eBPF-based, CNCF, open-source, no license cost).
- `/platform-skills:secrets`: Secrets strategy, External Secrets Operator scaffolding, Sealed Secrets seal/rotate/backup, rotation runbooks, and Kubernetes-side secrets audit.
- `/platform-skills:self-improve`: Bootstrap and operate a self-improving agent workspace.
- `/platform-skills:setup-agents`: Scaffold a multi-agent AI setup for any repo.
- `/platform-skills:supply-chain`: Secure the software supply chain from source to running container.
- `/platform-skills:terraform`: Runs through the full Terraform validation pipeline — fmt, validate, tflint, security scan — and reviews a module or plan for blast radius, IAM risk, and state impact.
- `/platform-skills:token-optimizer`: Route broad repository discovery to a cheaper worker model using each client's native subagents, keeping the main agent for decisions and targeted verification.
- `/platform-skills:triage`: Triages a PR comment — from a bot (Copilot, CI) or a human reviewer.
- `/platform-skills:trivy`: Scan container images, filesystems, git repos, and existing SBOMs for CVEs, secrets, and license violations using Trivy.
- `/platform-skills:zizmor`: Audit GitHub Actions workflows, composite actions, Dependabot configs, and pre-commit configs for security findings using zizmor — template injection, credential persistence, unpinned uses, over-broad permissions, impostor commits.

## Source and license

Source, issues and release notes are at https://github.com/nitinjain999/platform-skills. The plugin is licensed under Apache-2.0; see `LICENSE` and `NOTICE`.

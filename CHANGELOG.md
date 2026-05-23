# Changelog

All notable changes to Platform Skills will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

#### Self-Improve: global path resolution for cross-project learnings

- `commands/self-improve.md` — added `## Path Resolution` preamble that all modes evaluate before acting: detects global setup (`~/.claude/.learnings/` exists), project setup (`.learnings/` in `$PWD`), or auto-creates global on first use; all path references updated to use `LEARNINGS_BASE`
- `commands/self-improve.md` — `init` mode now asks **global vs project-local** before creating any directories; step 4 skips `.gitignore` check for global setup; step 5 targets the correct `settings.json` (`~/.claude/` for global, `.claude/` for project) and enforces absolute paths in the PostToolUse hook command
- `commands/self-improve.md` — `log` confirm message now shows resolved `$LEARNINGS_BASE` path instead of hardcoded `.learnings/`
- `commands/self-improve.md` — `resume`, `review`, `promote`, `state`, WAL Protocol, Working Buffer, SESSION-STATE, and Daily Notes proactive protocols updated to use `$LEARNINGS_BASE`
- `references/agent-self-improve.md` — new **Global vs project scope** section under Directory layout: scope comparison table, auto-detection order, promotion-targets-stay-local rule, working PostToolUse hook JSON example with absolute paths
- `examples/agent-self-improve/HOW_IT_WORKS.md` — updated `init` description to mention global vs project choice; corrected "What This Skill Cannot Do" section which previously stated learnings cannot persist across projects
- `examples/agent-self-improve/README.md` — updated setup instructions to reflect global scope option and hook wiring steps
- `examples/agent-self-improve/scripts/session-end.sh` — Stop hook script: drains `.pending-errors.log` into ERR entries on every session close, saves daily notes, auto-logs PENDING WAL as ERR, clears session marker, increments session counter with review reminder every 5 sessions, nudges if no LRN logged today
- `examples/agent-self-improve/scripts/session-start-reminder.sh` — PreToolUse hook script: marker-based session detection fires once per session; prints memory-load banner with active task and pending error count; silent on all subsequent tool calls
- `examples/agent-self-improve/global-claude.md` — template for `~/.claude/CLAUDE.md`: temporary path override table, session-start instruction, in-session logging rules (`log LRN/ERR/FEAT at moment of discovery`), `VFM_THRESHOLD=60`, Agent Rules section
- `examples/agent-self-improve/settings.json.example` — all 3 hooks wired: Stop (`session-end.sh`), PreToolUse (`session-start-reminder.sh`), PostToolUse (inline error capture to `.pending-errors.log`)

## [1.22.0] - 2026-05-22

### Added

#### AWS CloudFront + WAF + Lambda@Edge (Domains 33–34)

- `references/aws-cloudfront.md` — comprehensive reference covering: distribution anatomy, OAC (Origin Access Control replaces legacy OAI), cache policies, origin request policies, security headers (`aws_cloudfront_response_headers_policy` with HSTS preload + CSP + X-Frame + XSS), WAF integration (CLOUDFRONT scope requires us-east-1 — documented as the most common footgun), Lambda@Edge (all 4 event types with memory/timeout/body-access table), CloudFront Functions vs Lambda@Edge decision matrix (~6× cost difference), standard logging v2 + real-time logging + Athena partitioning, multi-account patterns (shared CDN account with cross-account OAC, per-account distributions + FMS enforcement), Organizations SCP, and production readiness checklist
- `references/aws-waf.md` — comprehensive reference covering: scope section (CLOUDFRONT vs REGIONAL, prominent footgun callout), web ACL anatomy, full managed rule groups table (14 groups, free vs paid), rate-based rules with aggregation keys (IP, forwarded IP, HTTP header, query string, custom key combinations), custom rules (IP sets, geo match, regex, label matching), CAPTCHA/Challenge actions, WAF logging (CW log group must start with `aws-waf-logs-`), testing workflow (Count → Block), multi-account FMS (prerequisites, policy anatomy, FIRST/MIDDLE/LAST rule group ownership model, auto-remediation, compliance dashboard, cross-account central logging), and Shield Advanced integration
- `commands/aws.md` — slash command `/platform-skills:aws` with six modes: `cloudfront` (distribution design, OAC, caching, security headers), `waf` (scope, managed rules, rate limiting, logging), `lambda-edge` (event type selection, constraints, deployment), `multi-account` (FMS policy design, OU targeting, audit mode), `review` (production-readiness checklist for CloudFront + WAF Terraform), `terraform` (module structure, provider aliases, validation blocks, best practices)
- `examples/aws/cloudfront/` — production-ready Terraform module:
  - `versions.tf` — provider constraints (`aws >= 5.0.0`, `archive ~> 2.4`), `us_east_1` alias, `required_version = ">= 1.7.0"`
  - `variables.tf` — 15 variables with `validation{}` blocks for `price_class`, `geo_restriction_type`, and `name` (regex + length)
  - `locals.tf` — origin IDs, `use_custom_domain`, `viewer_certificate`, `default_origin_id`, `use_alb` derived values
  - `main.tf` — S3 bucket (versioning + SSE-KMS + public access block), OAC with `cloudfront.amazonaws.com` service principal + `AWS:SourceArn` condition, response headers policy, CloudFront Function, distribution with dynamic blocks for ALB origin + custom header enforcement, Lambda@Edge association via `qualified_arn`, geo restriction, standard logging v2
  - `outputs.tf` — `distribution_id/arn/domain_name/hosted_zone_id`, `origin_bucket_name/arn`, `oac_id`
  - `lambda-edge/main.tf` — Lambda@Edge: `publish = true`, `provider = aws.us_east_1`, dual trust policy (`lambda.amazonaws.com` + `edgelambda.amazonaws.com`), pre-created CloudWatch log group, `qualified_arn` output (with explicit note: do not use `.arn` which resolves to `$LATEST`)
  - `lambda-edge/functions/viewer-request.js` — auth check (missing Bearer → 401), method restriction on `/api/`, A/B routing by cookie (20% to `/v2/`)
  - `functions/url-rewrite.js` — CloudFront Functions JS 2.0: trailing slash → index.html, SPA deep-link rewrite, clean URL rewrite, path traversal blocking
- `examples/aws/waf/` — production-ready Terraform module:
  - `versions.tf` — `us_east_1` alias with comment explaining CLOUDFRONT scope requirement
  - `variables.tf` — 9 variables with validation: `default_action` (allow/block), `rate_limit` (0 or 100–2B), `cloudwatch_log_retention_days` (validates against CloudWatch valid values list)
  - `main.tf` — WebACL with: IP allowlist (priority 0, dynamic), IP reputation (5), AnonymousIpList (6), CRS with `SizeRestrictions_BODY` override to Count (10), KnownBadInputs (11), geo block (20, dynamic), rate limit with custom 429 + `Retry-After` header (30, dynamic), Bot Control with inspection level (40, dynamic), ATP with login path config (50, dynamic); logging config with field redaction (authorization, cookie headers) + filter to keep only BLOCK/COUNT actions
  - `outputs.tf` — `web_acl_arn/id`, `web_acl_capacity` (WCU consumption), `log_group_name/arn`
- `examples/aws/firewall-manager/main.tf` — self-contained FMS module: `aws_fms_admin_account`, `aws_fms_policy` for `AWS::CloudFront::Distribution` with OU include + excluded accounts, `preProcessRuleGroups` (IP reputation + CRS + KnownBadInputs at priorities 5/10/11), `overrideCustomerWebACLAssociation = false` to allow app-team local rules, `remediation_enabled` defaulting to `false` (audit mode) with explanation
- `examples/aws/README.md` — updated index with cloudfront, waf, firewall-manager examples; quick-start snippets for single-account (WAF → CloudFront) and multi-account (FMS) patterns; key patterns summary and checklist

## [1.21.0] - 2026-05-21

### Added

#### Awesome Docs (Domain 27)

- `references/awesome-docs.md` — comprehensive reference covering: SVG Pattern A (architecture flow — `offset-path` animated dots, glow animations, arrowhead markers, legend), SVG Pattern B (decision/lifecycle loop — 3-state CSS cycling, status bar), SVG Pattern C (field explainer carousel — timing formula `slot = T/N`, `N × slot = T` invariant, tooltip structure), SVG Pattern D (timeline phases — bar math `y = bottom - (N/max)*height`), GitHub SVG animation constraints table (allowed vs blocked), theme system (`github-dark`, `docs-light`, `custom`), multi-platform export rules (GitHub SVG, Confluence/Notion HTML, PNG manual steps), quality checklist, and curated external references (MDN, GitHub Docs, Shields.io, SVGO, Primer CSS)
- `commands/awesome-docs.md` — slash command `/platform-skills:awesome-docs` with seven modes: `generate` (doc-type-aware guided interview with outline/preview step → full animated doc with incremental SVG confirmation for any doc type — readme, architecture-guide, runbook, tutorial, api-reference, how-it-works, rfc, post-mortem, or custom), `convert` (8-type doc classification; batch mode for directory input; inject SVGs into existing Markdown with conflict detection), `update` (revise a single diagram), `diff` (detect stale diagrams; `--base <branch|tag|SHA>` flag, defaults to HEAD), `audit` (quality punch list), `preview` (cross-platform local browser preview via `python3 -m http.server`), `export` (GitHub SVG default; Confluence/Notion animated HTML; PNG manual step)
- `references/awesome-docs.md` extended: SVG Pattern E (sequence diagram — actor lifelines, message arrows, CSS step animation, activation boxes), SVG Pattern F (state machine — state nodes, transition arrows, current-state cycling ring), field carousel multi-format syntax colors (YAML, HCL/Terraform, JSON, TOML)
- `examples/awesome-docs/arch-flow.svg` — reusable architecture flow SVG template (github-dark, 3 boxes, 2 animated dot paths)
- `examples/awesome-docs/lifecycle-loop.svg` — reusable lifecycle loop SVG template (3-state CSS, diamond gate, status bar)
- `examples/awesome-docs/field-carousel.svg` — reusable field carousel SVG template (4 fields, 8s cycle, `N × slot = T` timing)
- `examples/awesome-docs/timeline-phases.svg` — reusable timeline phases SVG template (3 phases, replica chart with correct bar math)
- `examples/awesome-docs/sequence-diagram.svg` — auth token request flow demo (4-step CSS-sequenced messages with activation boxes)
- `examples/awesome-docs/state-machine.svg` — deployment lifecycle demo (Pending → Deploying → Healthy, error/retry paths, current-state cycling ring)
- `examples/awesome-docs/docs-audit-workflow.yml` — GitHub Actions workflow: SVG size check, caption check, broken-ref check, external-href check, stale-diagram diff report, PR comment

## [1.20.0] - 2026-05-20

### Added

#### Datadog Labs + LLM Observability

- `references/datadog.md` — two new sections: **pup CLI** (install, config, common operations, scripting post-deploy gates, troubleshooting table) and **Datadog Labs Claude Skills** (dd-pup, dd-apm, dd-logs, dd-monitors, dd-docs — install commands, capability table, when-to-use decision matrix)
- `references/llm-observability.md` — new reference covering: LLMObs vs traditional APM decision matrix, Python instrumentation (`@llm`, `@workflow`, `@retrieval` decorators, `LLMObs.annotate()`), Node.js instrumentation (`llmobs.trace()` callback, `llmobs.annotate()`), environment variables, eval bootstrap workflow, `submit_evaluation()` pattern, pup-based CI quality gate, trace RCA with `dd-llmo-eval-trace-rca`, experiment analysis with `dd-llmo-experiment-analyzer`, manual pup fallback commands, troubleshooting table, and security guidance
- `commands/datadog.md` — two new modes: **pup** (log search, metric query, monitor management, post-deploy gate generation) and **llmo** (instrument/evaluate/rca/experiment classification flow)
- `examples/datadog/llm-observability/llmobs-python.py` — complete Python LLMObs example with `@llm`, `@workflow`, `@retrieval` decorators and faithfulness evaluation
- `examples/datadog/llm-observability/llmobs-nodejs.js` — complete Node.js LLMObs example with `llmobs.trace()` and evaluation submission
- `examples/datadog/llm-observability/evaluator-bootstrap.py` — faithfulness and quality evaluator stubs with LLM-as-judge pattern

## [1.19.0] - 2026-05-20

### Added

#### Chaos Engineering (Domain 27)

- `references/chaos.md` — comprehensive reference covering: decision matrix (Litmus Chaos v3 vs Chaos Mesh v2), fault taxonomy (pod/node/network/stress), steady-state hypothesis pattern (httpProbe and promProbe), blast radius scoping rules, ChaosEngine and NetworkChaos YAML, GitOps integration via ChaosSchedule, rollback semantics, DORA feedback loop, and troubleshooting for stuck experiments and RBAC gaps
- `commands/chaos.md` — slash command `/platform-skills:chaos` with six modes: `install`, `experiment`, `schedule`, `gameday`, `debug`, `report`
- `examples/chaos/` — eight working examples and one validator:
  - `litmus-install-values.yaml` — Helm values for Litmus Chaos v3
  - `chaos-mesh-install-values.yaml` — Helm values for Chaos Mesh v2
  - `pod-delete-experiment.yaml` — Litmus ChaosEngine targeting a Deployment with HTTP probe
  - `network-loss-experiment.yaml` — Chaos Mesh NetworkChaos with 20% packet loss
  - `cpu-stress-experiment.yaml` — Litmus pod-cpu-hog with Prometheus steady-state probe
  - `chaos-schedule.yaml` — weekly pod-delete ChaosSchedule (staging only)
  - `gameday-runbook.md` — structured GameDay template (steady-state → blast radius → inject → observe → verdict → DORA impact)
  - `chaos-validate.sh` — domain validator

#### DORA Metrics (Domain 28)

- `references/dora.md` — comprehensive reference covering: the four DORA metrics with exact definitions, 2023 performance bands (Elite/High/Medium/Low), GitHub Actions + Prometheus Pushgateway open-source instrumentation pattern, all four Prometheus recording rules, PagerDuty and OpsGenie incident webhook integration for MTTR, SaaS decision matrix (Sleuth, LinearB, Cortex, open-source), five anti-pattern detections (commits vs deploys, all alerts vs customer incidents, partial outages, staging vs production, PR open vs first commit), chaos engineering cross-reference for high change failure rate, and agent platform rules
- `commands/dora.md` — slash command `/platform-skills:dora` with four modes: `instrument`, `dashboard`, `benchmark`, `debug`
- `examples/dora/` — five working examples, one validator, and an AMP variant:
  - `deployment-event-step.yaml` — GitHub Actions step pushing deploy timestamp and lead time to Pushgateway
  - `incident-webhook-handler.yaml` — full GitHub Actions workflow triggered by PagerDuty/OpsGenie webhook for MTTR tracking
  - `prometheus-recording-rules.yaml` — all four DORA Prometheus recording rules
  - `grafana-dashboard.json` — Grafana dashboard with four DORA panels and Elite/High/Medium/Low threshold bands
  - `dora-validate.sh` — domain validator
  - `amp-variant/` — Amazon Managed Prometheus variant: `amp-workspace.tf` (Terraform module provisioning AMP workspace + recording rules via `terraform-aws-modules/managed-service-prometheus/aws`), `pushgateway-helm-values.yaml`, `prometheus-agent-values.yaml` (SigV4/IRSA remote_write), `amp-recording-rules-deploy.sh` (AWS CLI fallback), `grafana-amp-datasource.yaml`, `grafana-amg-datasource.json`

## [1.18.0] - 2026-05-20

### Added

#### Self-Improvement: SESSION-STATE, Daily Notes, VBR, Context Threshold

Four improvements to the proactive agent pattern in Domain 24:

- **SESSION-STATE.md** — always-on capture file (`memory/SESSION-STATE.md`) for corrections, preferences, decisions, and proper nouns. Written before responding when any of these occur (not only before destructive ops). Second read in compaction recovery after working-buffer.
- **Daily Notes** — rolling per-day log (`memory/YYYY-MM-DD.md`) of notable exchanges, discoveries, completed tasks, and errors. Survives compaction as a searchable history. Third read in compaction recovery.
- **Context threshold trigger** — working buffer is written proactively at ~60% context, not only at task boundaries. Prevents silent context loss mid-task.
- **Verify Before Reporting (VBR)** — explicit protocol: run the validation command and read the changed file before reporting done. Text change ≠ behavior change; test actual outcomes.
- Updated compaction recovery order in `commands/self-improve.md` `resume` mode: working-buffer → SESSION-STATE → daily notes → resource verification. "Never ask where were we?" rule added.
- New `state` mode in `commands/self-improve.md` — explicit slash command for capturing session state entries
- Example scaffold updated: `memory/SESSION-STATE.md` and `memory/YYYY-MM-DD.md` templates added to `examples/agent-self-improve/memory/`
- `.gitignore` recommendation updated: gitignore `memory/` entirely (daily notes grow fast)

## [1.17.0] - 2026-05-20

### Added

- Closing `## Closing — Log learnings` section added to `commands/triage.md`, `commands/supply-chain.md`, and `commands/runtime-security.md` — each workflow now ends with an explicit step to log errors and learnings via `/platform-skills:self-improve log` immediately after completing work, preventing context loss across sessions
- PostToolUse hook in `.claude/settings.json` (local, not committed) prompts incremental learning capture after every `git commit`

### Changed

- Promoted 10 learnings from v1.16.0 session to `CLAUDE.md` and reference guides (`references/supply-chain.md`, `references/runtime-security.md`, `references/kyverno.md`) as permanent agent rules

## [1.16.0] - 2026-05-20

### Added

#### Supply Chain Security — Domain 25

New Domain 25: `Supply Chain Security` — secure the build pipeline and image lifecycle.

- `references/supply-chain.md` — comprehensive reference covering:
  - Cosign keyless signing (Sigstore/Rekor, OIDC-based, no key management)
  - SBOM generation and OCI attestation with Syft
  - CVE scanning with Trivy and Grype, severity gate strategy
  - SLSA Level 2 vs Level 3 provenance requirements
  - Kyverno `ImageValidatingPolicy` for admission enforcement
  - Gap classification table and recommended rollout order
- `commands/supply-chain.md` — slash command `/platform-skills:supply-chain` with six modes: `audit`, `sign`, `sbom`, `scan`, `enforce`, `slsa`
- `examples/supply-chain/` — five working GitHub Actions workflows and one Kyverno policy:
  - `sign-and-push.yaml` — build → Cosign keyless sign → push
  - `sbom-attest.yaml` — Syft SBOM generation and Cosign attestation
  - `trivy-gate.yaml` — Trivy scan with CRITICAL+HIGH severity gate and GitHub Security tab upload
  - `kyverno-verify-image.yaml` — `ImageValidatingPolicy` blocking unsigned images (Audit mode)
  - `slsa-provenance.yaml` — SLSA Level 2 provenance via `slsa-github-generator`
  - `supply-chain-validate.sh` — domain validator

#### Runtime Security — Domain 26

New Domain 26: `Runtime Security` — detect in-container threats with Falco.

- `references/runtime-security.md` — comprehensive reference covering:
  - Falco architecture: eBPF probe, rules engine, alert output
  - Driver comparison: `modern_ebpf` vs `ebpf` vs `kmod` (kmod never on managed K8s)
  - EKS and GKE installation with eBPF (Bottlerocket, COS, Fargate caveats)
  - Built-in ruleset overview and noise reduction approach
  - Custom rule syntax: condition fields, lists, macros
  - Falcosidekick alert routing: Slack, webhook, SNS, PagerDuty
  - Falco → Kyverno bridge pattern for blocking flagged workload re-admission
  - Resource sizing and CPU limit guidance (do not set CPU limits)
- `commands/runtime-security.md` — slash command `/platform-skills:runtime-security` with five modes: `install`, `rules`, `alerts`, `debug`, `harden`
- `examples/runtime-security/` — four working Helm values and one Kyverno policy:
  - `falco-values.yaml` — Falco Helm values with eBPF driver and resource limits
  - `falco-custom-rules.yaml` — shell-in-container, privilege escalation, unexpected outbound
  - `falcosidekick-values.yaml` — Slack + webhook routing with deduplication
  - `falco-kyverno-bridge.yaml` — `ValidatingPolicy` blocking Falco-flagged workload re-admission
  - `runtime-security-validate.sh` — domain validator

## [1.15.0] - 2026-05-20

### Added

#### Agent Self-Improvement — Domain 24

New Domain 24: `Agent Self-Improvement` — bootstrap and operate self-improving, proactive agent workspaces.

- `references/agent-self-improve.md` — comprehensive reference guide covering:
  - `.learnings/` directory layout and entry lifecycle (LRN/ERR/FEAT)
  - WAL Protocol (append-only log, write-ahead before action)
  - Working Buffer pattern for mid-session state persistence
  - VFM Scoring (Value-Frequency Matrix) for evaluating unsolicited proactive actions
  - ADL Protocol (Action Decision Logic) for choosing between competing implementation approaches
  - Six Operating Pillars for proactive agent behavior
  - Heartbeat pattern for session continuity
  - Reverse Prompting to surface agent knowledge gaps
- `commands/self-improve.md` — slash command definition for `/platform-skills:self-improve` with five modes: `init`, `log`, `resume`, `review`, `promote`
- `examples/agent-self-improve/` — ready-to-copy workspace scaffold:
  - `README.md` — overview and copy commands
  - `.learnings/LEARNINGS.md` — positive learnings template
  - `.learnings/ERRORS.md` — error log template
  - `.learnings/FEATURE_REQUESTS.md` — feature request template
  - `memory/working-buffer.md` — WAL scratchpad template
- Updated `SKILL.md` (root and `skills/platform-skills/`) with Domain 24 entry, reference bullet, and `/platform-skills:self-improve` slash command
- Updated `README.md` with Domain 26 badge and domain table row
- Updated `COMMANDS.md` with ToC entry and full command reference section

## [1.14.0] - 2026-05-16

### Added

#### KEDA — Kubernetes Event-Driven Autoscaling

New Domain 23: `KEDA` — design, generate, debug, and review event-driven autoscaling with KEDA v2.14.

- `references/keda.md` — comprehensive reference guide covering:
  - KEDA vs HPA decision matrix (when to use each)
  - Architecture (operator, metrics adapter, webhook)
  - Helm installation with resource limits
  - `ScaledObject` spec: minReplicaCount, maxReplicaCount, pollingInterval, cooldownPeriod, advanced HPA behavior overrides, scale-to-zero with cold-start guidance
  - `ScaledJob` spec: batch processing per message with scaling strategies (accurate/default/custom)
  - `TriggerAuthentication` and `ClusterTriggerAuthentication`: Kubernetes Secret reference, IRSA (AWS), Azure Workload Identity, GCP Workload Identity
  - Scalers with full metadata reference: Prometheus, AWS SQS, Apache Kafka (SASL/TLS), Redis List, Cron, Azure Service Bus, HTTP Add-on
  - Scaling lifecycle and tuning table (pollingInterval/cooldownPeriod by scenario)
  - Security patterns: least-privilege IAM per scaler, namespace-scoped vs cluster-scoped auth, RBAC for ScaledObject management
  - GitOps integration: Flux Kustomization with health checks, Argo CD ordering, ExternalSecret pairing
  - Troubleshooting: 7 common failure patterns with diagnostic commands and exact fixes
  - Observability: KEDA Prometheus metrics, Grafana dashboard import
  - Version compatibility matrix and upgrade checklist
- `/platform-skills:keda` (`commands/keda.md`) — four modes:
  - `generate` — write a production-ready ScaledObject or ScaledJob from a description
  - `debug` — diagnose scaling failures with a structured checklist
  - `review` — correctness, security, and operational safety review
  - `scale` — design the scaling strategy for a workload from requirements
- `examples/keda/` — four working examples:
  - `scaledobject-sqs.yaml` — SQS queue trigger with IRSA, scale-to-zero, HPA stabilization
  - `scaledobject-prometheus.yaml` — HTTP request rate trigger with Cron floor for business hours
  - `scaledobject-kafka.yaml` — Kafka consumer lag trigger with SASL/TLS auth
  - `scaledjob-sqs.yaml` — batch ScaledJob (one Job per SQS message) with security hardening

## [1.13.0] - 2026-05-16

### Added

#### Triage Command

New command `/platform-skills:triage` — triages any PR comment (from a bot, CI tool, or human reviewer) using the `gh` CLI directly inside Claude Code. No workflow or secrets required.

- `commands/triage.md` — full skill definition with two modes:
  - `<PR number> <comment ID>` — triage one specific comment
  - `--all <PR number>` — triage every unresolved thread on a PR in one pass
- Classifies each comment as `ACTIONABLE_FIX`, `INFORMATIONAL`, or `NOT_APPLICABLE`
- For `ACTIONABLE_FIX`: reads the referenced file, applies the minimal fix with the Edit tool, commits and pushes to the PR branch
- Posts a reply on the thread explaining the decision with classification-specific closing lines
- Resolves the thread via `gh api graphql` `resolveReviewThread` mutation
- Prints a summary table when running `--all` mode
- `examples/triage/` — 11 fully documented scenarios:
  - `actionable-fix/` — wildcard IAM (SOC 2 CC6.1), missing resource limits, deprecated `networking.k8s.io/v1beta1` API, wrong liveness probe path, hardcoded secret reference
  - `informational/` — replica count question, PDB follow-up suggestion, KMS rotation evidence request
  - `not-applicable/` — CI status bot message, already-fixed-in-later-commit, comment on file not in PR diff

#### Review Bot Comment Mode

Enhanced `/platform-skills:review` with structured output for automated PR comment workflows.

- `commands/review.md` — adds `--bot` flag and GitHub-flavoured markdown output format
- Defines `MERGE_READY / NEEDS_FIX / BLOCKED` result values based on finding severity
- Uses `<!-- platform-skills-review -->` HTML marker for idempotent comment updates on re-push
- Severity table with emoji labels (🔴 Critical, 🟡 Improvement, 🔵 Note) and file/line references

#### Wiki

- Full GitHub wiki published at https://github.com/nitinjain999/platform-skills/wiki
- 50 pages covering all 21 commands and 25 domains
- Navigation index, Quick Start, Installation, Editor Integrations, How It Works, Contributing
- One page per command with Claude Code slash syntax, Copilot Chat prompts, and what gets checked
- One page per domain with key patterns, code examples, and links to the full reference guide

## [1.12.0] - 2026-05-16

### Added

#### PR Review Domain

New Domain 21: `PR Review` — comprehensive pre-merge risk review across six dimensions. Each mode inspects the diff and current file state, reports findings with severity, and recommends concrete fixes.

- `references/pr-review.md` — cost impact (compute, storage, network spend delta with AWS pricing reference), environment drift detection (Kustomize overlay gaps, Helm values sibling mismatches, Terraform workspace drift, GitOps source drift, feature flag drift), ownership and governance (CODEOWNERS gaps, missing team labels, Terraform module README requirements, PR governance checklist), SOC 2 compliance mapping (CC6.1–CC8.1, A1.2 with Terraform patterns and `aws` CLI evidence collection commands), deprecated API / version hygiene (Kubernetes API removal timeline, Terraform provider constraint patterns, GitHub Actions SHA pinning, container digest pinning), rollback feasibility scoring (reversibility matrix: FULL/PARTIAL/MANUAL/NONE, blast radius: LOCAL/CLUSTER/PLATFORM/DATA, pre-merge requirements for high-risk changes, GitOps rollback patterns), and bot comment triage workflow with GH CLI commands for resolving threads
- `/platform-skills:pr-review` (`commands/pr-review.md`) — six modes: `cost` (spend delta with severity per resource), `drift` (environment alignment across overlays, values files, Terraform workspaces), `ownership` (CODEOWNERS, team labels, module README, PR governance), `compliance` (SOC 2 control impact with remediation and auditor evidence commands), `upgrade` (deprecated Kubernetes APIs, loose Terraform constraints, floating action versions, `:latest` images), `rollback` (reversibility and blast radius score per change with Rollback Risk Score: 🟢/🟡/🔴), `full` (all six modes with Merge Readiness Summary)

## [1.11.0] - 2026-05-16

### Added

#### Kyverno Domain

New Domain 20: `Kyverno` — write and maintain Kubernetes-native admission policies using the CEL-based types (`ValidatingPolicy`, `MutatingPolicy`, `GeneratingPolicy`, `ImageValidatingPolicy`) introduced in Kyverno v1.14–v1.15. Covers Audit→Deny promotion, PolicyExceptions, PolicyReport analysis, and migration from legacy `ClusterPolicy` or PodSecurityPolicy. All policies use `apiVersion: policies.kyverno.io/v1`.

- `references/kyverno.md` — all five new policy kinds with namespace-scoped variants, `matchConstraints`/`matchConditions` CEL filtering, `ValidatingPolicy` with `validations[].expression` and `messageExpression`, `MutatingPolicy` with `ApplyConfiguration` (`Object{...}`) and `JSONPatch` (`[JSONPatch{...}]`) patch types, container iteration with `.map()`/`.all()`, `mutateExisting`, `GeneratingPolicy` with `generator.Apply()` and `dyn()` inline resources, `ImageValidatingPolicy` with `verifyImageSignatures()`, Cosign keyless/key-based and Notary attestors, Audit→Deny promotion workflow with PolicyReport queries, PolicyException (`kyverno.io/v2`), kyverno-cli install and test manifest structure, PolicyReport export to CSV, GitHub Actions integration, three full annotated example policies, and a troubleshooting table covering 11 failure modes
- `/platform-skills:kyverno` (`commands/kyverno.md`) — five modes: `generate` (write CEL-based policy from description, always Audit-first), `test` (write kyverno-test.yaml with pass/fail/skip fixtures), `audit` (rank PolicyReport violations and produce Deny promotion plan), `debug` (diagnose webhook registration, matchConstraints/matchConditions gaps, background scan, CEL errors, PolicyException suppression), `migrate` (legacy ClusterPolicy→new-type translation table, PSP field mapping, Gatekeeper ConstraintTemplate translation)
- `examples/kyverno/` — two `ValidatingPolicy` examples (`require-team-labels.yaml`, `disallow-privileged-containers.yaml`), one `GeneratingPolicy` example (`generate-default-networkpolicy.yaml`), four test resource fixtures, and a `kyverno-test.yaml` that exercises pass and fail cases for each validate policy

## [1.10.0] - 2026-05-09

### Added

#### OPA / Conftest Domain

New Domain 19: `OPA / Conftest` — generate Rego policies, write unit tests, run the full validation pipeline (fmt → regal lint → conftest verify → integration test), explain existing policies in plain English, and debug why a rule is not firing.

- `references/opa.md` — Rego v1 syntax, METADATA blocks, rule types (deny/warn/violation), package namespacing, input shape analysis with `conftest parse`, policy examples (Terraform IAM, Kubernetes pod security), unit test patterns with input fixtures, full validation pipeline (conftest fmt, regal lint, conftest verify, integration test), GitHub Actions workflow, shared `data.*` allow-lists, and troubleshooting table
- `/platform-skills:opa` (`commands/opa.md`) — five modes: `generate` (write Rego from description with correct structure), `test` (write `_test.rego` unit tests with fixtures), `validate` (run fmt/regal/verify/integration pipeline), `explain` (translate policy to plain English), `debug` (diagnose namespace mismatch, wrong rule name, input shape issues)
- `examples/opa/conftest/` — working S3 encryption policy (`deny_unencrypted_s3.rego`), full unit test suite (`deny_unencrypted_s3_test.rego`), sample Terraform input, and `.regal/config.yaml`

## [1.9.0] - 2026-05-09

### Added

#### Conventional Commits Domain

New Domain 18: `Conventional Commits` — analyze git diffs or staged changes, generate commit messages that explain WHY a change was made, intelligently stage files for atomic commits, and validate messages against the Conventional Commits 1.0.0 specification.

- `references/conventional-commits.md` — message structure (subject/body/footer rules), type classification table with decision guidance, scope rules, breaking change patterns with examples, atomic commit strategy with `git add -p`, full examples for fix/feat/chore/breaking/revert, commitlint setup with scope allow-list, husky git hook configuration, GitHub Actions PR title lint workflow, semantic-release configuration with version bump rules, and a validation rules table
- `/platform-skills:commit` (`commands/commit.md`) — four modes: `analyze` (classify type/scope/breaking from diff), `generate` (produce full conventional commit message), `stage` (intelligently group and stage files for atomic commits), `validate` (check an existing message against the spec)
- `examples/conventional-commits/commitlint/` — commitlint config with scope allow-list, husky `commit-msg` hook, and `package.json` for installation

#### Datadog Domain

New Domain 16: `Datadog` — deploy and configure the Datadog Agent on Kubernetes, instrument services with APM and log correlation, and manage monitors, dashboards, SLOs, and synthetic tests as Terraform-managed resources.

- `references/datadog.md` — Agent Helm setup, APM instrumentation (Node.js/Python), Unified Service Tagging, Log Management with processing rules, Monitors (Terraform), Dashboards (Terraform), SLOs, Synthetic tests, and troubleshooting table
- `/platform-skills:datadog` (`commands/datadog.md`) — six modes: `setup`, `instrument`, `monitor`, `dashboard`, `slo`, `debug`
- `examples/datadog/terraform/monitors.tf` — Terraform monitors for error rate and latency, plus SLO resource

#### Dynatrace Domain

New Domain 17: `Dynatrace` — deploy OneAgent via the Kubernetes Operator with automatic injection, configure anomaly detection, ingest custom metrics, define SLOs, and manage dashboards and alerting profiles with the Dynatrace Terraform provider.

- `references/dynatrace.md` — Operator and DynaKube CR setup, Node.js/Python/Java SDK instrumentation, Log Monitoring, custom metrics via MINT API, SLOs, Terraform provider (anomaly detection, SLOs, alerting), Davis AI problem feeds, troubleshooting table, and token scopes
- `/platform-skills:dynatrace` (`commands/dynatrace.md`) — six modes: `setup`, `instrument`, `monitor`, `slo`, `dashboard`, `debug`
- `examples/dynatrace/operator/dynakube.yaml` — production DynaKube CR with cloudNativeFullStack injection and ActiveGate

## [1.8.0] - 2026-05-08

### Added

#### MCP Domain (Model Context Protocol)

New Domain 13: `MCP (Model Context Protocol)` — build, review, and debug MCP servers and clients covering TypeScript and Python SDKs, Zod/Pydantic schema validation, stdio/HTTP/SSE transports, protocol compliance, authentication, and rate limiting.

- `references/mcp.md` — protocol fundamentals, TypeScript SDK patterns, Python FastMCP patterns, schema design, error handling, testing with MCP Inspector, security, and deployment checklist
- `/platform-skills:mcp` (`commands/mcp.md`) — three modes: `create` (scaffold production-ready server), `review` (protocol compliance and security audit), `debug` (diagnose transport/protocol/schema/handler failures)
- `examples/mcp/docs-server/` — complete TypeScript MCP server with `search_docs` and `get_doc` tools and a `docs://index` resource

#### Observability Domain

New Domain 14: `Observability` — instrument services with structured logging, Prometheus metrics, and OpenTelemetry tracing; build Grafana dashboards, write alerting rules, run k6 load tests, and plan capacity.

- `references/observability.md` — Pino/structlog structured logging, prom-client/prometheus-client metrics, OpenTelemetry tracing, RED/USE method alerting rules, Grafana dashboard templates, k6 load testing, and capacity planning formulas
- `/platform-skills:observability` (`commands/observability.md`) — five modes: `instrument`, `dashboard`, `alert`, `loadtest`, `capacity`
- `examples/observability/prometheus-alerts/` — RED method Prometheus alerting rules for a production service

#### Documentation Domain

New Domain 15: `Documentation` — generate and validate inline docstrings (Google/NumPy/Sphinx/JSDoc), OpenAPI 3.1 specifications, documentation sites (MkDocs, TypeDoc), and developer getting started guides.

- `references/documentation.md` — Google/NumPy/Sphinx docstring styles, TypeScript JSDoc, OpenAPI 3.1 spec with shared components, FastAPI and NestJS auto-documentation, coverage measurement, MkDocs site setup, and guide structure
- `/platform-skills:document` (`commands/document.md`) — four modes: `docstrings`, `openapi`, `site`, `guide`
- `examples/documentation/openapi-spec/` — complete OpenAPI 3.1 Orders API with shared components, security schemes, and response definitions

## [1.7.0] - 2026-05-08

### Added

#### Helm Domain (Helmcheck)

New Domain 12: `Helm (Helmcheck)` — production-grade Helm chart development covering scaffolding, values design, template patterns, dependency management, security hardening, and the full lint/validation pipeline.

**Reference guide:**
- `references/helm.md` — complete template patterns, standard `_helpers.tpl`, security-hardened Deployment baseline, conditional resource templates (Ingress, HPA, PDB, NetworkPolicy), `values.yaml` design principles, `values.schema.json` type safety, dependency management, lint/validation pipeline, and GitOps integration (Flux HelmRelease, Argo CD Application)

**Slash command:**
- `/platform-skills:helmcheck` (`commands/helmcheck.md`) — three modes: `create` (scaffold a production-ready chart), `review` (analyse chart structure and quality), `security` (audit RBAC, pod security, network policies, and secrets handling)

**Example chart:**
- `examples/helm/web-service/` — full production chart: security-hardened Deployment, Service, Ingress, ServiceAccount, HPA, PDB, NetworkPolicy, `values.schema.json`, and helm test pod compliant with `restricted` PodSecurity

**Platform rules added:**
- Helm lint pipeline rule: enforce `helm lint --strict` → `helm template --debug` → `kubeconform -strict -summary` → `checkov` → `helm test` in order; fail CI on any `helm lint --strict` warning

**Tests:**
- `tests/validate-helmcheck.sh` — 62 checks covering command structure, SKILL.md integration, reference guide sections, chart file presence, Chart.yaml correctness, schema validity, security baselines, template safety, and HOW_IT_WORKS completeness

#### Documentation

- `HOW_IT_WORKS.md` — explains how AI coding agents work, how skills activate, how to write effective prompts, how the review workflow runs, and what the agent cannot do

## [1.6.0] - 2026-04-11

### Added

#### Compliance Domain (SOC 2 for Terraform)

New Domain 11: `Compliance` — SOC 2 Trust Services Criteria mapped to Terraform patterns, covering 11 criteria across access, encryption, detection, logging, change management, and availability.

**Reference guide:**
- `references/compliance.md` — full SOC 2 TSC coverage with Terraform patterns, Checkov rule IDs, AWS CLI evidence commands, and a pre-audit readiness checklist

**Criteria covered with Terraform patterns, Checkov rules, and evidence commands:**
- `CC6.1` — IAM least privilege: scoped policies, IRSA, SCPs denying privilege escalation
- `CC6.2` — Authentication: MFA-enforcement SCP, GitHub Actions OIDC (no static credentials)
- `CC6.3` — Access removal: access key rotation via Config `access-keys-rotated` rule
- `CC6.6` — Network security: security groups, private subnets, VPC flow logs, WAF (`aws_wafv2_web_acl`) with rate limiting and AWS managed rule groups
- `CC6.7` — Encryption: S3, RDS, EBS, KMS; extended to DynamoDB, ECR, ElastiCache, OpenSearch, Kinesis, EFS, and Redshift
- `CC6.8` — Vulnerability management: `aws_ecr_registry_scanning_configuration` (ENHANCED + CONTINUOUS_SCAN), `aws_inspector2_enabler`, `aws_ssm_patch_baseline`
- `CC7.1` — Detection: `aws_guardduty_detector` (S3, EKS, malware sources), 14 CIS Benchmark CloudWatch metric filters and alarms (CIS 3.1–3.14), `aws_securityhub_account` with AWS Foundational and CIS standards
- `CC7.2` — Audit logging: multi-region CloudTrail with KMS encryption, S3 object lock (COMPLIANCE mode, 365-day), AWS Config recorder with 12 SOC 2-relevant managed rules, VPC flow logs
- `CC7.3` — Incident response: KMS-encrypted SNS topic with email and PagerDuty subscriptions, GuardDuty HIGH/CRITICAL findings → EventBridge → SNS pipeline, Config delivery channel with SNS notification
- `CC8.1` — Change management: S3 + DynamoDB state locking, PR-gated Terraform plan/apply workflow with plan posted as PR comment
- `A1.1` — Availability: multi-AZ EKS node groups, RDS multi-AZ
- `A1.2 / A1.3` — Backup and recovery: `aws_backup_plan` (daily 35-day + monthly 1-year), `aws_backup_vault_lock_configuration` (COMPLIANCE mode, 35-day minimum), cross-region copy for DR, tag-based backup selection

**Slash command:**
- `/platform-skills:compliance` (`commands/compliance.md`) — five modes: `gap` (find audit blockers), `control` (implement a specific criterion), `evidence` (generate audit-ready CLI commands), `remediate` (fix a Checkov finding with blast-radius analysis), `checklist` (full SOC 2 readiness review)

**Examples:**
- `examples/compliance/checkov-config.yaml` — Checkov config with all SOC 2 check IDs grouped by criterion and documented suppression format
- `examples/compliance/iam/` — IRSA application role, GitHub Actions OIDC trust (plan + apply), SCPs for MFA enforcement and privilege escalation prevention
- `examples/compliance/logging/` — CloudTrail with object lock, AWS Config recorder with 12 managed rules, VPC flow logs
- `examples/compliance/network/` — WAF, security groups, and VPC flow logs
- `examples/compliance/encryption-data-services/` — DynamoDB, ECR, ElastiCache, OpenSearch, Kinesis, EFS, and Redshift encryption/logging controls
- `examples/compliance/vulnerability/` — Inspector v2, ECR enhanced scanning, and SSM patching
- `examples/compliance/detection/` — GuardDuty, CIS CloudWatch alarms, and Security Hub
- `examples/compliance/incident-response/` — KMS-encrypted SNS, EventBridge alert routing, and PagerDuty subscription
- `examples/compliance/backup/` — AWS Backup plan, vault lock, and cross-region DR copies

**Infrastructure updates:**
- Domain 11 (`Compliance`) added to `skills/platform-skills/SKILL.md` tool-routing and reference file list
- `references/compliance.md` added to `REQUIRED_REFERENCES` in `tests/validate-skill.sh`
- `examples/compliance` added to `EXAMPLE_DOMAINS` in `tests/validate-skill.sh`
- `compliance`, `soc2`, `checkov`, `audit-logging`, `iam-least-privilege`, `cloudtrail` added to `marketplace.json` keywords

## [1.5.0] - 2026-04-03

### Added
- `references/platform-mindset.md` — product mindset, developer experience (SPACE/DORA metrics, friction audits, golden paths, Backstage), collaboration and communication (RFC/ADR templates, incident updates, blameless post-mortems), and proactive problem-solving (systemic fixes, capacity planning, cost optimisation loop, quarterly platform health review)
- `/platform-skills:product` command (`commands/product.md`) — applies product thinking to platform work across nine topics: devex, friction, rfc, adr, incident, postmortem, capacity, cost, review
- `references/linux-networking.md` — Linux administration (process/service management, disk, memory/CPU, kernel tuning, permissions) and networking fundamentals (DNS record types, CoreDNS, Route 53, Azure Private DNS, ALB/NLB, Ingress/Gateway API, VPC/VNet CIDR design, subnet tiers, peering vs Transit Gateway, PrivateLink, NSGs, troubleshooting checklists)
- `/platform-skills:linux` command (`commands/linux.md`) — structured guidance for dns, lb, vpc, process, disk, network, security-groups, and troubleshoot topics
- Domain 8 added to SKILL.md tool-routing section: `Linux & Networking`
- Domain 9 added to SKILL.md tool-routing section: `Platform Mindset`

## [1.4.2] - 2026-04-02

### Changed
- Moved `SKILL.md` from the repository root to `skills/platform-skills/SKILL.md` to match the Claude Code proper skill directory format
- Updated `.claude-plugin/plugin.json` to declare `"skills": ["./skills/platform-skills"]` (directory reference) instead of the old root-level path
- Updated `tests/validate-skill.sh` to reference `skills/platform-skills/SKILL.md` in all three validation checks

## [1.4.1] - 2026-04-02

### Added
- `.claude-plugin/plugin.json` — registration manifest explicitly declaring plugin name, version, author, skill (`SKILL.md`), and all 5 command paths so Claude Code uses consistent `/platform-skills:<name>` namespacing regardless of install directory name

## [1.4.0] - 2026-04-02

### Added

#### Slash Commands

Five explicit slash commands added under `commands/` — invoked as `/platform-skills:<name>`:

- `/platform-skills:debug` — structured troubleshooting: classifies the problem layer, lists evidence commands, forms a root-cause hypothesis, proposes a fix with validation and rollback
- `/platform-skills:review` — production-readiness review of any manifest, Terraform file, workflow, or Helm values: correctness, security, operational safety, deprecations
- `/platform-skills:terraform` — full Terraform validation pipeline walkthrough (fmt, validate, tflint, tfsec/checkov), blast radius, IAM risk, state impact, module design
- `/platform-skills:gitops` — Flux CD and Argo CD troubleshooting: classifies by source/artifact/reconciliation/runtime layer, provides exact evidence commands, fix, and rollback
- `/platform-skills:linkerd` — Linkerd diagnostics: injection, mTLS, authorization policy, observability, traffic management, multi-cluster, control plane

## [1.3.0] - 2026-04-02

### Added

#### Reference Guides
- `references/linkerd.md`: mTLS, proxy injection, authorization policy, traffic management (HTTPRoute, retries, timeouts, canary splits), golden-signal observability (`linkerd viz stat/tap`), Prometheus PodMonitor integration, multi-cluster mirroring, and 5-scenario troubleshooting guide
- Linkerd routing rule added to SKILL.md tool classification
- `references/linkerd.md` added to `tests/validate-skill.sh` required references

### Changed
- CONTRIBUTING.md: fixed local install commands (`claude plugin install .` → `claude plugin marketplace add $(pwd)` + `claude plugin install platform-skills`); added upgrade flow; updated What We're Looking For to reflect current roadmap priorities

## [1.2.0] - 2026-04-02

### Added

#### Reference Guides
- Added RBAC troubleshooting to `references/kubernetes.md`: 401 vs 403 diagnosis, `kubectl auth can-i` evidence collection, binding scope matrix (Role/ClusterRole × RoleBinding/ClusterRoleBinding), `ClusterRoleBinding` audit query
- Added image automation section to `references/flux.md`: `ImageRepository`, `ImagePolicy`, `ImageUpdateAutomation` setup, registry auth table (GHCR/ECR/ACR/GAR/Docker Hub), troubleshooting table, safety rules for staging vs. production promotion
- Added `references/secrets.md`: decision matrix (ESO vs. Sealed Secrets), ESO setup for AWS/Azure/Vault/static credentials, Sealed Secrets seal/rotate/backup workflow, troubleshooting tables for both patterns, least-privilege IAM example, operational rules
- Added `references/secrets.md` to `REQUIRED_REFERENCES` in `tests/validate-skill.sh`

#### Plugin
- Bumped marketplace description and keywords to be developer-first (removed enterprise-only framing)
- Added keywords: `helm`, `docker`, `containers`, `deployment`, `rbac`, `secrets`, `security`, `gke`
- Updated SKILL.md activation description and body framing for discoverability by any developer
- Fixed `assignees` format in `renovate.json` (removed `@` prefix)
- Fixed `kubeconform` flag in `validate.yml`: `-skip-kinds` → `-skip` (correct flag name for v0.6.4)
- Fixed `LICENSE` copyright placeholder `[yyyy] [name of copyright owner]` → `2026 Nitin Jain`

## [1.1.0] - 2026-04-02

### Added

#### Reference Guides
- Expanded AWS reference with tagging guidance: `default_tags` provider block, ASG `propagate_at_launch`, EBS/Lambda propagation gaps, AWS Config `required-tags` rule, cost allocation tag activation steps, org-level tag policy enforcement
- Expanded Azure reference with tagging guidance: `merge(local.common_tags, {...})` pattern, tag inheritance gap explanation, Azure Policy `deny`/`modify` enforcement, remediation task for existing resources, AKS managed resource group tagging
- Added tagging rule to SKILL.md: enforce a baseline via provider-level mechanisms; specific keys are an organizational decision

#### Example Assets
- Added real example assets for previously stub domains: `examples/kubernetes/*.yaml` (4 files), `examples/openshift/*.yaml` (2 files), `examples/aws/iam/*.json` (2 files), `examples/azure/workload-identity/` (`main.tf` + `serviceaccount.yaml`)

#### Testing
- Added `tests/validate-skill.sh` — checks SKILL.md frontmatter, all reference files exist, each example domain has at least one asset beyond README.md, SKILL.md references every reference file; wired into `validate.yml` as a blocking CI job

#### Developer Experience
- Added `.github/copilot-instructions.md` — GitHub Copilot automatically applies Platform Skills patterns (no Claude Code required)
- Added `VSCODE_INTEGRATION.md` — comprehensive guide for VSCode with Claude Code extension, GitHub Copilot split-screen, and browser workflows
- Added `QUICKSTART.md` — 5-minute install and first-use guide
- Added `INSTALLATION.md` — full installation methods, team setup, troubleshooting

#### Dependency Management
- Scoped Renovate automerge catch-all rule to explicit managers (terraform, helmv3, kubernetes, docker-compose) to prevent accidental automerge of GitHub Actions

### Fixed

#### CI/CD Workflows
- Fixed `validate.yml` and `release.yml` marketplace.json validation — field paths now match marketplace format (`plugins[0].version`, `plugins[0].description`, etc.)
- Replaced deprecated `actions/create-release` (archived action) with `gh release create` CLI in `release.yml`
- SHA-pinned `hashicorp/setup-terraform` in `validate.yml` — floating `@v4.0.0` tag was causing the workflow's own security check to fail
- Removed unused `actions/setup-node` step from publish-marketplace job

#### Documentation
- Fixed dead Discord `#` placeholder link in README — replaced with real URL
- Added `QUICKSTART.md`, `INSTALLATION.md`, and `VSCODE_INTEGRATION.md` to README navigation and repository structure table
- Fixed hardcoded `v1.0.0` examples in CHANGELOG release checklist — replaced with `vX.Y.Z` placeholder
- Fixed Argo CD example Application `path:` fields — were pointing at Flux monorepo paths instead of Argo CD-appropriate paths
- Fixed Azure workload-identity `main.tf` — added `required_providers` block with minimum `azurerm >= 3.87.0`

### Changed

- README repositioned as handbook-first — skill layer described as optional, not the primary product
- Updated README repository structure tree to show real example files rather than `README.md`-only entries
- Trimmed VSCode install detail from README to a single pointer to VSCODE_INTEGRATION.md — install story now lives in one place
- Marketplace distribution: personal marketplace now named `platform-skills` (was `platform-skills-marketplace`)
- Owner contact updated to personal email
- All CLI command references updated: binary is `claude`, subcommand is `claude plugin` (not `claude-code skill`)

## [1.0.0] - 2026-04-02

Initial release of Platform Skills - A comprehensive Claude Agent Skill for platform engineering across 8 domains: Kubernetes, OpenShift, Argo CD, Flux CD, AWS, Azure, Terraform, and GitHub Actions.

### Added

#### Automation & CI/CD
- GitHub Actions workflow for automated releases (`.github/workflows/release.yml`)
  - Version validation and consistency checks
  - Quality checks (markdown, YAML, Terraform, security)
  - Automatic GitHub Release creation
  - Marketplace publication preparation
- GitHub Actions workflow for continuous validation (`.github/workflows/validate.yml`)
  - Repository structure validation
  - Markdown linting and link checking
  - YAML and Kubernetes manifest validation
  - Terraform format and validation checks
  - Security scanning for secrets and action pinning
- Renovate configuration for automated dependency updates (`renovate.json`)
  - GitHub Actions SHA pinning with automatic updates
  - Terraform provider version management
  - Helm chart version tracking
  - Container image update monitoring
  - Security vulnerability alerts
- Consolidated release process documentation in CONTRIBUTING.md
- Removed redundant internal documentation (QUALITY_ASSURANCE.md, WORKFLOWS_SUMMARY.md)
- Cleaned up experimental files for production release
- Clarified distribution model: GitHub repository as primary distribution
- Fixed README structure (removed duplicate Installation headers)
- Updated marketplace.json with accurate repository URL and description

#### Core Features
- Initial release of Platform Skills
- Core skill definition in SKILL.md with activation triggers and troubleshooting framework
- GETTING_STARTED.md for new user onboarding
- Reference guides for 8 domains:
  - Platform Operating Model - Cross-cutting architecture and ownership patterns
  - Kubernetes - Cluster baselines, workload patterns, and policy defaults
  - OpenShift - Routes, SCC-aware workload design, operators, and tenancy
  - Argo CD - Projects, app-of-apps, ApplicationSet patterns, and promotion flows
  - Flux CD - GitOps reconciliation and repository structure patterns
  - AWS - Account model, EKS, IAM, and cloud foundations
  - Azure - Subscription model, AKS, RBAC, and resource management
  - Terraform - Module architecture, state management, and validation
  - GitHub Actions - Workflow security, reusability, and promotion patterns
- Working examples for all 8 domains:
  - Kubernetes: Namespace baselines, deployment patterns, network policy, pod disruption budgets
  - OpenShift: Routes, quotas, and platform-specific security adaptation
  - Argo CD: App-of-apps root application manifest
  - Flux CD: Complete monorepo structure with production and staging environments
  - AWS: IAM, VPC, EKS patterns
  - Azure: AKS, workload identity
  - Terraform: Production EKS module, multi-environment structures
  - GitHub Actions: Complete CI/CD pipelines, Flux sync validation, container builds
- Comprehensive README with installation and usage instructions
- Contributing guidelines for community participation
- Skill development guide (CLAUDE.md) with philosophy and patterns
- Apache-2.0 license with NOTICE file
- Claude Code marketplace integration (dual distribution: marketplace + local install)

### Core Principles Established
- Production-first mindset with blast radius awareness
- Root-cause analysis over symptom treatment
- Explicit rollback plans for all risky operations
- Security by default with least-privilege patterns
- Progressive disclosure from quick answers to deep dives

### Problem Classification Framework
- Kubernetes: Baseline standards, workload patterns, security controls, operational consistency
- OpenShift: Platform-specific constraints, GitOps integration, security and tenancy, day-2 operations
- Argo CD: Repository patterns, reconciliation model, promotion model, safety rules
- Flux CD: Source, Artifact, Reconciliation, Chart Rendering, Runtime issues
- AWS: Access/Auth, Network, Service-Specific, Cost, Compliance
- Azure: Access/Auth, Network, Service-Specific, Cost, Compliance
- Terraform: State Conflicts, Plan Failures, Apply Failures, Drift, Module Design
- GitHub Actions: Workflow Syntax, Permissions, Performance, Security, Reliability

### Troubleshooting Structure
- Symptom identification
- Evidence collection commands
- Hypothesis formation
- Diagnostic validation
- Specific fix with justification
- Verification steps
- Prevention strategies
- Rollback procedures

### Best Practices Documented
- Kubernetes: Platform baselines, workload patterns, security policies, operational rules
- OpenShift: Route patterns, SCC compatibility, operator usage, tenant isolation
- Argo CD: App-of-apps design, ApplicationSet patterns, sync control, promotion flows
- Flux CD: Reconciliation patterns, repository structures, multi-tenancy, progressive delivery
- AWS: IAM least privilege, tagging standards, EKS patterns, OIDC federation
- Azure: Managed identities, policy enforcement, AKS configuration, workload identity
- Terraform: Module conventions, state isolation, validation pipelines, testing strategies
- GitHub Actions: Security controls, reusable workflows, OIDC authentication, SHA-pinned actions

### Quality & Security Improvements
- Fixed workflow validation subshell issues - error counts now properly propagate
- Made Terraform validation blocking in release workflow
- SHA-pinned all GitHub Actions in examples (no mutable @v3/@v4 tags)
- Fixed tflint_version from "latest" to specific version (v0.50.3)
- Fixed malformed nested Markdown in contribution guidelines
- Updated all reference files to be reconciler-agnostic (supports both Flux CD and Argo CD)
- Fixed Argo CD example paths to reference existing repository structure
- Clarified dual distribution model: Claude marketplace (primary) + local installation (customization)

### Roadmap Items Completed
- ✅ Added Argo CD patterns alongside Flux CD
- ✅ Added Kubernetes platform baseline patterns
- ✅ Added OpenShift operating patterns

---

## Release Process

### Version Numbering

- **Major (X.0.0)**: Breaking changes to skill interface or structure
- **Minor (1.X.0)**: New patterns, reference guides, or significant enhancements
- **Patch (1.0.X)**: Bug fixes, clarifications, or minor updates

### What Warrants a Release

**Major Release:**
- Restructuring of core SKILL.md that changes skill behavior
- Breaking changes to reference file structure
- Removal of deprecated patterns

**Minor Release:**
- New reference guides (e.g., adding GCP patterns)
- Significant new troubleshooting sections
- New best practice patterns
- Tool version updates requiring new approaches

**Patch Release:**
- Typo fixes and clarifications
- Broken link fixes
- Command syntax updates
- Minor example improvements

### Release Checklist

Before releasing:

- [ ] Update version in `.claude-plugin/marketplace.json`
- [ ] Update this CHANGELOG with release notes
- [ ] Verify all examples work with current tool versions
- [ ] Test skill activation in Claude Code
- [ ] Review all external links
- [ ] Tag release in git: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
- [ ] Push tag: `git push origin vX.Y.Z`
- [ ] Create GitHub release with changelog excerpt
- [ ] Update marketplace if applicable

---

## Tool Version Compatibility

### Current Testing Matrix

| Tool | Version | Last Verified |
|------|---------|---------------|
| Flux CD | 2.2+ | 2026-04-02 |
| Terraform | 1.5+ | 2026-04-02 |
| AWS CLI | 2.x | 2026-04-02 |
| Azure CLI | 2.50+ | 2026-04-02 |
| kubectl | 1.28+ | 2026-04-02 |
| Helm | 3.12+ | 2026-04-02 |

### Deprecation Notices

None currently.

---

## Migration Guides

### Upgrading from Pre-1.0

N/A - Initial release

---

## Contributors

Thank you to all contributors who helped build Platform Skills:

- [@nitinjain999](https://github.com/nitinjain999) - Initial skill design and implementation

See [CONTRIBUTING.md](CONTRIBUTING.md) to join this list!

---

## Links

- [Repository](https://github.com/nitinjain999/platform-skills)
- [Issues](https://github.com/nitinjain999/platform-skills/issues)
- [Discussions](https://github.com/nitinjain999/platform-skills/discussions)
- [Claude Code Marketplace](https://claude.ai/marketplace/skills)

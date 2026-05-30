# Platform Skills Prompt Library

Copy these prompts into Claude, Codex, Cursor, or GitHub Copilot. In Claude and Codex, keep `$platform-skills` when the integration is installed. In Cursor and Copilot, the same prompts work as natural language after you install the project rules or Copilot instructions.

## Fast Starters

```text
Use $platform-skills to review this change for production readiness. Focus on ownership, blast radius, validation, rollback, and security defaults.
```

```text
Act as a senior platform engineer. Review the files I changed and return findings ordered by severity, with exact file references, validation steps, and rollback notes.
```

```text
Use platform-skills patterns to turn this rough infrastructure idea into a safe implementation plan with assumptions, risks, validation, and rollback.
```

## Kubernetes

```text
Use $platform-skills to review this Kubernetes workload for production readiness: securityContext, resources, probes, lifecycle, HPA, PDB, service account, RBAC, and NetworkPolicy.
```

```text
Generate a production-ready Kubernetes Deployment, Service, HPA, PDB, and NetworkPolicy for this app. Include validation commands and rollback steps.
```

```text
This pod is CrashLoopBackOff. Walk me through evidence collection, likely root causes, safe fixes, validation, and rollback.
```

## Terraform

```text
Use $platform-skills to review this Terraform plan for replacement risk, IAM scope, state impact, provider constraints, cost, compliance, and rollback.
```

```text
Generate a Terraform module skeleton with versions.tf, variables.tf validations, outputs.tf, README.md, examples, and validation commands.
```

```text
Review this IAM policy for least privilege. Flag wildcard actions, wildcard resources, missing conditions, and safer alternatives.
```

## GitOps: Flux CD And Argo CD

```text
Use $platform-skills to debug this Flux Kustomization or HelmRelease that is stuck NotReady. Start with evidence, then root cause, fix, validation, and rollback.
```

```text
Review this Flux repository structure for source ownership, environment overlays, image automation boundaries, secret handling, and promotion safety.
```

```text
Review this Argo CD Application for project isolation, sync policy, prune behavior, namespace creation, drift risk, and rollback path.
```

## Helm

```text
Use $platform-skills to review this Helm chart for values design, immutable selectors, securityContext, probes, resources, schema validation, and GitOps compatibility.
```

```text
Generate a production-ready Helm chart for this service with values.schema.json, NetworkPolicy, HPA, PDB, probes, resources, and test hooks.
```

## GitHub Actions

```text
Use $platform-skills to harden this GitHub Actions workflow. Check permissions, OIDC, SHA-pinned actions, pull_request_target risk, caching, secrets, and artifact integrity.
```

```text
Generate a GitHub Actions pipeline for Terraform with fmt, validate, tflint, checkov, plan, approval gates, and least-privilege OIDC.
```

## AWS, Azure, And Cloud

```text
Use $platform-skills to review this AWS design for IAM least privilege, network boundaries, encryption, logging, cost, tagging, and rollback.
```

```text
Review this EKS setup for IRSA, node group safety, cluster access, logging, network policy readiness, and upgrade risk.
```

```text
Review this Azure AKS setup for workload identity, RBAC, network policy, private cluster exposure, logging, and policy controls.
```

## Security And Compliance

```text
Use $platform-skills to review this change for SOC 2 control impact. Map findings to access control, encryption, logging, monitoring, backup, and change management.
```

```text
Review this supply chain pipeline for Cosign signing, SBOM generation, provenance, image scanning, dependency pinning, and admission enforcement.
```

```text
Review these Kyverno or OPA policies for audit-first rollout, false positive risk, test coverage, exception handling, and promotion to enforcement.
```

## Observability And Incidents

```text
Use $platform-skills to design observability for this service: logs, metrics, traces, SLOs, dashboards, alerts, runbooks, and validation.
```

```text
We have an incident. Build a troubleshooting plan with symptom, evidence, hypotheses, diagnosis commands, safe fixes, validation, prevention, and rollback.
```

```text
Review these alerts for actionability, ownership, severity, burn-rate signal, noise risk, and runbook links.
```

## KEDA And Autoscaling

```text
Use $platform-skills to review this KEDA ScaledObject or ScaledJob for trigger auth, min/max replicas, cooldown, fallback, scale-to-zero risk, and validation.
```

```text
Design an event-driven autoscaling setup for this queue or metric. Include scaler choice, authentication, failure behavior, validation, and rollback.
```

## PR Review

```text
Use $platform-skills to review this PR across six dimensions: cost, drift, ownership, compliance, upgrade risk, and rollback feasibility.
```

```text
Summarize this PR for a platform maintainer. Call out risky files, missing validation, blast radius, and what must be fixed before merge.
```

```text
Triage the review comments on this PR. Classify valid fixes, questions, duplicates, and non-actionable comments. Apply safe fixes only.
```

## Team Rollout

```text
Create a rollout plan for adopting platform-skills across 50 repositories using Copilot instructions, Cursor rules, Codex skills, and Claude. Include phases, ownership, validation, and rollback.
```

```text
Create a one-page internal announcement for platform-skills. Explain who should use it, how to install it, first prompts to try, and how to report gaps.
```

## Security Team

```text
Use $platform-skills to audit all IAM roles and policies in this Terraform module.
Flag wildcard actions, wildcard resources, missing conditions, overly broad assume-role trust policies, and unused permissions.
```

```text
Review this supply chain configuration for software composition risks: pinned action SHAs, SBOM generation, image signing, dependency provenance, and artifact attestation.
```

```text
Generate an OPA/Rego policy that enforces these security controls on all Kubernetes Deployments:
non-root containers, read-only root filesystem, dropped capabilities, no hostPID or hostNetwork, and resource limits required.
```

```text
Review this Falco rule set for coverage gaps, false-positive risk, and missing detections for privilege escalation, lateral movement, and data exfiltration in a Kubernetes environment.
```

```text
Use $platform-skills to produce a threat model for this architecture diagram. Identify trust boundaries, attack vectors, blast radius, and prioritized mitigations.
```

## SRE Team

```text
Use $platform-skills to walk me through this incident symptom: [paste error, alert, or log]. Start with evidence collection, then root cause hypothesis, safe fix options, validation steps, and rollback.
```

```text
Generate a runbook for this failure mode: [describe the failure]. Include detection signals, triage steps, escalation path, remediation commands, validation, and post-incident actions.
```

```text
Review these SLO definitions for correctness: error budget calculation, burn rate alert thresholds, window alignment, and whether the SLIs actually measure user experience.
```

```text
Use $platform-skills to design a chaos experiment for this service. Include steady-state hypothesis, failure injection method, blast radius, abort conditions, and success criteria.
```

```text
Generate capacity planning estimates for this workload at 2x and 5x current traffic. Include pod count, node count, RDS instance size, and NAT gateway throughput.
```

## App and Developer Team

```text
I'm onboarding to this platform. Walk me through what I need to know: cluster access, namespaces, secrets management, deploy process, observability, and how to get help.
```

```text
Use $platform-skills to review my PR before I ask for human review. Check for: missing tests, unsafe Kubernetes defaults, hardcoded config, secrets in code, and missing rollback plan.
```

```text
Generate a deploy checklist for this service going to production for the first time.
Include: health check endpoints, runbook location, alerting coverage, rollback procedure, and feature flag state.
```

```text
This deploy just went wrong. Walk me through a safe rollback: how to detect the blast radius, the rollback commands, how to validate it worked, and what to document in the incident channel.
```

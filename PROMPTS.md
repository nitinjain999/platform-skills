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

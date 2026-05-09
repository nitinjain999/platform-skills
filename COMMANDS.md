# Skill Commands — Usage Guide

This guide shows how to invoke each `/platform-skills:<command>` slash command in Claude Code or the Claude desktop app.

## Prerequisites

Install the plugin once:

```bash
claude plugin install platform-skills
```

Then restart Claude Code. All commands below work in any conversation.

---

## Command Reference

### `/platform-skills:review`

Production-readiness review of any platform config — Kubernetes manifests, Terraform, GitHub Actions workflows, Helm values.

```
/platform-skills:review [paste file content or describe what to review]
```

**Examples:**

```
/platform-skills:review
```
*(paste a manifest — Claude will classify findings as Critical / Improvement / Note)*

```
/platform-skills:review check my HPA configuration for correctness
```

```
/platform-skills:review
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders-service
...
```

---

### `/platform-skills:debug`

Structured troubleshooting for any platform symptom. Classifies the problem layer, proposes evidence to collect, forms a root-cause hypothesis, and suggests a fix with rollback steps.

```
/platform-skills:debug [symptom or error message]
```

**Examples:**

```
/platform-skills:debug Flux kustomization stuck in NotReady, error: "context deadline exceeded"
```

```
/platform-skills:debug pod CrashLoopBackOff: OOMKilled, limits 256Mi
```

```
/platform-skills:debug 503 errors spiked after deploying v2, Linkerd retries not helping
```

---

### `/platform-skills:terraform`

Full Terraform validation pipeline — fmt, validate, tflint, security scan — plus blast radius and IAM risk review.

```
/platform-skills:terraform [paste terraform code, plan output, or describe the change]
```

**Examples:**

```
/platform-skills:terraform review this IAM policy for least-privilege violations
```

```
/platform-skills:terraform
resource "aws_iam_role_policy" "app" {
  policy = jsonencode({ Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }] })
}
```

```
/platform-skills:terraform what is the blast radius of deleting this module?
```

---

### `/platform-skills:gitops`

Flux CD and Argo CD reconciliation troubleshooting — source, artifact, reconciliation, chart rendering, and runtime workload issues.

```
/platform-skills:gitops [describe the GitOps symptom, paste flux/argocd output, or share a manifest]
```

**Examples:**

```
/platform-skills:gitops flux get kustomizations shows "dependency not found"
```

```
/platform-skills:gitops ArgoCD app stuck in OutOfSync despite manual sync
```

```
/platform-skills:gitops HelmRelease is failing with "values don't match schema"
```

---

### `/platform-skills:linkerd`

Linkerd mTLS, injection, policy, and multi-cluster diagnostics.

```
/platform-skills:linkerd [describe the Linkerd symptom or paste linkerd check / viz output]
```

**Examples:**

```
/platform-skills:linkerd pod injection not working after adding annotation
```

```
/platform-skills:linkerd mTLS handshake failures between orders-service and payments-service
```

```
/platform-skills:linkerd how do I set up AuthorizationPolicy for internal traffic only?
```

---

### `/platform-skills:linux`

Linux administration, DNS, load balancing, VPC/VNet networking, and connectivity troubleshooting.

```
/platform-skills:linux [topic: dns | lb | vpc | process | disk | network | security-groups | troubleshoot]
```

**Examples:**

```
/platform-skills:linux dns pod cannot resolve service.namespace.svc.cluster.local
```

```
/platform-skills:linux network packets dropped between node and pod, no obvious route
```

```
/platform-skills:linux security-groups inbound rule allowing 0.0.0.0/0 on port 22
```

---

### `/platform-skills:commit`

Generate conventional commit messages from a staged diff or description. Supports message generation, file staging, and spec validation.

```
/platform-skills:commit [analyze|generate|stage|validate] [optional: type/scope override or description]
```

**Modes:**

| Mode | What it does |
|------|-------------|
| `analyze` | Classifies type and scope from staged diff |
| `generate` | Writes a full commit message with WHY |
| `stage` | Groups unrelated files into atomic commits |
| `validate` | Checks an existing message against the spec |

**Examples:**

```
/platform-skills:commit generate
```
*(analyzes staged changes and writes the commit message)*

```
/platform-skills:commit validate "fix: update config"
```

```
/platform-skills:commit analyze
```
*(classifies type/scope — you decide whether to commit)*

---

### `/platform-skills:helmcheck`

Create Helm chart scaffolding, review chart structure, or run a security analysis.

```
/platform-skills:helmcheck [create <workload-type> | review | security] [chart path or description]
```

**Examples:**

```
/platform-skills:helmcheck create deployment for a Node.js API service
```

```
/platform-skills:helmcheck review ./charts/orders-service
```

```
/platform-skills:helmcheck security check for privileged containers and host mounts
```

---

### `/platform-skills:observability`

Instrument services, build Grafana dashboards, write Prometheus alerts, design load tests, and plan capacity.

```
/platform-skills:observability [instrument|dashboard|alert|loadtest|capacity] [service description]
```

**Examples:**

```
/platform-skills:observability instrument a Python FastAPI service with RED metrics
```

```
/platform-skills:observability alert write SLO-based alerts for 99.9% availability
```

```
/platform-skills:observability dashboard design a Grafana dashboard for the orders-service
```

```
/platform-skills:observability loadtest write a k6 script for 1000 concurrent users
```

---

### `/platform-skills:opa`

Generate Rego policies, write unit tests, run the validation pipeline (fmt → regal → conftest verify), explain policies in plain English, or debug rule evaluation.

```
/platform-skills:opa [generate|test|validate|explain|debug] [policy description or file path]
```

**Modes:**

| Mode | What it does |
|------|-------------|
| `generate` | Writes a Rego policy from a description |
| `test` | Writes `_test.rego` unit tests with fixtures |
| `validate` | Runs fmt → regal lint → conftest verify |
| `explain` | Translates Rego to plain English |
| `debug` | Diagnoses why a rule fires or doesn't |

**Examples:**

```
/platform-skills:opa generate a policy that denies Kubernetes pods without resource limits
```

```
/platform-skills:opa test write unit tests for my IAM wildcard policy
```

```
/platform-skills:opa validate ./policies
```

```
/platform-skills:opa explain this rule:
deny contains msg if {
    some name
    bucket := input.resource.aws_s3_bucket[name]
    bucket.acl == "public-read"
    msg := sprintf("S3 bucket '%s' must not be public", [name])
}
```

---

### `/platform-skills:compliance`

SOC 2 gap analysis, control mapping, evidence generation, and Checkov remediation for Terraform code.

```
/platform-skills:compliance [topic: gap | control | evidence | remediate | checklist]
```

**Examples:**

```
/platform-skills:compliance gap analyze my Terraform for SOC 2 CC6.1 access control gaps
```

```
/platform-skills:compliance control map this IAM policy to SOC 2 controls
```

```
/platform-skills:compliance remediate this Checkov failure: CKV_AWS_18
```

---

### `/platform-skills:datadog`

Datadog Agent setup, APM instrumentation, monitor and dashboard creation, SLOs, and incident investigation.

```
/platform-skills:datadog [setup|instrument|monitor|dashboard|slo|investigate|debug] [service or description]
```

**Examples:**

```
/platform-skills:datadog setup install Datadog Agent on EKS with APM enabled
```

```
/platform-skills:datadog monitor create a high error rate monitor for the orders-service
```

```
/platform-skills:datadog investigate a p99 latency spike in the payments-service over the last 2 hours
```

---

### `/platform-skills:dynatrace`

Dynatrace Operator deployment, OneAgent injection, code-level instrumentation, SLOs, and Davis AI incident investigation.

```
/platform-skills:dynatrace [setup|instrument|monitor|slo|dashboard|investigate|debug] [service or description]
```

**Examples:**

```
/platform-skills:dynatrace setup deploy the Dynatrace Operator on Kubernetes
```

```
/platform-skills:dynatrace slo create an availability SLO for 99.9% over 30 days
```

```
/platform-skills:dynatrace investigate anomaly detection firing on the checkout service
```

---

### `/platform-skills:document`

Generate docstrings, OpenAPI specs, documentation sites, or getting started guides.

```
/platform-skills:document [docstrings|openapi|site|guide] [language/framework] [path or description]
```

**Examples:**

```
/platform-skills:document docstrings python add Google-style docstrings to this module
```

```
/platform-skills:document openapi generate an OpenAPI 3.1 spec for a REST orders API
```

```
/platform-skills:document guide write a getting started guide for the orders-service
```

---

### `/platform-skills:mcp`

Create, review, or debug Model Context Protocol server implementations in TypeScript or Python.

```
/platform-skills:mcp [create|review|debug] [typescript|python] [description]
```

**Examples:**

```
/platform-skills:mcp create typescript an MCP server that exposes Kubernetes pod logs as a tool
```

```
/platform-skills:mcp review my MCP server for security and error handling
```

```
/platform-skills:mcp debug tool call returns empty result
```

---

### `/platform-skills:product`

Platform product thinking — DevEx audits, friction mapping, RFC/ADR drafting, incident updates, post-mortems, and capacity/cost review.

```
/platform-skills:product [topic: devex | friction | rfc | adr | incident | postmortem | capacity | cost | review]
```

**Examples:**

```
/platform-skills:product friction audit the developer onboarding experience
```

```
/platform-skills:product rfc draft an RFC for migrating from Argo CD to Flux CD
```

```
/platform-skills:product postmortem write a post-mortem for a database failover incident
```

```
/platform-skills:product cost review EC2 rightsizing opportunities for the data platform
```

---

## Tips

- **Paste context directly** — paste a manifest, error output, or code block right after the command for the best results.
- **Chain commands** — run `/platform-skills:debug` to diagnose, then `/platform-skills:review` to validate the fix.
- **Reference examples** — each command has working examples in [examples/](examples/) and a deep-dive in [references/](references/).
- **Auto-activation** — the skill activates automatically when you work with Kubernetes, Terraform, GitOps, or GitHub Actions files — you don't always need the slash command.

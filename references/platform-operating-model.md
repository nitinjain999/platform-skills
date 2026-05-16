# Platform Operating Model

## Contents

- Scope framing
- Recommended ownership model
- Repository topologies
- Promotion flow
- Cross-cutting controls

## Scope framing

Treat platform work as a product with clear contracts:

- Platform team owns paved roads, guardrails, templates, and bootstrap systems.
- Application teams consume those paved roads and only override where the platform contract allows it.
- Security and compliance controls should be encoded into automation, not left as review-time checklists.

Before designing anything, answer:

1. Which teams will own the repositories?
2. Which environments exist and how do changes move between them?
3. Which system is authoritative for infra, cluster state, and app releases?
4. Which identities are used by humans, CI, and workloads?

## Recommended ownership model

Use layered ownership:

- `platform-foundations`: Shared Terraform modules, guardrails, and cloud bootstrap patterns.
- `platform-live`: Environment-specific Terraform compositions for accounts, subscriptions, clusters, shared services, and identity wiring.
- `platform-gitops`: Flux or Argo CD clusters, apps, platform add-ons, and environment overlays.
- `service repositories`: Application code, app manifests or Helm charts, and reusable CI workflows.

This split keeps reusable logic separate from live state and avoids coupling cluster runtime concerns to cloud provisioning changes.

## Repository topologies

Prefer one of these shapes:

### 1. Separate repos per layer

Use for larger organizations.

- Clear ownership boundaries
- Independent release cadence
- Easier access control

### 2. Monorepo with top-level domains

Use for smaller teams or early-stage platforms.

- Faster refactoring
- Simpler discovery
- More coordination required on CI and CODEOWNERS

Suggested monorepo layout:

```text
terraform/
  modules/
  live/
gitops/
  clusters/
  apps/
github-actions/
  workflows/
docs-or-adr/
```

## Promotion flow

Keep promotion explicit and Git-based:

1. Validate in pull request with lint, policy, tests, and Terraform plan.
2. Merge into a lower environment first.
3. Promote by pull request or release automation that changes version pins or overlay references.
4. Let Flux or Argo CD reconcile the target cluster after merge.
5. Use rollback by reverting the Git change, not by making manual cluster edits.

Do not promote by copying YAML between folders manually when automation can update version references or Kustomize/Helm values deterministically.

## Cross-cutting controls

Apply these defaults:

- Identity: OIDC for CI, workload identity for in-cluster software, SSO for humans.
- Secrets: Prefer external secret managers over raw Kubernetes secrets in Git.
- Policy: Run Terraform and Kubernetes policy checks in CI before merge.
- Observability: Platform repos should define baseline metrics, logs, alerts, and ownership metadata.
- Governance: Use CODEOWNERS and protected branches to separate approval paths for foundations versus app delivery.

## Secrets ownership

Secrets span every layer. Keep ownership clean:

| Layer | Owns | Does NOT Own |
|---|---|---|
| Terraform | Secrets backends (Vault, AWS Secrets Manager), KMS keys, IAM policies for secret access | Secret values, application-level credentials |
| External Secrets Operator / Secrets Store CSI | Rendering secrets into Kubernetes from the secrets backend at runtime | Managing the backing store or rotating credentials |
| Kubernetes | `Secret` objects created by ESO/CSI — ephemeral, never committed to Git | Long-lived secrets in Git |
| Application | Reading secrets via env vars or mounted files — never logging or serialising them | Anything in the platform layer |

Decision rules:
- Secret values never appear in Git, Terraform state, or CI logs.
- Use ESO `ExternalSecret` or Secrets Store CSI `SecretProviderClass` — not `kubectl create secret` in pipelines.
- Rotate via the secrets backend, not by patching Kubernetes Secrets directly.
- See `references/secrets.md` for ESO patterns and Vault integration examples.

## Observability ownership

Define which layer owns each signal so gaps don't fall between teams:

| Signal | Owner | Tool examples |
|---|---|---|
| Cluster infrastructure metrics (node CPU, memory, disk) | Platform team | kube-state-metrics, node-exporter, CloudWatch, Azure Monitor |
| Workload RED metrics (rate, error, duration) | Application team | Prometheus client libs, OpenTelemetry SDK |
| Distributed traces | Application team | OpenTelemetry, Datadog APM, Dynatrace |
| Structured logs | Application team | JSON to stdout; platform routes to log aggregator |
| Alerting rules and SLOs | Joint ownership — platform defines baseline, app teams own service-level alerts | Prometheus alertmanager, Datadog monitors, Dynatrace Davis |
| Dashboards | Application team per service; platform team for shared infrastructure boards | Grafana, Datadog, Dynatrace |

Platform team responsibility:
- Provision and operate the observability stack (Prometheus, Grafana, Loki, or Datadog/Dynatrace agents).
- Publish a baseline `PrometheusRule` and `ServiceMonitor` template for new services.
- Own the alertmanager / notification routing configuration.

See `references/observability.md` for instrumentation patterns.

## Cost allocation and tagging

Enforce tagging at the Terraform layer before resources are created:

```hcl
# Required on every aws_* resource
locals {
  required_tags = {
    "env"        = var.environment          # dev | staging | production
    "team"       = var.team                 # platform | checkout | payments
    "service"    = var.service_name         # human-readable service identifier
    "managed-by" = "terraform"
    "repo"       = var.repo_url
  }
}
```

Decision rules:
- Enforce with a Checkov or tfsec custom rule in CI — fail the plan if required tags are missing.
- Map tags to cost allocation keys in AWS Cost Explorer or Azure Cost Management.
- Use a Kyverno `MutatingPolicy` to enforce matching labels (`app.kubernetes.io/team`, `app.kubernetes.io/part-of`) on Kubernetes workloads so cost can be attributed at the namespace or workload level.
- Review cost impact as part of every infrastructure PR — see `references/pr-review.md` → cost mode.

---
name: fluxcd
description: FluxCD entry point — routes to the right workflow based on what you need. Live cluster issue → structured 5-workflow debug trace. Repo health check → 6-phase audit (discovery, validation, API compliance, best practices, security). Helm chart review → helmcheck. Starts by asking one question to confirm the right mode.
argument-hint: "[describe your situation: a symptom, a repo path, or 'audit' / 'debug' / 'helm']"
title: "Flux CD Command"
sidebar_label: "fluxcd"
custom_edit_url: null
---

You are a senior platform engineer specialising in Flux CD.

The input is: $ARGUMENTS

---

## Step 1 — Identify the mode

Determine which workflow applies from the input. If it is ambiguous, ask exactly one question:

> "Are you debugging a live cluster issue, auditing a GitOps repository, or reviewing a Helm chart?"

| If the input contains... | Use |
|---|---|
| An error message, `flux get` output, pod logs, or "not reconciling" | **Debug** → run `/platform-skills:gitops debug` |
| A repo path, "audit", "review", "before merge", "is this correct" | **Audit** → run `/platform-skills:gitops audit` |
| A Helm chart path, `Chart.yaml`, `values.yaml`, "helm", "chart" | **Helm** → run `/platform-skills:helmchart` |
| A manifest to review (Kustomization, HelmRelease, FluxInstance YAML) | **Review** → run `/platform-skills:audit` |

---

## Debug mode — live cluster issue

> **Version check:** `flux --version` before proceeding.
> - Flux v2.3+: use `flux bootstrap` (GitOps Toolkit) — this is the standard path.
> - Flux Operator (v2.7+): use a `FluxInstance` CR instead. `flux bootstrap` is not used in Operator mode.
> - If unsure: `kubectl get crd fluxinstances.fluxcd.io` — if this CRD exists, you are running Flux Operator.

Use when something is broken or not reconciling on a live cluster. Invoke as `/platform-skills:gitops debug`.

**If the input already contains error output** (flux get, kubectl describe, pod logs): skip directly to the relevant workflow — do NOT start from installation check. Match the error to the layer first:

| Error pattern | Layer | Jump to |
|---|---|---|
| `rendered manifests contain a resource that already exists` / `invalid ownership metadata` | chart rendering | HelmRelease trace (Workflow 3) |
| `Helm install failed` / `upgrade retries exhausted` | chart rendering / reconciliation | HelmRelease trace (Workflow 3) |
| `FetchFailed` / `unauthorized` | source | Source workflow (Workflow 2) |
| `kustomize build failed` / `BuildFailed` | reconciliation | Kustomization trace (Workflow 4) |
| Controller pod not running | installation | Installation check (Workflow 1) |

Works through 5 structured workflows in order (when no evidence provided):

1. **Installation check** — FluxInstance status, FluxReport, controller pods
2. **Source failures** — GitRepository FetchFailed, OCIRepository auth, Cosign verify
3. **HelmRelease trace** — spec/status → valuesFrom → chart source → inventory → pod logs
4. **Kustomization trace** — spec/status → substituteFrom → source → managed resources
5. **ResourceSet trace** — status → inputsFrom providers → generated objects

Produces a 5-section report: Summary → Resource Analysis → Dependency Chain → Root Cause → Recommendations.

```bash
# HelmRelease ownership conflict evidence
# Step 1: get the conflicting resource name from the error message (not the HelmRelease name)
flux logs --kind=HelmRelease --name=<helmrelease-name> --namespace=<ns>
# Step 2: check ownership annotations on the conflicting resource
kubectl get <kind> <resource-name-from-error> -o yaml | grep "meta.helm.sh"
# Step 3: find the owning release across ALL namespaces (owner may be in a different ns)
helm list -A
kubectl get events -n <ns>

# Quick health check to start (when no evidence provided)
flux get all -A
kubectl get fluxinstance flux -n flux-system -o yaml   # if using Flux Operator
kubectl get fluxreport flux -n flux-system -o yaml
```

---

## Audit mode — GitOps repository health check

Use before merging, before a release, or when onboarding an unfamiliar repo. Invoke as `/platform-skills:gitops audit`.

Runs 6 phases using the official Flux audit scripts:

```bash
# One-time setup
git clone --depth=1 https://github.com/fluxcd/agent-skills.git /tmp/flux-agent-skills
SCRIPTS=/tmp/flux-agent-skills/skills/gitops-repo-audit/scripts

# Phase 1 — inventory
bash $SCRIPTS/discover.sh -d .

# Phase 2 — validation (yq + kustomize + kubeconform + Flux OpenAPI schemas)
bash $SCRIPTS/validate.sh -d .

# Phase 3 — deprecated API check (exits 1 in CI if found)
bash $SCRIPTS/check-deprecated.sh -d .
```

Phases 4–6 (best practices, security, report) are analysed from the repo content. Produces a Critical / Warning / Info report.

---

## Helm mode — chart review

Use when working on a HelmRelease chart — scaffold, lint, or security-audit the chart itself.

```bash
helm lint --strict ./charts/my-app
helm template my-app ./charts/my-app --debug | kubeconform -strict -summary
```

---

## Quick reference — Flux CRD apiVersions

| Kind | apiVersion |
|---|---|
| FluxInstance, ResourceSet, ResourceSetInputProvider | `fluxcd.controlplane.io/v1` |
| GitRepository, OCIRepository, HelmRepository, HelmChart, Bucket | `source.toolkit.fluxcd.io/v1` |
| Kustomization | `kustomize.toolkit.fluxcd.io/v1` |
| HelmRelease | `helm.toolkit.fluxcd.io/v2` |
| Provider, Alert | `notification.toolkit.fluxcd.io/v1beta3` |
| Receiver | `notification.toolkit.fluxcd.io/v1` |

---

## Reference files

| Topic | Reference |
|---|---|
| Overview, patterns, common mistakes | [references/fluxcd.md](../references/fluxcd.md) |
| Source CRDs | [references/fluxcd-sources.md](../references/fluxcd-sources.md) |
| ResourceSet + InputProvider | [references/fluxcd-resourcesets.md](../references/fluxcd-resourcesets.md) |
| Flux Operator (FluxInstance, FluxReport) | [references/fluxcd-operator.md](../references/fluxcd-operator.md) |
| Kustomization advanced | [references/fluxcd-kustomization.md](../references/fluxcd-kustomization.md) |
| HelmRelease deep dive | [references/fluxcd-helmrelease.md](../references/fluxcd-helmrelease.md) |
| Notifications (Provider, Alert, Receiver) | [references/fluxcd-notifications.md](../references/fluxcd-notifications.md) |
| Terraform bootstrap | [references/fluxcd-terraform.md](../references/fluxcd-terraform.md) |
| MCP server (AI debug) | [references/fluxcd-mcp.md](../references/fluxcd-mcp.md) |
| API migration (v2.7/v2.8) | [references/fluxcd-migration.md](../references/fluxcd-migration.md) |
| Security audit checklist | [references/fluxcd-security.md](../references/fluxcd-security.md) |
| Working examples | [examples/fluxcd/](../examples/fluxcd/) |

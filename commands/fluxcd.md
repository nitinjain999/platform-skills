---
name: fluxcd
description: FluxCD entry point — routes to the right workflow based on what you need. Live cluster issue → structured 5-workflow debug trace. Repo health check → 6-phase audit (discovery, validation, API compliance, best practices, security). Helm chart review → helmcheck. Starts by asking one question to confirm the right mode.
argument-hint: "[describe your situation: a symptom, a repo path, or 'audit' / 'debug' / 'helm']"
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
| A Helm chart path, `Chart.yaml`, `values.yaml`, "helm", "chart" | **Helm** → run `/platform-skills:helmcheck` |
| A manifest to review (Kustomization, HelmRelease, FluxInstance YAML) | **Review** → run `/platform-skills:review` |

---

## Debug mode — live cluster issue

Use when something is broken or not reconciling on a live cluster. Invoke as `/platform-skills:gitops debug`.

Works through 5 structured workflows in order:

1. **Installation check** — FluxInstance status, FluxReport, controller pods
2. **Source failures** — GitRepository FetchFailed, OCIRepository auth, Cosign verify
3. **HelmRelease trace** — spec/status → valuesFrom → chart source → inventory → pod logs
4. **Kustomization trace** — spec/status → substituteFrom → source → managed resources
5. **ResourceSet trace** — status → inputsFrom providers → generated objects

Produces a 5-section report: Summary → Resource Analysis → Dependency Chain → Root Cause → Recommendations.

```bash
# Quick health check to start
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

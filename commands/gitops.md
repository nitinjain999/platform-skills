---
name: gitops
description: Flux CD and Argo CD — two modes. debug: five structured debug workflows for live clusters (installation, source, HelmRelease, Kustomization, ResourceSet) producing a five-section report. audit: six-phase read-only repo analysis (discovery, validation, API compliance, best practices, security) producing a prioritised Critical/Warning/Info report.
argument-hint: "debug [describe symptom or paste flux/argocd output] | audit [repo path or paste directory listing]"
---

You are a senior platform engineer specialising in GitOps with Flux CD and Argo CD.

The input is: $ARGUMENTS

---

## Step 1 — Identify the mode

| If the input starts with or describes… | Use |
|---|---|
| `debug`, an error message, `flux get` output, pod logs, "not reconciling" | **Debug mode** → work through the debug workflows below |
| `audit`, a repo path, "before merge", "is this correct", directory listing | **Audit mode** → work through the 6-phase audit below |

If the mode is ambiguous, ask:
> "Are you debugging a live cluster issue or auditing a GitOps repository?"

---

## Debug mode — live cluster troubleshooting

### 1. Identify the tool and layer

**Flux CD layers:**
- **Source** — GitRepository, OCIRepository, HelmRepository, Bucket
- **Artifact** — Kustomization build, HelmChart render
- **Reconciliation** — Kustomization apply, HelmRelease install/upgrade
- **Runtime** — pod health, hook failures, dependency ordering
- **Operator** — FluxInstance, ResourceSet, ResourceSetInputProvider

**Argo CD layers:**
- **Source** — repo connection, credentials, branch/path
- **Diff** — ignoreDifferences, server-side apply drift
- **Sync** — sync waves, resource hooks, namespace creation
- **Health** — custom health checks, resource status

---

### 2. Flux debug workflows

Work through the relevant workflow. Follow the dependency chain top-down — do not skip layers.

#### Workflow 1 — Installation check

Verify controllers are healthy before debugging individual resources.

```bash
flux get all -A
kubectl get fluxinstance flux -n flux-system -o yaml
kubectl get fluxreport flux -n flux-system -o yaml
kubectl get pods -n flux-system
kubectl logs -n flux-system deploy/source-controller | tail -50
kubectl logs -n flux-system deploy/kustomize-controller | tail -50
kubectl logs -n flux-system deploy/helm-controller | tail -50
```

**Controller failure modes:**

| Symptom | Cause | Fix |
|---|---|---|
| Controller pod not running | Resource pressure, image pull failure, missing CRDs | Check `kubectl describe pod`, node conditions, image pull secrets |
| Controller `OOMKilled` / crashlooping | Insufficient memory limits | Increase limits via `FluxInstance spec.kustomize.patches` or delete pod to reset |
| `spec.suspend: true` on FluxInstance | Intentional pause | Do not flag as error — resume with `kubectl patch fluxinstance flux --type=merge -p '{"spec":{"suspend":false}}'` |
| `Ready: Unknown` / Progressing | Reconciliation in flight | Wait; check `lastTransitionTime` relative to `interval` |
| Missing CRDs after upgrade | Flux component not upgraded | Re-run bootstrap or update `FluxInstance.spec.distribution.version` |

#### Workflow 1b — Source failures

Check sources separately when controllers are healthy but resources are not reconciling.

```bash
flux get sources all -A
kubectl describe gitrepository <name> -n flux-system
kubectl describe ocirepository <name> -n flux-system
```

**Source failure modes:**

| Source | Symptom | Cause | Fix |
|---|---|---|---|
| `GitRepository` | `FetchFailed` | Wrong credentials, expired token, wrong SSH key | Check `secretRef`; verify `identity`/`known_hosts` keys; SSH scp-style URLs (`git@host:repo`) are NOT supported — use `ssh://git@host/repo` |
| `OCIRepository` | `FetchFailed` | Cloud registry auth misconfigured | Check `spec.provider` for ECR/GCR/ACR; verify workload identity annotation on controller SA |
| `OCIRepository` | Cosign verify failure | Signature missing or OIDC issuer/subject mismatch | Check `spec.verify.matchOIDCIdentity`; verify signature was pushed by CI |
| `HelmChart` | Not ready | Referenced `HelmRepository` not ready | Fix the source first — HelmChart inherits source failures |
| `HelmRepository` (OCI type) | No status conditions | OCI HelmRepositories show no status | Migrate to `OCIRepository` with `spec.chartRef` |

#### Workflow 2 — HelmRelease trace

Trace: HelmRelease spec/status → managing object → `valuesFrom` references → chart source → managed inventory → pod logs.

```bash
flux get helmrelease <name> -n <namespace>
kubectl describe helmrelease <name> -n <namespace>
flux logs --kind=HelmRelease --name=<name> --namespace=<namespace>
kubectl get configmap,secret -n <namespace>
flux get sources oci -A
flux get sources helm -A
kubectl get all -n <namespace>
kubectl logs -n <namespace> deploy/<name> | tail -50
```

**Common failures:**

| Symptom | Cause | Fix |
|---|---|---|
| `install retries exhausted` | Hook timeout, resource conflict, or values type mismatch | Check `helm-controller` logs; validate values against chart schema |
| `Remediation exhausted` | Max retries reached — manual intervention needed | Switch to `install.strategy.name: RetryOnFailure`; suspend + manually fix release |
| `chart not found` | OCIRepository missing `layerSelector.mediaType` | Add `layerSelector.mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip` |
| `valuesFrom` key missing | ConfigMap lacks `reconcile.fluxcd.io/watch: Enabled` or wrong key | Verify key name and add watch label |
| `spec.chart.spec` and `spec.chartRef` both set | Mutually exclusive fields | Remove `spec.chart.spec`; use `spec.chartRef` for OCI sources |
| HelmRelease stuck after `spec.force: true` | Force recreates but hooks fail | Disable `force` after the immutable field change is resolved |

#### Workflow 3 — Kustomization trace

Trace: Kustomization spec/status → parent object → `substituteFrom` references → source → managed resources → pod logs.

```bash
flux get kustomization <name> -n flux-system
kubectl describe kustomization <name> -n flux-system
flux logs --kind=Kustomization --name=<name>
kubectl get kustomization -A \
  -o jsonpath='{range .items[*]}{.metadata.name}{" dependsOn: "}{.spec.dependsOn}{"\n"}{end}'
kubectl get configmap,secret -n flux-system -l reconcile.fluxcd.io/watch=Enabled
flux get sources git -A
kubectl get all -n <target-namespace>
```

**Common failures:**

| Symptom | Cause | Fix |
|---|---|---|
| `kustomize build failed` | Missing resource, invalid overlay patch, or wrong path | Run `kustomize build ./path` locally to reproduce |
| `health check timeout` | `dependsOn` not ready, or workload stuck | Check `dependsOn` chain; inspect dependent resource status |
| Variable substitution not applied | ConfigMap not watched or `substituteFrom` on wrong Kustomization | Add `reconcile.fluxcd.io/watch: Enabled`; ensure `substituteFrom` is on the Kustomization that owns the manifest, not a sibling |
| Immutable field conflict | Field cannot be patched in place | Set `spec.force: true` temporarily to recreate; remove after |
| Missing ConfigMap/Secret | `substituteFrom` references an object that doesn't exist | Create the missing object in the Kustomization's namespace |

#### Workflow 4 — ResourceSet trace

Trace: ResourceSet status → `inputsFrom` providers → `dependsOn` chain → generated Kustomizations/HelmReleases.

```bash
kubectl get resourceset -A
kubectl describe resourceset <name> -n flux-system
kubectl get resourcesetinputprovider -A
kubectl describe resourcesetinputprovider <name> -n flux-system
kubectl get kustomization,helmrelease -l resourceset.fluxcd.io/name=<name> -A
kubectl get resourceset <name> -n flux-system -o jsonpath='{.spec.dependsOn}'
```

**Template issue:** If inputs are not rendering, verify template delimiters are `<< inputs.field >>` — not `{{ inputs.field }}`.

#### Workflow 5 — Log analysis

```bash
kubectl get deployment <name> -n <namespace> \
  -o jsonpath='{.spec.selector.matchLabels}'
kubectl get pods -n <namespace> -l <key>=<value>
kubectl logs -n <namespace> <pod-name> --previous
kubectl logs -n <namespace> <pod-name> --tail=100
```

**Edge cases:**
- Flux-managed resources: warn before manual changes — Flux will revert them on next reconciliation.
- Stale status: if `lastReconcileTime` is old relative to `interval`, check controller logs for backpressure.

---

### 3. Argo CD debug workflows

```bash
argocd app get <name> --show-operation
argocd app diff <name>
argocd app logs <name>
kubectl describe application <name> -n argocd
```

**Common failures:**

| Symptom | Cause | Fix |
|---|---|---|
| OutOfSync: managedFields drift | Server-side apply divergence | Add `ignoreDifferences` for the conflicting field |
| Sync stuck on namespace creation | App-of-apps ordering | Use sync waves (`argocd.argoproj.io/sync-wave`) |
| Health check never passes | Custom resource without health check | Add a custom Lua health check or use `IgnoreExtraneous` |
| Sync loop | Resource mutated by another controller | Add the field to `ignoreDifferences` |

---

### 4. Fix

Provide the exact configuration change, annotation, or command. Show before/after for manifest changes.

---

### 5. Report

**1. Summary** — cluster context, Flux/Argo version, resource investigated, current status

**2. Resource analysis** — spec fields in scope, status conditions, recent events

**3. Dependency chain** — e.g. `GitRepository → Kustomization → HelmRelease → Deployment`

**4. Root cause** — evidence-backed from conditions, events, and logs

**5. Recommendations** — ordered: Critical → Warning → Info

---

### 6. Validation

```bash
flux get all -A | grep -v "True"
flux reconcile kustomization <name> --with-source
kubectl get events -n flux-system --sort-by='.lastTimestamp' | tail -20
```

### 7. Rollback

```bash
flux suspend kustomization <name>
flux suspend helmrelease <name> -n <namespace>
git revert <commit> && git push
flux resume kustomization <name>
```

---

## Audit mode — GitOps repository health check

Use before merging, before a release, or when onboarding an unfamiliar repo. Read-only — do not apply any changes.

### Tooling setup (one-time)

```bash
git clone --depth=1 https://github.com/fluxcd/agent-skills.git /tmp/flux-agent-skills
SCRIPTS=/tmp/flux-agent-skills/skills/gitops-repo-audit/scripts
```

**Prerequisites:** `awk` (discover), `yq >= 4.50` + `kustomize >= 5.8` + `kubeconform >= 0.7` (validate), `flux` CLI (check-deprecated).

---

### Phase 1 — Discovery

```bash
bash $SCRIPTS/discover.sh -d .
bash $SCRIPTS/discover.sh -d . -e terraform   # exclude dirs if needed
```

Outputs JSON: `fluxResources.byKind`, `kubernetesResources.byKind`, `kustomizeOverlays.byDirectory`.

Classify the repo pattern:

| Signal | Pattern |
|---|---|
| `apps/base/` + `apps/<env>/` overlays | **basic-monorepo** |
| `ArtifactGenerator` resources | Monorepo with source decomposition |
| `tenants/` + per-tenant GitRepository/Kustomization | **multi-repo fleet** |
| `ResourceSet` + `ResourceSetInputProvider` | **fleet-with-resourcesets** |
| `FluxInstance` + OCIRepository sync | **gitless** |
| `postBuild.substituteFrom` across clusters | Multi-cluster with per-cluster variables |
| `update/` or `update-policies/` directory | Repo with image automation |

Check for `gotk-sync.yaml` — if present, flag for Flux Operator migration.

---

### Phase 2 — Manifest Validation

```bash
bash $SCRIPTS/validate.sh -d .
bash $SCRIPTS/validate.sh -d . -e terraform -e helm-charts
```

What it checks: YAML syntax (yq), Kubernetes manifests (kubeconform -strict + Flux OpenAPI schemas), kustomize build per overlay.

**Valid — not errors:** SOPS-encrypted Secrets, third-party CRDs (`skipped` in kubeconform output), `${VARIABLE}` substitution patterns, `gotk-components.yaml`.

---

### Phase 3 — API Compliance

```bash
bash $SCRIPTS/check-deprecated.sh -d .   # exits 1 if deprecated APIs found — CI-safe
grep -rn "fluxcd.controlplane.io" . --include="*.yaml" | grep "apiVersion"
grep -rn "type: oci" . --include="*.yaml"
```

**Current stable API versions:**

| Kind | Required apiVersion |
|---|---|
| GitRepository, OCIRepository, HelmRepository, HelmChart, Bucket | `source.toolkit.fluxcd.io/v1` |
| Kustomization | `kustomize.toolkit.fluxcd.io/v1` |
| HelmRelease | `helm.toolkit.fluxcd.io/v2` |
| Provider, Alert | `notification.toolkit.fluxcd.io/v1beta3` |
| Receiver | `notification.toolkit.fluxcd.io/v1` |
| FluxInstance, ResourceSet, ResourceSetInputProvider | `fluxcd.controlplane.io/v1` |

---

### Phase 4 — Best Practices

**Kustomization:**
- [ ] `spec.prune: true` — prevents orphaned resources
- [ ] `spec.wait: true` — blocks dependent resources until health checks pass
- [ ] `spec.timeout` set
- [ ] `spec.dependsOn` chains match actual dependency order

**HelmRelease:**
- [ ] `spec.chartRef` (OCI) not `spec.chart.spec`
- [ ] `spec.install.strategy.name: RetryOnFailure` — not legacy `install.remediation.retries`
- [ ] Drift detection: `spec.driftDetection.mode: enabled`
- [ ] Chart version is a semver range — not `:latest`

**Reactivity:**
- [ ] Every ConfigMap/Secret in `valuesFrom` or `substituteFrom` has `reconcile.fluxcd.io/watch: Enabled`

**ResourceSet (if present):**
- [ ] Template delimiters are `<< inputs.field >>` — not `{{ inputs.field }}`
- [ ] `layerSelector.mediaType` set on OCIRepository used for Helm

**Repository structure:**
- [ ] `clusters/`, `apps/`, `infrastructure/` clearly separated
- [ ] `flux-system/` lives under `clusters/<cluster>/`
- [ ] No overlapping Kustomization paths
- [ ] Error-severity Alert + Provider configured for production
- [ ] Receiver configured for immediate reconciliation on Git push

---

### Phase 5 — Security Review

```bash
# Unencrypted Secrets
grep -rn "kind: Secret" . --include="*.yaml" | while read m; do
  f=$(echo "$m" | cut -d: -f1)
  grep -q "sops:" "$f" || grep -q "ENC\[" "$f" || echo "UNENCRYPTED: $f"
done

# Hardcoded credentials
grep -rn -e "password:" -e "token:" -e "apiKey:" -e "_SECRET=" -e "ACCESS_KEY=" --include="*.yaml" .

# Insecure sources
grep -rn "insecure: true" . --include="*.yaml"

# Cloud registries without Workload Identity
grep -rn "ecr\.\|\.gcr\.io\|\.azurecr\.io" . --include="*.yaml" -B5 | grep -v "provider:"

# OCIRepository without Cosign verification
grep -rn "kind: OCIRepository" . --include="*.yaml" -A20 | grep -v "verify:"

# cluster-admin bindings
grep -rn "cluster-admin" . --include="*.yaml"

# Image automation pushing to main
grep -rn "kind: ImageUpdateAutomation" . --include="*.yaml" -A20 | grep "branch: main\|branch: master"
```

Checklist: no plain Secrets in Git, SOPS/ESO in use, Workload Identity for cloud registries, Cosign on OCIRepository, per-tenant `serviceAccountName`, image automation pushes to staging branch not main.

---

### Phase 6 — Report

Produce a markdown report:

1. **Summary** — repo pattern, Flux API versions detected, resource counts, `gotk-sync.yaml` present (flag if yes)
2. **Directory structure** — tree of key directories
3. **Validation results** — YAML syntax, kustomize build, schema validation
4. **API compliance** — deprecated versions found with replacements
5. **Best practices** — per-category pass/fail/warning
6. **Security** — per-category findings

**Recommendations** grouped by severity:

**Critical** (must fix before production)
- Plain secrets in Git
- Deprecated API versions that will stop working on next Flux upgrade

**Warning** (should fix)
- Missing `prune: true` on Kustomizations
- HelmRelease using legacy remediation strategy
- Missing `reconcile.fluxcd.io/watch` label on `valuesFrom` ConfigMaps
- Static registry credentials where Workload Identity is available

**Info** (improvement opportunities)
- Migrate from `flux bootstrap` to Flux Operator
- Enable drift detection on HelmReleases
- Add Cosign verification to OCIRepository sources

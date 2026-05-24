# FluxCD API Migration Guide

Flux has removed deprecated API versions in two waves. Running any `v1beta1` or `v1beta2` resource in a post-removal cluster will cause reconciliation failures.

---

## What was removed and when

### Flux v2.7 — `v1beta1` removals

All `v1beta1` versions across every toolkit were removed:

| API group | Removed version |
|---|---|
| `source.toolkit.fluxcd.io` | `v1beta1` (GitRepository, HelmRepository, HelmChart, Bucket, OCIRepository) |
| `kustomize.toolkit.fluxcd.io` | `v1beta1` (Kustomization) |
| `helm.toolkit.fluxcd.io` | `v1beta1` (HelmRelease) |
| `image.toolkit.fluxcd.io` | `v1beta1` (ImageRepository, ImagePolicy, ImageUpdateAutomation) |
| `notification.toolkit.fluxcd.io` | `v1beta1` (Provider, Alert, Receiver) |

### Flux v2.8 — `v1beta2` removals

All `v1beta2` versions were removed:

| API group | Removed version |
|---|---|
| `source.toolkit.fluxcd.io` | `v1beta2` (GitRepository, HelmRepository, HelmChart, Bucket, OCIRepository) |
| `kustomize.toolkit.fluxcd.io` | `v1beta2` (Kustomization) |
| `helm.toolkit.fluxcd.io` | `v1beta2` (HelmRelease) |
| `notification.toolkit.fluxcd.io` | `v1beta2` (Provider, Alert) |

### Current stable API versions (post-v2.8)

| Kind | Current apiVersion |
|---|---|
| GitRepository, OCIRepository, HelmRepository, HelmChart, Bucket | `source.toolkit.fluxcd.io/v1` |
| Kustomization | `kustomize.toolkit.fluxcd.io/v1` |
| HelmRelease | `helm.toolkit.fluxcd.io/v2` |
| Provider, Alert | `notification.toolkit.fluxcd.io/v1beta3` |
| Receiver | `notification.toolkit.fluxcd.io/v1` |
| ImageRepository, ImagePolicy, ImageUpdateAutomation | `image.toolkit.fluxcd.io/v1beta2` (for non-gitless) |
| FluxInstance, ResourceSet, ResourceSetInputProvider | `fluxcd.controlplane.io/v1` |

---

## Detect deprecated APIs before migrating

```bash
# Preview all files that need updating (dry-run — no changes written)
flux migrate -f . --dry-run

# Or use the official audit script from fluxcd/agent-skills
git clone --depth=1 https://github.com/fluxcd/agent-skills.git /tmp/flux-agent-skills
bash /tmp/flux-agent-skills/skills/gitops-repo-audit/scripts/check-deprecated.sh -d .
```

`flux migrate --dry-run` exits 1 if deprecated versions are found. Use in CI to block merges.

---

## Migration path — CLI-based (3 steps)

Use when managing Flux via `flux bootstrap`.

### Step 1 — Migrate Git manifests

```bash
# Clone your GitOps repo
git clone https://github.com/my-org/fleet-manifests.git
cd fleet-manifests

# Rewrite deprecated apiVersions in all YAML files
flux migrate -f .

# Review the diff
git diff

# Commit and push
git add -A
git commit -m "chore: migrate Flux APIs to v2.8+ versions"
git push

# Trigger reconciliation
flux reconcile ks flux-system --with-source
```

### Step 2 — Migrate in-cluster resources

```bash
# Update resources already stored in etcd
# Safe to run multiple times — idempotent
flux migrate

# For a specific cluster context
flux migrate --context my-cluster --kubeconfig ~/.kube/config
```

### Step 3 — Upgrade Flux components

```bash
# Re-run your original bootstrap command with the new version
flux bootstrap github \
  --owner=my-org \
  --repository=fleet-manifests \
  --branch=main \
  --path=clusters/production

# Verify
flux check
```

---

## Migration path — Flux Operator-based (3 steps)

Use when managing Flux via `FluxInstance`.

### Step 1 — Upgrade Flux Operator

```bash
helm upgrade flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --version ">=0.43.0"
```

### Step 2 — Migrate Git manifests

Same as CLI Step 1 — run `flux migrate -f .` in your GitOps repo, commit, push.

### Step 3 — Update FluxInstance target version

```yaml
apiVersion: fluxcd.controlplane.io/v1
kind: FluxInstance
metadata:
  name: flux
  namespace: flux-system
spec:
  distribution:
    version: "2.8.x"    # or "2.x" to track latest
```

The Flux Operator automatically handles in-cluster API migrations when the version target is updated.

---

## Post-migration validation

```bash
# Validate all manifests against current Flux OpenAPI schemas
git clone --depth=1 https://github.com/fluxcd/agent-skills.git /tmp/flux-agent-skills
bash /tmp/flux-agent-skills/skills/gitops-repo-audit/scripts/validate.sh -d .

# Check Flux component health
flux check

# Check all sources and kustomizations
flux get all -A
```

---

## CI gate — block deprecated API merges

Add to your GitHub Actions workflow:

```yaml
- name: Check for deprecated Flux APIs
  run: |
    flux migrate -f . --dry-run
    if [ $? -ne 0 ]; then
      echo "Deprecated Flux API versions found — run 'flux migrate -f .' to fix"
      exit 1
    fi
```

---

## Common issues after migration

| Symptom | Cause | Fix |
|---|---|---|
| `no matches for kind "HelmRelease" in version "helm.toolkit.fluxcd.io/v2beta2"` | YAML not migrated | Run `flux migrate -f .` |
| Resources stuck after `flux migrate` | Cached schema in kubeconfig | Run `rm -rf ~/.kube/cache` |
| `flux check` shows outdated components | Components not upgraded | Re-run bootstrap or update FluxInstance version |
| `flux migrate` shows no changes but errors persist | In-cluster resources not migrated | Run `flux migrate` (without `-f .`) to update etcd |

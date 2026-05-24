# FluxCD Security Audit Checklist

Use this checklist when reviewing a GitOps repository for security posture. Run all scans regardless of earlier findings — issues compound.

---

## Secrets management

Acceptable strategies: **SOPS**, **External Secrets Operator (ESO)**, **Sealed Secrets**. Any `kind: Secret` manifest that is none of these is a leak.

**Detection:**

```bash
# Find unencrypted Secrets — no SOPS metadata and no ENC[ values
grep -rn "kind: Secret" . | grep -v "SealedSecret\|ExternalSecret" | while read match; do
  file=$(echo "$match" | cut -d: -f1)
  if ! grep -q "sops:" "$file" && ! grep -q "ENC\[" "$file"; then
    echo "UNENCRYPTED SECRET: $file"
  fi
done

# Find secretGenerator with plaintext in kustomization.yaml
grep -rn "secretGenerator\|literals:\|envs:\|files:" kustomization.yaml

# Find configMapGenerator with credential-like values
grep -rn "configMapGenerator" . -A 10 | grep -iE "password|token|secret|key|credential"
```

**Flags:**
- `kind: Secret` without `sops:` metadata and without `ENC[` prefixed values → **CRITICAL**
- `secretGenerator` with `literals:` or `envs:` containing plaintext credentials → **CRITICAL**
- `configMapGenerator` with credential-like values → **WARNING**

---

## Hardcoded credentials

Scan `spec.values` in HelmReleases, `spec.postBuild.substitute` in Kustomizations, ConfigMap `data:` fields, and `kustomization.yaml` generators.

```bash
# Credential patterns in YAML values
grep -rn \
  -e "password:" \
  -e "token:" \
  -e "apiKey:" \
  -e "api_key:" \
  -e "_SECRET=" \
  -e "ACCESS_KEY=" \
  -e "SECRET_KEY=" \
  -e "PRIVATE_KEY=" \
  --include="*.yaml" .

# Specific Flux locations to check
grep -rn "spec.values\|postBuild.substitute\|substitute:" . --include="*.yaml" -A 20 | \
  grep -iE "password|token|secret|key|credential"
```

---

## Source authentication

```bash
# Sources with insecure TLS — should never appear in production
grep -rn "insecure: true" . --include="*.yaml"

# Cloud registry sources without Workload Identity
# ECR, GCR, ACR should use .spec.provider, not .spec.secretRef
grep -rn "ecr\.\|\.gcr\.io\|\.azurecr\.io" . --include="*.yaml" -B 5 | grep -v "provider:"

# Private sources missing authentication
grep -rn "kind: GitRepository\|kind: OCIRepository\|kind: HelmRepository" . --include="*.yaml" -A 10 | \
  grep -v "secretRef\|provider:\|public"
```

**Flags:**
- `insecure: true` on any source → **CRITICAL**
- Cloud registry (ECR/GCR/ACR) source without `.spec.provider` (Workload Identity) → **WARNING** — static credentials rotate; WI does not
- Private source without `secretRef` and without a cloud provider → **WARNING**

---

## OCI supply chain

```bash
# Production OCIRepositories without Cosign verification
grep -rn "kind: OCIRepository" . --include="*.yaml" -A 20 | grep -v "verify:"

# HelmRepository with type: oci — migrate to OCIRepository
grep -rn "type: oci" . --include="*.yaml"

# Mutable tags in production OCIRepositories
grep -rn "tag: latest\|ref:.*latest" . --include="*.yaml"
```

**Flags:**
- `OCIRepository` without `spec.verify.provider: cosign` in production → **WARNING**
- `HelmRepository` with `type: oci` → **WARNING** — migrate to `OCIRepository` (no Cosign support on HelmRepository OCI)
- `ref: tag: latest` in production → **WARNING** — use semver or digest refs

---

## Multi-tenancy and RBAC

```bash
# ClusterRoleBindings for application service accounts — should be RoleBindings
grep -rn "kind: ClusterRoleBinding" . --include="*.yaml" -A 10 | grep -v "flux\|system"

# cluster-admin bindings
grep -rn "cluster-admin" . --include="*.yaml"

# Cross-namespace source references — tenant A referencing tenant B's source
grep -rn "sourceRef:" . --include="*.yaml" -A 3 | grep "namespace:" | \
  grep -v "flux-system"
```

**Flags:**
- `cluster-admin` binding for application service accounts → **CRITICAL**
- `ClusterRoleBinding` where `RoleBinding` would suffice → **WARNING**
- Cross-namespace `sourceRef` where `namespace` differs from owning resource → **WARNING** — breaks tenant isolation
- Kustomization without `spec.serviceAccountName` in a multi-tenant setup → **WARNING**

---

## Network policies

```bash
# Check FluxInstance networkPolicy setting
grep -rn "networkPolicy:" . --include="*.yaml"

# Check if application namespaces have NetworkPolicy resources
for ns_dir in apps/*/; do
  if ! find "$ns_dir" -name "*.yaml" -exec grep -l "kind: NetworkPolicy" {} \; | grep -q .; then
    echo "WARNING: No NetworkPolicy in $ns_dir"
  fi
done
```

**Flags:**
- `FluxInstance` with `cluster.networkPolicy: false` (default is `true`) → **WARNING**
- Application namespaces in multi-tenant clusters without `NetworkPolicy` → **WARNING**

---

## Image automation security

```bash
# Push credentials — check if same secret used for pull and push
grep -rn "kind: ImageUpdateAutomation" . --include="*.yaml" -A 20 | grep "secretRef"

# Push branch — should not be main/master directly
grep -rn "kind: ImageUpdateAutomation" . --include="*.yaml" -A 20 | grep "branch:"

# Tag filter restrictions
grep -rn "kind: ImagePolicy" . --include="*.yaml" -A 20 | grep -v "filterTags\|semver"
```

**Flags:**
- Image automation pushing directly to `main` or `master` → **WARNING** — push to a feature branch to enable PR review
- Same secret for pull (read) and push (write) credentials → **WARNING** — use separate secrets
- `ImagePolicy` without `filterTags.pattern` or `semver` range → **INFO** — any tag can be promoted

---

## Quick grep reference

| What to find | Pattern |
|---|---|
| Unencrypted Secrets | `kind: Secret` without `sops:` or `ENC[` |
| Hardcoded passwords | `password:`, `token:`, `apiKey:`, `_SECRET=`, `ACCESS_KEY=` |
| Insecure sources | `insecure: true` |
| Cloud registries without WI | `ecr.`, `.gcr.io`, `.azurecr.io` without `.spec.provider` |
| Cross-namespace source refs | `sourceRef:` blocks where `namespace:` differs from owner |
| OCI without Cosign | `kind: OCIRepository` without `verify:` block |
| Cluster-admin abuse | `cluster-admin` in non-system RoleBindings |
| Deprecated OCI HelmRepo | `type: oci` on a `HelmRepository` |
| Direct main push | `ImageUpdateAutomation` with `branch: main` or `branch: master` |

---

## Automated security scan

Run the full audit using the official Flux repo audit scripts:

```bash
git clone --depth=1 https://github.com/fluxcd/agent-skills.git /tmp/flux-agent-skills

# Phase 2 — manifest validation (catches schema violations)
bash /tmp/flux-agent-skills/skills/gitops-repo-audit/scripts/validate.sh -d .

# Phase 3 — deprecated API check
bash /tmp/flux-agent-skills/skills/gitops-repo-audit/scripts/check-deprecated.sh -d .

# Phase 5 — security grep patterns (run manually from above)
```

> The `validate.sh` script requires `yq >= 4.50`, `kustomize >= 5.8`, and `kubeconform >= 0.7`. It uses the Flux OpenAPI schemas bundled in the agent-skills repo to validate all CRDs.

# Flux Reference

## Contents

- Scope
- Controller and CRD reference
- Source selection
- Repository patterns
- Reconciliation model
- Promotion model
- Safety rules
- Flux Operator and FluxInstance
- ResourceSet and ResourceSetInputProvider
- Gitless (OCI-based) delivery
- Reactivity: reconcile.fluxcd.io/watch
- Common mistakes
- Image automation (Git-based and Gitless)

## Scope

Use Flux for:

- Cluster add-ons
- Application delivery
- Helm release management
- Kustomize overlays per cluster or environment

Flux should consume a prepared cluster. Bootstrap the cluster and its cloud prerequisites with Terraform unless there is a strong reason to use another control plane.

## Controller and CRD reference

| Kind | apiVersion | Controller |
|---|---|---|
| `FluxInstance` | `fluxcd.controlplane.io/v1` | flux-operator |
| `ResourceSet` | `fluxcd.controlplane.io/v1` | flux-operator |
| `ResourceSetInputProvider` | `fluxcd.controlplane.io/v1` | flux-operator |
| `GitRepository` | `source.toolkit.fluxcd.io/v1` | source-controller |
| `OCIRepository` | `source.toolkit.fluxcd.io/v1` | source-controller |
| `HelmRepository` | `source.toolkit.fluxcd.io/v1` | source-controller |
| `HelmChart` | `source.toolkit.fluxcd.io/v1` | source-controller |
| `Bucket` | `source.toolkit.fluxcd.io/v1` | source-controller |
| `ArtifactGenerator` | `source.extensions.fluxcd.io/v1beta1` | source-controller |
| `Kustomization` | `kustomize.toolkit.fluxcd.io/v1` | kustomize-controller |
| `HelmRelease` | `helm.toolkit.fluxcd.io/v2` | helm-controller |
| `Provider` | `notification.toolkit.fluxcd.io/v1beta3` | notification-controller |
| `Alert` | `notification.toolkit.fluxcd.io/v1beta3` | notification-controller |
| `Receiver` | `notification.toolkit.fluxcd.io/v1` | notification-controller |
| `ImageRepository` | `image.toolkit.fluxcd.io/v1beta2` | image-reflector-controller |
| `ImagePolicy` | `image.toolkit.fluxcd.io/v1beta2` | image-reflector-controller |
| `ImageUpdateAutomation` | `image.toolkit.fluxcd.io/v1beta1` | image-automation-controller |

## Source selection

| Scenario | Use |
|---|---|
| Git repo with YAML / Kustomize overlays | `GitRepository` |
| OCI artifact (manifests, configs) | `OCIRepository` |
| Helm chart from OCI registry (recommended) | `OCIRepository` with `layerSelector.mediaType` |
| Helm chart from HTTPS repository | `HelmRepository` |
| S3 / GCS / MinIO bucket | `Bucket` |
| Monorepo — split one Git source into multiple artifact streams | `ArtifactGenerator` |

**Kustomization vs HelmRelease:**
- Plain YAML / Kustomize overlays → `Kustomization`
- Helm chart → `HelmRelease`

**ResourceSet vs Kustomization:**
- One fixed deployment of manifests → `Kustomization`
- Same template applied to N inputs (tenants, environments) → `ResourceSet`

## Repository patterns

Common layout:

```text
clusters/
  prod/
  staging/
apps/
  base/
  overlays/
infrastructure/
  controllers/
  add-ons/
```

- `clusters/` defines what each cluster reconciles.
- `apps/` defines application or service workloads.
- `infrastructure/` contains in-cluster platform components such as ingress, cert-manager, external-dns, or observability stacks.

## Reconciliation model

Resource flow:

```
Sources → Artifacts → Appliers → Managed Resources → Notifications
```

- Keep reconciliation pull-based from Git.
- Pin chart and image versions intentionally.
- Prefer small, well-named `Kustomization` boundaries with clear dependencies.
- Use `dependsOn`, health checks, and intervals deliberately rather than a single large root object.

### GitRepository + Kustomization

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: my-app
  namespace: flux-system
spec:
  interval: 5m
  url: https://github.com/org/my-app.git
  ref:
    branch: main
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: my-app
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: my-app
  path: ./deploy/production
  prune: true
  wait: true
  timeout: 5m
```

## Promotion model

- Promote by changing image tags, chart versions, or overlay refs in Git.
- Keep environment overlays minimal; shared defaults belong in base definitions.
- For multi-cluster fleets, separate cluster-specific settings from app version promotion.

## Safety rules

- Do not patch resources manually in-cluster and call that the deployed state.
- Keep secrets out of plain Git unless encrypted and operationally justified.
- Ensure controllers that need cloud access use workload identity rather than static keys where possible.
- Treat Flux as the last-mile reconciler, not as the place to invent environment-specific business logic.

## Flux Operator and FluxInstance

The Flux Operator manages the full lifecycle of Flux controllers via a `FluxInstance` CRD — installation, configuration, upgrades, and health reporting.

**Rules:**
- Only one `FluxInstance` per cluster, and it must be named `flux`.
- The operator exposes a `FluxReport` resource for cluster-wide reconciliation health.

### FluxInstance with gitless OCI sync (recommended)

```yaml
apiVersion: fluxcd.controlplane.io/v1
kind: FluxInstance
metadata:
  name: flux
  namespace: flux-system
spec:
  distribution:
    version: "2.x"
    registry: "ghcr.io/fluxcd"
  sync:
    kind: OCIRepository
    url: "oci://ghcr.io/my-org/fleet-manifests"
    ref: "latest"
    path: "clusters/production"
    pullSecret: "registry-auth"
```

### Check FluxReport health

```bash
kubectl get fluxreport flux -n flux-system -o yaml
```

### Install Flux Operator

```bash
helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace
```

## ResourceSet and ResourceSetInputProvider

Use `ResourceSet` to apply the same template to N inputs (tenants, environments, services) without duplicating Kustomization or HelmRelease manifests.

**Template delimiters:** `<< inputs.field >>` — not `{{ }}`.

```yaml
apiVersion: fluxcd.controlplane.io/v1
kind: ResourceSet
metadata:
  name: tenant-deployments
  namespace: flux-system
spec:
  inputsFrom:
    - kind: ResourceSetInputProvider
      name: tenant-tags
  resources:
    - apiVersion: kustomize.toolkit.fluxcd.io/v1
      kind: Kustomization
      metadata:
        name: "<< inputs.tenant >>-app"
        namespace: flux-system
      spec:
        interval: 10m
        prune: true
        sourceRef:
          kind: OCIRepository
          name: "<< inputs.tenant >>-manifests"
        path: ./deploy
```

### ResourceSetInputProvider — OCIArtifactTag (gitless image automation)

```yaml
apiVersion: fluxcd.controlplane.io/v1
kind: ResourceSetInputProvider
metadata:
  name: tenant-tags
  namespace: flux-system
spec:
  type: OCIArtifactTag
  url: "oci://ghcr.io/my-org/tenant-app"
  filter:
    semver: "1.x"
  interval: 5m
  secretRef:
    name: registry-auth
```

## Gitless (OCI-based) delivery

The gitless model pushes manifests as OCI artifacts to a container registry. Flux pulls from the registry — no Git credentials on clusters, artifacts are immutable and can be signed.

**Why prefer gitless for Flux Operator deployments:**
- No Git polling lag
- No bot credentials on clusters
- Artifacts are immutable and signable (Cosign)
- Works natively with `FluxInstance.spec.sync.kind: OCIRepository`

### Push manifests as OCI artifact (CI side)

```bash
flux push artifact oci://ghcr.io/my-org/fleet-manifests:latest \
  --path=./clusters/production \
  --source="$(git config --get remote.origin.url)" \
  --revision="$(git rev-parse HEAD)"
```

### OCIRepository source

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: fleet-manifests
  namespace: flux-system
spec:
  interval: 5m
  url: oci://ghcr.io/my-org/fleet-manifests
  ref:
    tag: latest
  secretRef:
    name: registry-auth
```

### HelmRelease from OCI (recommended over HTTPS)

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: cert-manager-chart
  namespace: cert-manager
spec:
  interval: 1h
  url: oci://quay.io/jetstack/charts/cert-manager
  layerSelector:
    mediaType: "application/vnd.cncf.helm.chart.content.v1.tar+gzip"
    operation: copy
  ref:
    semver: "1.x"
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cert-manager
  namespace: cert-manager
spec:
  interval: 1h
  chartRef:
    kind: OCIRepository
    name: cert-manager-chart
  install:
    strategy:
      name: RetryOnFailure
      retryInterval: 5m
```

## Reactivity: reconcile.fluxcd.io/watch

Adding the label `reconcile.fluxcd.io/watch: Enabled` to a ConfigMap or Secret causes any Kustomization or HelmRelease that references it via `substituteFrom` or `valuesFrom` to reconcile immediately when that resource changes — bypassing the normal poll interval.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: flux-system
  labels:
    reconcile.fluxcd.io/watch: Enabled   # triggers immediate reconciliation on change
data:
  APP_VERSION: "1.4.2"
```

Use this label on every ConfigMap or Secret referenced in `substituteFrom` or `valuesFrom`.

## Common mistakes

| Mistake | Correct approach |
|---|---|
| Using `{{ inputs.field }}` in ResourceSet templates | Use `<< inputs.field >>` |
| Setting both `spec.chart.spec` and `spec.chartRef` on a HelmRelease | These are mutually exclusive — use `spec.chartRef` for OCI, `spec.chart.spec` for HTTPS |
| Multiple `FluxInstance` resources in a cluster | Only one, must be named `flux` |
| Using `RemediateOnFailure` or `install.remediation.retries` | Use `install.strategy.name: RetryOnFailure` |
| `OCIRepository` for a Helm chart without `layerSelector` | Set `layerSelector.mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip` |
| Missing `reconcile.fluxcd.io/watch: Enabled` on `substituteFrom`/`valuesFrom` ConfigMaps | Add the label so changes trigger immediate reconciliation |
| `gotk-sync.yaml` in repo root | Indicates `flux bootstrap` install — migrate to Flux Operator for lifecycle management |

## Image automation

Flux supports two image automation models. Use the gitless model for Flux Operator deployments; use the Git-based model when Git is the canonical version record and PR-based approval is required.

### Comparison

| Dimension | Git-based | Gitless (OCIArtifactTag) |
|---|---|---|
| How version flows | Flux commits updated tag back to Git | CI pushes new OCI artifact tag; Flux ResourceSet reads it |
| Git credentials on cluster | Yes (deploy key with write access) | No |
| Audit trail | Git commit history | OCI registry tag history |
| PR approval | Supported (push to branch, open PR) | Not applicable — version is the artifact tag |
| Recommended for | Flux bootstrap installs, PR-gated promotion | Flux Operator deployments, fleet management |

### Git-based image automation

Flux image automation watches a container registry and commits updated image tags back to Git. The Git commit then triggers normal reconciliation.

#### Components

| Resource | Purpose |
|---|---|
| `ImageRepository` | Polls a container registry for available tags |
| `ImagePolicy` | Selects which tag to deploy using semver, alphabetical, or numerical rules |
| `ImageUpdateAutomation` | Commits the selected tag back to the GitOps branch |

#### Setup

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: my-app
  namespace: flux-system
spec:
  image: ghcr.io/your-org/my-app
  interval: 5m
  secretRef:
    name: registry-credentials
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: my-app
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: my-app
  policy:
    semver:
      range: ">=1.0.0 <2.0.0"
---
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        email: fluxcdbot@users.noreply.github.com
        name: fluxcdbot
      messageTemplate: 'chore: update {{range .Updated.Images}}{{println .}}{{end}}'
    push:
      branch: main
  update:
    path: ./clusters/production
    strategy: Setters
```

Mark the image field in the deployment manifest:

```yaml
containers:
  - name: my-app
    image: ghcr.io/your-org/my-app:1.0.0  # {"$imagepolicy": "flux-system:my-app"}
```

### Gitless image automation

CI publishes a new OCI artifact tag. A `ResourceSetInputProvider` of type `OCIArtifactTag` polls the registry and feeds the selected tag into a `ResourceSet`, which generates the Kustomization or HelmRelease with the new version — no Git commit, no bot credentials.

```yaml
apiVersion: fluxcd.controlplane.io/v1
kind: ResourceSetInputProvider
metadata:
  name: app-image-tag
  namespace: flux-system
spec:
  type: OCIArtifactTag
  url: "oci://ghcr.io/my-org/my-app"
  filter:
    semver: "1.x"
  interval: 5m
  secretRef:
    name: registry-auth
---
apiVersion: fluxcd.controlplane.io/v1
kind: ResourceSet
metadata:
  name: my-app
  namespace: flux-system
spec:
  inputsFrom:
    - kind: ResourceSetInputProvider
      name: app-image-tag
  resources:
    - apiVersion: kustomize.toolkit.fluxcd.io/v1
      kind: Kustomization
      metadata:
        name: my-app
        namespace: flux-system
      spec:
        interval: 10m
        prune: true
        sourceRef:
          kind: OCIRepository
          name: my-app-manifests
        postBuild:
          substitute:
            APP_IMAGE_TAG: "<< inputs.tag >>"
```

### Registry authentication

Create a `docker-registry` Secret for any private registry:

```bash
kubectl create secret docker-registry registry-credentials \
  --namespace=flux-system \
  --docker-server=ghcr.io \
  --docker-username=<username> \
  --docker-password=<token>
```

**Registry-specific notes:**

| Registry | Token type | Expiry |
|---|---|---|
| GitHub Container Registry (GHCR) | Personal Access Token or GitHub App token | No expiry for PAT; App tokens expire — automate refresh |
| AWS ECR | Temporary token via `aws ecr get-login-password` | 12 hours — requires automated refresh (CronJob or `aws-ecr-credential-helper`) |
| Azure Container Registry (ACR) | Service principal secret or Workload Identity | SP secrets expire based on policy; prefer Workload Identity |
| Google Artifact Registry (GAR) | Service account key or Workload Identity | SA keys don't expire but should be rotated; prefer Workload Identity |
| Docker Hub | Access token | No expiry; rate limiting applies to anonymous pulls — always authenticate |

For any registry that issues short-lived tokens, automate the Secret refresh before expiry.

### Troubleshooting image automation

```bash
# Check ImageRepository is scanning successfully
kubectl -n flux-system describe imagerepository my-app

# Check what tag the policy selected
kubectl -n flux-system get imagepolicy my-app \
  -o jsonpath='{.status.latestImage}'

# Check automation controller logs
kubectl -n flux-system logs deploy/image-automation-controller | tail -50

# Check if the Git commit was pushed
kubectl -n flux-system describe imageupdateautomation flux-system
```

**Common failures:**

| Symptom | Cause | Fix |
|---|---|---|
| `ImageRepository` not ready, auth error | Registry credentials missing, wrong, or expired | Recreate the `registry-credentials` Secret with a valid token; check registry-specific expiry |
| `ImagePolicy` shows no `latestImage` | No tags match the policy range | Verify pushed tags conform to the semver range; check with `crane ls <image>` |
| No Git commit despite policy selecting a tag | Marker comment absent or malformed in manifest | Confirm the `# {"$imagepolicy": "..."}` comment is on the same line as `image:` |
| `ImageUpdateAutomation` failing to push | Deploy key lacks write access to the branch | Rotate the deploy key with write permission; or use a GitHub App token |

### Safety rules for image automation

- Set `push.branch` to a staging branch for staging clusters. For production, prefer committing to a release branch and merging via PR rather than direct `main` pushes.
- Restrict the automation's Git credentials to the specific path it manages — do not reuse the bootstrap deploy key.
- Use `semver` ranges rather than `latest` or `alphabetical` unless the registry enforces a reliable tag convention.
- For registries with short-lived tokens: automate Secret refresh on a schedule shorter than the token TTL.

# Flux Reference

## Contents

- Scope
- Repository patterns
- Reconciliation model
- Promotion model
- Safety rules

## Scope

Use Flux for:

- Cluster add-ons
- Application delivery
- Helm release management
- Kustomize overlays per cluster or environment

Flux should consume a prepared cluster. Bootstrap the cluster and its cloud prerequisites with Terraform unless there is a strong reason to use another control plane.

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

- Keep reconciliation pull-based from Git.
- Pin chart and image versions intentionally.
- Prefer small, well-named `Kustomization` boundaries with clear dependencies.
- Use `dependsOn`, health checks, and intervals deliberately rather than a single large root object.

## Promotion model

- Promote by changing image tags, chart versions, or overlay refs in Git.
- Keep environment overlays minimal; shared defaults belong in base definitions.
- For multi-cluster fleets, separate cluster-specific settings from app version promotion.

## Safety rules

- Do not patch resources manually in-cluster and call that the deployed state.
- Keep secrets out of plain Git unless encrypted and operationally justified.
- Ensure controllers that need cloud access use workload identity rather than static keys where possible.
- Treat Flux as the last-mile reconciler, not as the place to invent environment-specific business logic.

## Image automation

Flux image automation watches a container registry and commits updated image tags back to Git. The Git commit then triggers normal reconciliation — the *desired state* in the cluster is updated from Git, while workloads still pull image layers from the container registry at runtime.

### Components

| Resource | Purpose |
|---|---|
| `ImageRepository` | Polls a container registry for available tags |
| `ImagePolicy` | Selects which tag to deploy using semver, alphabetical, or numerical rules |
| `ImageUpdateAutomation` | Commits the selected tag back to the GitOps branch |

### Basic setup

```yaml
# Watch a container registry for new tags
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: my-app
  namespace: flux-system
spec:
  image: ghcr.io/your-org/my-app   # replace with your registry and image path
  interval: 5m
  # Remove secretRef if the registry is public
  secretRef:
    name: registry-credentials     # docker-registry Secret; see registry auth below
---
# Pin to the latest semver patch on 1.x
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
# Commit the selected tag back to the GitOps branch
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

Mark the image field in the deployment manifest so Flux knows which line to rewrite:

```yaml
containers:
  - name: my-app
    image: ghcr.io/your-org/my-app:1.0.0  # {"$imagepolicy": "flux-system:my-app"}
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

### Troubleshooting

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

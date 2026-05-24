# Image Automation with Flux

Status: Beta

Two side-by-side models for automating container image updates with Flux CD:

| Model | How it works | Best for |
|---|---|---|
| **Git-based** | Flux commits updated image tag to Git; normal reconciliation follows | PR-gated promotion, Git as canonical version record |
| **Gitless** | CI pushes OCI artifact with new tag; ResourceSetInputProvider picks it up; no Git commit | Flux Operator deployments, fleet management, no bot credentials |

## Git-based image automation

### Components

- `ImageRepository` — polls a container registry for available tags
- `ImagePolicy` — selects the tag to deploy (semver, alphabetical, numerical)
- `ImageUpdateAutomation` — commits the selected tag back to the GitOps branch

### Files

```text
image-automation/
└── git-based/
    ├── imagerepository.yaml
    ├── imagepolicy.yaml
    └── imageupdateautomation.yaml
```

### Setup

1. Apply the resources:
   ```bash
   kubectl apply -f git-based/
   ```

2. Mark the image field in your Deployment:
   ```yaml
   containers:
     - name: my-app
       image: ghcr.io/my-org/my-app:1.0.0  # {"$imagepolicy": "flux-system:my-app"}
   ```

3. Verify the policy selected a tag:
   ```bash
   kubectl -n flux-system get imagepolicy my-app \
     -o jsonpath='{.status.latestImage}'
   ```

### Safety rules

- Set `push.branch` to a staging branch — not `main` — for staging clusters
- Use a dedicated deploy key with write access only to the image automation path
- Use `semver` ranges, not `:latest`

---

## Gitless image automation (recommended for Flux Operator)

### Components

- `ResourceSetInputProvider` (type: `OCIArtifactTag`) — polls OCI registry for new tags
- `ResourceSet` — generates Kustomizations with `<< inputs.tag >>` substituted

### Files

```text
image-automation/
└── gitless/
    ├── resourcesetinputprovider.yaml
    └── resourceset.yaml
```

### How it works

1. CI builds and pushes a new image tag: `ghcr.io/my-org/my-app:1.4.2`
2. `ResourceSetInputProvider` detects the new tag (polls every 5m or via webhook)
3. `ResourceSet` regenerates the Kustomization with `APP_IMAGE_TAG: 1.4.2`
4. kustomize-controller applies the updated manifest — no Git commit required

### Verify

```bash
# Check the input provider is polling
kubectl describe resourcesetinputprovider app-image-tag -n flux-system

# Check the ResourceSet generated the Kustomization
kubectl get kustomization -l resourceset.fluxcd.io/name=my-app -A

# Check the generated Kustomization status
flux get kustomization my-app -n flux-system
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `ImageRepository` not ready, auth error | Registry credentials wrong or expired | Recreate `registry-credentials` Secret |
| `ImagePolicy` shows no `latestImage` | No tags match the semver range | Verify pushed tags with `crane ls <image>` |
| No Git commit despite policy selecting a tag | Missing `# {"$imagepolicy": ...}` marker | Add marker comment on same line as `image:` |
| `ImageUpdateAutomation` failing to push | Deploy key lacks write access | Rotate deploy key with write permission |
| `ResourceSetInputProvider` not detecting new tag | Wrong semver filter or auth issue | Check provider status and registry credentials |

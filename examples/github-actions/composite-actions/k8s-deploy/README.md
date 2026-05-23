# k8s-deploy

> Apply a Kubernetes manifest and wait for rollout to complete. The kubeconfig is written to a temp file with mode 600 and deleted after the job — even on failure.

Status: Stable

<!-- Run `/platform-skills:awesome-docs generate` on this file to add an animated architecture flow and lifecycle loop diagram. -->

## Quick start

```yaml
- uses: your-org/actions/k8s-deploy@v1
  with:
    kubeconfig: ${{ secrets.KUBECONFIG }}
    namespace: production
    manifest_path: deploy/app.yml
    deployment_name: my-app
```

---

## Architecture

```
Trigger: push to main / workflow_dispatch
        │
        ▼
┌─────────────────────────────────────────────────────┐
│  k8s-deploy composite action                         │
│                                                      │
│  1. Validate inputs                                  │
│  2. Install kubectl (or use cached version)          │
│  3. Decode base64 kubeconfig → tmp file (chmod 600) │
│     ::add-mask:: raw content immediately             │
│  4. kubectl apply -f <manifest_path> -n <namespace> │
│     (--dry-run=server if dry_run=true)               │
│  5. kubectl rollout status deployment/<name>         │
│     (skipped if deployment_name is empty)            │
│  6. Write job summary                                │
│  7. [post] Delete kubeconfig tmp file (always)      │
└─────────────────────────────────────────────────────┘
        │
        ▼
Kubernetes cluster — resources created/updated
```

---

## Inputs

| Input | Type | Required | Secret | Default | Description |
|---|---|---|---|---|---|
| `kubeconfig` | string | **Yes** | **Yes** | — | Base64-encoded kubeconfig |
| `namespace` | string | **Yes** | No | — | Target Kubernetes namespace |
| `manifest_path` | string | **Yes** | No | — | Path to manifest file or directory |
| `deployment_name` | string | No | No | `''` | Deployment to watch (`rollout status`) |
| `timeout` | string | No | No | `5m` | Rollout wait timeout (e.g. `5m`, `300s`) |
| `kubectl_version` | string | No | No | `v1.30.0` | kubectl version to install |
| `dry_run` | boolean | No | No | `false` | Validate without applying |

---

## Outputs

| Output | Description |
|---|---|
| `rollout_status` | `success`, `skipped`, or `failed` |
| `applied_resources` | Newline-separated list of resources created or updated |

---

## Variables and secrets

`kubeconfig` is the only secret. It must be base64-encoded before storing.

```
Cluster admin generates kubeconfig
        │
        │  base64 -w 0 ~/.kube/config
        ▼
GitHub secret: KUBECONFIG = <base64 string>
        │
        │  with:
        │    kubeconfig: ${{ secrets.KUBECONFIG }}
        ▼
inputs.kubeconfig
        │
        │  KUBECONFIG_CONTENT=$(echo "$INPUT" | base64 -d)
        │  echo "::add-mask::$KUBECONFIG_CONTENT"   ← masked immediately
        │  echo "$KUBECONFIG_CONTENT" > /tmp/kubeconfig-XXXXX
        │  chmod 600 /tmp/kubeconfig-XXXXX
        │  export KUBECONFIG=/tmp/kubeconfig-XXXXX
        ▼
kubectl apply ...    ← reads file, credentials never in command args
        │
        │  [always runs after job]
        ▼
rm -f /tmp/kubeconfig-XXXXX    ← cleanup
```

**What is logged vs what is masked:**

| Value | Logged? |
|---|---|
| `inputs.namespace` | ✅ Yes |
| `inputs.manifest_path` | ✅ Yes |
| `inputs.kubeconfig` (base64) | ❌ No — masked |
| Decoded kubeconfig content | ❌ No — masked immediately after decode |
| `cluster-info` URL | ✅ Yes (token/cert fields filtered) |
| kubectl apply output | ✅ Yes (resource names only) |

---

## Permissions

```yaml
permissions:
  contents: read   # checkout manifests
```

The kubeconfig itself provides Kubernetes RBAC access. Use a service account scoped to `apply` on the target namespace only:

```yaml
# Minimum Kubernetes RBAC for this action
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: github-actions-deploy
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["services", "configmaps"]
    verbs: ["get", "list", "create", "update", "patch"]
```

---

## Idempotency

**Idempotent** — `kubectl apply` is idempotent by design. Running twice on the same manifest produces the same cluster state. If the image tag and manifest are unchanged, the second run is a no-op.

---

## Concurrency (recommended)

```yaml
concurrency:
  group: deploy-${{ github.ref }}-${{ inputs.namespace }}
  cancel-in-progress: false   # never cancel an in-flight deploy
```

---

## Preparing the kubeconfig secret

```bash
# Option A — full kubeconfig (least privilege: restrict via RBAC in the cluster)
base64 -w 0 ~/.kube/config | gh secret set KUBECONFIG

# Option B — generate a minimal kubeconfig for a service account
kubectl create serviceaccount github-actions -n production
kubectl create rolebinding github-actions-deploy \
  --clusterrole=github-actions-deploy \
  --serviceaccount=production:github-actions \
  -n production

TOKEN=$(kubectl create token github-actions -n production --duration=87600h)
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

cat <<EOF | base64 -w 0 | gh secret set KUBECONFIG
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $CA
    server: $SERVER
  name: prod
contexts:
- context:
    cluster: prod
    namespace: production
    user: github-actions
  name: prod
current-context: prod
users:
- name: github-actions
  user:
    token: $TOKEN
EOF
```

---

## Full example

```yaml
name: Deploy to production

on:
  push:
    branches: [main]
    paths:
      - 'deploy/**'

permissions:
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production   # requires approval

    concurrency:
      group: deploy-production
      cancel-in-progress: false

    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - name: Deploy
        id: deploy
        uses: your-org/actions/k8s-deploy@v1
        with:
          kubeconfig: ${{ secrets.KUBECONFIG_PROD }}
          namespace: production
          manifest_path: deploy/
          deployment_name: my-app
          timeout: 10m

      - name: Report
        run: |
          echo "Rollout: ${{ steps.deploy.outputs.rollout_status }}"
          echo "Resources: ${{ steps.deploy.outputs.applied_resources }}"
```

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md)

# k8s-deploy

> Apply a Kubernetes manifest and wait for rollout to complete. Authenticates to EKS, AKS, or GKE via OIDC — no static kubeconfig secrets.

Status: Stable

<!-- Run `/platform-skills:awesome-docs generate` on this file to add an animated architecture flow and lifecycle loop diagram. -->

## Quick start

**EKS:**

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: actions/checkout@v4
  - uses: your-org/actions/k8s-deploy@v2
    with:
      cloud_provider: aws
      aws_role_arn: ${{ vars.AWS_DEPLOY_ROLE_ARN }}
      aws_cluster_name: my-cluster
      aws_region: us-east-1
      namespace: production
      manifest_path: deploy/app.yml
      deployment_name: my-app
```

**AKS:**

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: actions/checkout@v4
  - uses: your-org/actions/k8s-deploy@v2
    with:
      cloud_provider: azure
      azure_client_id: ${{ vars.AZURE_CLIENT_ID }}
      azure_tenant_id: ${{ vars.AZURE_TENANT_ID }}
      azure_subscription_id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      azure_cluster_name: my-cluster
      azure_resource_group: my-rg
      namespace: production
      manifest_path: deploy/app.yml
      deployment_name: my-app
```

**GKE:**

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: actions/checkout@v4
  - uses: your-org/actions/k8s-deploy@v2
    with:
      cloud_provider: gke
      gcp_workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER }}
      gcp_service_account: ${{ vars.GCP_SERVICE_ACCOUNT }}
      gcp_project: my-project
      gcp_cluster_name: my-cluster
      gcp_cluster_location: us-central1
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
┌─────────────────────────────────────────────────────────────────────┐
│  k8s-deploy composite action                                         │
│                                                                      │
│  1. Validate inputs (cloud_provider + cloud-specific required fields)│
│                                                                      │
│  2a. EKS:  configure-aws-credentials (OIDC)                         │
│            └─ aws eks update-kubeconfig                              │
│  2b. AKS:  azure/login (OIDC)                                       │
│            └─ az aks install-cli (kubelogin only)                   │
│            └─ az aks get-credentials + kubelogin convert-kubeconfig │
│  2c. GKE:  google-github-actions/auth (WIF)                         │
│            └─ get-gke-credentials                                   │
│                                                                      │
│  3. Install kubectl                                                  │
│  4. kubectl apply -f <manifest_path> -n <namespace>                 │
│     (--dry-run=server if dry_run=true)                               │
│  5. kubectl rollout status deployment/<name>                         │
│     (skipped if deployment_name is empty or dry_run=true)           │
│  6. Write job summary                                                │
└─────────────────────────────────────────────────────────────────────┘
        │
        ▼
Kubernetes cluster — resources created/updated
```

---

## Inputs

### Common

| Input | Type | Required | Default | Description |
|---|---|---|---|---|
| `cloud_provider` | string | **Yes** | — | `aws`, `azure`, or `gke` |
| `namespace` | string | **Yes** | — | Target Kubernetes namespace |
| `manifest_path` | string | **Yes** | — | Path to manifest file or directory |
| `deployment_name` | string | No | `''` | Deployment to watch (`rollout status`) |
| `timeout` | string | No | `5m` | Rollout wait timeout (e.g. `5m`, `300s`) |
| `kubectl_version` | string | No | `v1.30.0` | kubectl version to install |
| `dry_run` | boolean | No | `false` | Validate without applying |

### AWS / EKS

| Input | Required | Description |
|---|---|---|
| `aws_role_arn` | **Yes** | IAM role ARN to assume via OIDC |
| `aws_region` | No (default `us-east-1`) | EKS cluster region |
| `aws_cluster_name` | **Yes** | EKS cluster name |

### Azure / AKS

| Input | Required | Description |
|---|---|---|
| `azure_client_id` | **Yes** | App registration client ID (federated credential) |
| `azure_tenant_id` | **Yes** | Azure AD tenant ID |
| `azure_subscription_id` | **Yes** | Azure subscription ID |
| `azure_cluster_name` | **Yes** | AKS cluster name |
| `azure_resource_group` | **Yes** | Resource group containing the cluster |

### GCP / GKE

| Input | Required | Description |
|---|---|---|
| `gcp_workload_identity_provider` | **Yes** | WIF provider resource name — `projects/NUMBER/locations/global/workloadIdentityPools/POOL/providers/PROVIDER` |
| `gcp_service_account` | **Yes** | Service account email to impersonate |
| `gcp_project` | **Yes** | GCP project ID |
| `gcp_cluster_name` | **Yes** | GKE cluster name |
| `gcp_cluster_location` | **Yes** | Region (`us-central1`) or zone (`us-central1-a`) |

---

## Outputs

| Output | Description |
|---|---|
| `rollout_status` | `success`, `skipped`, or `failed` |
| `applied_resources` | Newline-separated list of resources created or updated |

---

## Required permissions

```yaml
permissions:
  id-token: write   # OIDC token exchange for all cloud providers
  contents: read
```

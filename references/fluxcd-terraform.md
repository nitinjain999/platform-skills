# FluxCD Terraform Bootstrap Reference

Bootstrap Flux Operator and a `FluxInstance` into a Kubernetes cluster via Terraform. Designed for clusters provisioned with Terraform where Flux takes over GitOps reconciliation after bootstrap.

---

## Ownership model

| Layer | Owns |
|---|---|
| **Terraform** | Ephemeral bootstrap: namespace, RBAC, mounted manifests, bootstrap Job |
| **Flux Operator** | Steady-state: all Flux resources once the Job completes |

Terraform creates an ephemeral Kubernetes `Job` that applies the FluxInstance manifest. After the Job succeeds, Flux owns itself and Terraform stops touching cluster state.

---

## Repository layout

```
repo/
├── terraform/              # Terraform root module
│   ├── main.tf
│   └── variables.tf
└── clusters/               # Flux fleet source of truth
    └── staging/
        └── flux-system/
            └── flux-instance.yaml
```

Since Terraform lives in a subdirectory, reference the repo root with `${path.root}/..` when loading manifests.

---

## Resource categories

### GitOps resources — create-once, owned by Flux

Applied once with **create-if-missing** semantics. After Flux bootstraps, it owns these:

| Input | Purpose |
|---|---|
| `instance_yaml` (required) | The FluxInstance manifest |
| `operator_chart` | Flux Operator Helm chart repo, version, values |
| `prerequisites.yamls` | Ordered manifests applied before FluxInstance |
| `prerequisites.charts` | Helm charts installed before Flux (e.g. cert-manager) |

### Managed resources — reconciled every bootstrap run

Server-side applied on every Job run:

| Input | Purpose |
|---|---|
| `secrets_yaml` | Multi-document Secret manifest |
| `runtime_info` | Key-value data published as `flux-runtime-info` ConfigMap |

> Managed resources are tracked in an inventory and garbage-collected when removed from input.

---

## Runtime info and variable substitution

When `managed_resources.runtime_info` is set, the Job:
1. Creates a `flux-runtime-info` ConfigMap with the provided key-value pairs
2. Substitutes `${variable}` references in all input manifests using `flux envsubst --strict`

```hcl
managed_resources = {
  runtime_info = {
    CLUSTER_REGION = "eu-west-1"
    ACCOUNT_ID     = "123456789012"
    ENVIRONMENT    = "staging"
  }
}
```

### Terraform and Git co-ownership of the same ConfigMap

Terraform and Git can each own separate fields in `flux-runtime-info` via SSA field ownership:

| Authority | Fields |
|---|---|
| Terraform | `CLUSTER_REGION`, `ACCOUNT_ID` (infra facts) |
| Git / Flux | `ARTIFACT_TAG`, `ENVIRONMENT`, `CLUSTER_NAME` (app facts) |

The Git-managed ConfigMap must include:

```yaml
metadata:
  annotations:
    kustomize.toolkit.fluxcd.io/ssa: "Merge"
```

This ensures kustomize-controller merges fields rather than replacing the whole object.

---

## Sync authentication

Match the Secret name to `spec.sync.pullSecret` (defaults to `flux-system`):

```hcl
managed_resources = {
  secrets_yaml = <<-EOT
    apiVersion: v1
    kind: Secret
    metadata:
      name: registry-auth
      namespace: flux-system
    type: kubernetes.io/dockerconfigjson
    stringData:
      .dockerconfigjson: '{"auths":{"ghcr.io":{"auth":"${base64encode("user:${var.ghcr_token}")}"}}}'
  EOT
}
```

**Auth options:**

| Method | Contents |
|---|---|
| Git PAT | `username`, `password` in `stringData` |
| GitHub App | `githubAppID`, `githubAppInstallationOwner`, `githubAppPrivateKey` — preferred over PATs |
| OCI registry | `kubernetes.io/dockerconfigjson` type |

> For OCI secrets embedded in YAML heredocs: single quotes inside JSON must be escaped — `replace(var.secret, "'", "''")`.

> Secret values never appear in Terraform state — only a SHA-256 hash is persisted.

---

## Node scheduling

Configure at three layers when using dedicated or tainted nodes:

```hcl
# 1. Bootstrap Job tolerations
job = {
  tolerations = [{
    key      = "dedicated"
    operator = "Equal"
    value    = "flux"
    effect   = "NoSchedule"
  }]
  host_network = false    # set true if CNI must be installed before pod networking
}

# 2. Flux Operator via operator_chart.values_yaml
operator_chart = {
  values_yaml = <<-EOT
    tolerations:
      - key: dedicated
        operator: Equal
        value: flux
        effect: NoSchedule
  EOT
}
```

```yaml
# 3. Flux controllers via FluxInstance spec.kustomize.patches
spec:
  kustomize:
    patches:
      - target:
          kind: Deployment
          name: kustomize-controller
        patch: |
          - op: add
            path: /spec/template/spec/tolerations
            value:
              - key: dedicated
                operator: Equal
                value: flux
                effect: NoSchedule
```

---

## Drift and revision

- The bootstrap Job reruns automatically when any input changes
- No changes → `terraform plan` shows zero diff
- Use `revision` (integer counter) to force a Job rerun without changing content
- Terraform-managed resources on the cluster are not tracked in state — the Job manages them

---

## Shared operator values file

A single `flux-operator-values.yaml` can serve both Terraform (bootstrap) and Flux (steady-state upgrades):

```hcl
operator_chart = {
  values_yaml = file("${path.root}/../flux-operator-values.yaml")
}
```

For bootstrap-specific overrides, use shallow `merge()` — note it **replaces entire top-level keys**, not nested fields.

---

## Debugging

```hcl
debug_on_failure = true   # relays Job logs on failure
```

Requires `bash`, `kubectl`, and the `hashicorp/null` provider in the execution environment.

```bash
# Check bootstrap Job status
kubectl get jobs -n flux-system
kubectl logs -n flux-system job/flux-bootstrap

# Check FluxInstance after bootstrap
kubectl get fluxinstance flux -n flux-system
kubectl get fluxreport flux -n flux-system -o yaml
```

---

## Full example

```hcl
module "flux_bootstrap" {
  source = "github.com/controlplaneio-fluxcd/terraform-flux-operator//modules/cluster"

  kubeconfig_path = "~/.kube/config"
  kubeconfig_context = "staging"

  gitops_resources = {
    instance_yaml = file("${path.root}/../clusters/staging/flux-system/flux-instance.yaml")
  }

  managed_resources = {
    runtime_info = {
      CLUSTER_NAME   = "staging"
      CLUSTER_REGION = var.region
      ENVIRONMENT    = "staging"
    }
    secrets_yaml = templatefile("${path.root}/templates/registry-secret.yaml", {
      token = var.ghcr_token
    })
  }
}
```

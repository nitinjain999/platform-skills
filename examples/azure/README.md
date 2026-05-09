Status: Stable

# Azure Examples

Production-ready Azure workload identity for AKS — federated credentials, no service principal secrets.

## Examples

| Example | Type | Description |
|---------|------|-------------|
| [workload-identity/main.tf](workload-identity/) | Terraform | Managed identity + federated credential for AKS pod |
| [workload-identity/serviceaccount.yaml](workload-identity/) | Kubernetes | Annotated ServiceAccount for workload identity binding |

## Quick Start

```bash
cd workload-identity
terraform init
terraform plan \
  -var="resource_group_name=my-rg" \
  -var="aks_cluster_name=my-aks" \
  -var="namespace=my-app" \
  -var="service_account_name=my-app-sa"
terraform apply

# Apply the annotated ServiceAccount
kubectl apply -f serviceaccount.yaml
```

## Key Patterns

### Workload Identity (no service principal secrets)

```hcl
# Federated credential binds managed identity to AKS ServiceAccount
resource "azurerm_federated_identity_credential" "app" {
  issuer  = data.azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
  audience = ["api://AzureADTokenExchange"]
}
```

```yaml
# ServiceAccount — annotated with client ID
metadata:
  annotations:
    azure.workload.identity/client-id: "<managed-identity-client-id>"
```

```yaml
# Pod spec — label triggers token injection
metadata:
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: my-app-sa
```

### Minimum RBAC

```hcl
resource "azurerm_role_assignment" "app_storage" {
  scope                = azurerm_storage_account.app.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}
```

### Tagging baseline

```hcl
locals {
  common_tags = { environment = var.environment, team = var.team, managed-by = "terraform" }
}
resource "azurerm_resource_group" "app" {
  tags = merge(local.common_tags, { service = "my-app" })
}
```

## Checklist

- [ ] No service principal client secrets — use workload identity federated credentials
- [ ] Federated credential subject pins to specific namespace and service account
- [ ] Pod spec includes `azure.workload.identity/use: "true"` label
- [ ] AKS cluster has `oidc_issuer_enabled = true` and `workload_identity_enabled = true`
- [ ] RBAC assignments use minimum required built-in roles
- [ ] All resources tagged with `environment`, `team`, `managed-by`

## See Also

- [references/azure.md](../../references/azure.md) — subscription model, AKS, RBAC, managed identities, tagging
- `/platform-skills:review` — production-readiness review of Azure Terraform resources

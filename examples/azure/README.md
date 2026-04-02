# Azure Examples

Status: committed file-level snippets for the handbook. Use these as building blocks rather than a complete standalone Azure platform example.

## Files

| File | What it shows |
|---|---|
| [workload-identity/main.tf](workload-identity/main.tf) | Managed identity, federated credential, and scoped role assignment for AKS workload identity |
| [workload-identity/serviceaccount.yaml](workload-identity/serviceaccount.yaml) | Kubernetes ServiceAccount annotated with the managed identity client ID |

## Patterns

### Internal load balancer

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-internal
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
    service.beta.kubernetes.io/azure-load-balancer-internal-subnet: "aks-internal-lb"
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: my-app
```

### ACR integration

```hcl
resource "azurerm_container_registry" "this" {
  name                = "myappregistry"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Premium"
  admin_enabled       = false
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
```

## Troubleshooting

### Workload identity not working
1. Verify `oidc_issuer_enabled = true` on the cluster
2. Check the federated credential subject matches the ServiceAccount namespace and name exactly
3. Verify the audience is `api://AzureADTokenExchange`
4. Confirm the pod's ServiceAccount has the `azure.workload.identity/client-id` annotation

### ACR pull failures
1. Verify the AKS kubelet identity has AcrPull on the registry
2. Check ACR network rules if using a private endpoint
3. Verify the image name includes the ACR FQDN

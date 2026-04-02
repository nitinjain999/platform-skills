# Azure Examples

This directory contains reference implementations for Azure best practices and common patterns.

## Examples

### 1. AKS Cluster with Azure CNI

```hcl
resource "azurerm_kubernetes_cluster" "this" {
  name                = "production-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = "production-aks"
  kubernetes_version  = "1.29"

  default_node_pool {
    name                = "system"
    node_count          = 3
    vm_size             = "Standard_D4s_v3"
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = true
    min_count           = 3
    max_count           = 10

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = "10.1.0.0/16"
    dns_service_ip    = "10.1.0.10"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  }

  azure_policy_enabled = true

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

### 2. Workload Identity for AKS

```hcl
# Enable workload identity
resource "azurerm_kubernetes_cluster" "this" {
  # ... other config
  
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
}

# Create user-assigned managed identity
resource "azurerm_user_assigned_identity" "workload" {
  name                = "my-app-identity"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
}

# Create federated credential
resource "azurerm_federated_identity_credential" "this" {
  name                = "my-app-federated"
  resource_group_name = azurerm_resource_group.this.name
  parent_id           = azurerm_user_assigned_identity.workload.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject             = "system:serviceaccount:my-app:my-app-sa"
}

# Grant permissions
resource "azurerm_role_assignment" "storage" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}
```

Kubernetes ServiceAccount:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  namespace: my-app
  annotations:
    azure.workload.identity/client-id: "<client-id>"
```

### 3. RBAC Best Practices

#### Custom Role Definition

```hcl
resource "azurerm_role_definition" "aks_operator" {
  name  = "AKS Operator"
  scope = azurerm_resource_group.this.id

  permissions {
    actions = [
      "Microsoft.ContainerService/managedClusters/read",
      "Microsoft.ContainerService/managedClusters/listClusterAdminCredential/action",
      "Microsoft.ContainerService/managedClusters/listClusterUserCredential/action",
      "Microsoft.ContainerService/managedClusters/agentPools/read"
    ]
    not_actions = []
  }

  assignable_scopes = [
    azurerm_resource_group.this.id
  ]
}
```

#### Role Assignment

```hcl
resource "azurerm_role_assignment" "aks_operator" {
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "AKS Operator"
  principal_id         = data.azuread_group.platform_team.object_id
}
```

### 4. Azure Policy for AKS

```hcl
resource "azurerm_kubernetes_cluster_extension" "policy" {
  name           = "azure-policy"
  cluster_id     = azurerm_kubernetes_cluster.this.id
  extension_type = "microsoft.policyinsights"
}

# Assign built-in policy initiative
resource "azurerm_resource_group_policy_assignment" "aks_baseline" {
  name                 = "aks-baseline"
  resource_group_id    = azurerm_resource_group.this.id
  policy_definition_id = "/providers/Microsoft.Authorization/policySetDefinitions/a8640138-9b0a-4a28-b8cb-1666c838647d"

  parameters = jsonencode({
    effect = {
      value = "audit"
    }
  })
}
```

### 5. Private AKS Cluster

```hcl
resource "azurerm_kubernetes_cluster" "private" {
  name                    = "private-aks"
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  dns_prefix              = "private-aks"
  private_cluster_enabled = true
  private_dns_zone_id     = azurerm_private_dns_zone.aks.id

  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    outbound_type     = "userDefinedRouting"  # Use Azure Firewall or NVA
  }

  # ... rest of config
}

resource "azurerm_private_dns_zone" "aks" {
  name                = "privatelink.${var.azure_region}.azmk8s.io"
  resource_group_name = azurerm_resource_group.this.name
}
```

### 6. Resource Tagging Strategy

```hcl
locals {
  common_tags = {
    Environment    = "production"
    Owner          = "platform-team@example.com"
    CostCenter     = "engineering"
    Application    = "my-app"
    DataClassification = "internal"
    ManagedBy      = "terraform"
    BackupRequired = "true"
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-production-eastus"
  location = "East US"
  tags     = local.common_tags
}
```

## Common Patterns

### Internal Load Balancer

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

### Azure Files Persistent Volume

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-files
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: azurefile-csi-premium
  resources:
    requests:
      storage: 100Gi
```

### Container Registry Integration

```hcl
resource "azurerm_container_registry" "this" {
  name                = "myappregistry"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Premium"
  admin_enabled       = false

  georeplications {
    location = "West Europe"
    tags     = local.common_tags
  }
}

# Grant AKS access to ACR
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
```

## Security Best Practices

### 1. Network Security Groups

```hcl
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks-nodes"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowVNetInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
}
```

### 2. Key Vault Secrets Provider

```hcl
resource "azurerm_kubernetes_cluster" "this" {
  # ... other config

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }
}

resource "azurerm_key_vault_access_policy" "aks" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].object_id

  secret_permissions = [
    "Get",
    "List"
  ]
}
```

### 3. Defender for Containers

```hcl
resource "azurerm_security_center_subscription_pricing" "defender_containers" {
  tier          = "Standard"
  resource_type = "Containers"
}

resource "azurerm_security_center_auto_provisioning" "this" {
  auto_provision = "On"
}
```

## Cost Optimization

### 1. Node Auto-scaling

```hcl
resource "azurerm_kubernetes_cluster_node_pool" "workloads" {
  name                  = "workloads"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = "Standard_D4s_v3"
  enable_auto_scaling   = true
  min_count             = 1
  max_count             = 20
  node_labels = {
    "workload" = "general"
  }
}
```

### 2. Spot Instances

```hcl
resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  name                  = "spot"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = "Standard_D4s_v3"
  priority              = "Spot"
  eviction_policy       = "Delete"
  spot_max_price        = -1  # Pay up to on-demand price
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = 10

  node_labels = {
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }

  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]
}
```

## Troubleshooting

### AKS Node Not Ready

1. Check node logs: `kubectl describe node <node-name>`
2. Verify network connectivity to Azure services
3. Check NSG rules aren't blocking required traffic
4. Verify managed identity has necessary permissions

### Workload Identity Not Working

1. Verify OIDC issuer enabled on cluster
2. Check federated credential subject matches ServiceAccount
3. Verify audience is `api://AzureADTokenExchange`
4. Check pod has correct ServiceAccount annotation

### ACR Pull Failures

1. Verify AKS kubelet identity has AcrPull role
2. Check ACR network rules if using private endpoint
3. Verify image name includes ACR FQDN
4. Check for image pull secrets if using admin credentials

## Further Reading

- [AKS Best Practices](https://learn.microsoft.com/azure/aks/best-practices)
- [Azure Security Baseline](https://learn.microsoft.com/security/benchmark/azure/)
- [Well-Architected Framework](https://learn.microsoft.com/azure/well-architected/)

---
name: azure
description: Azure identity (Workload Identity, OIDC, Entra ID), resource tagging, AKS platform patterns, RBAC scoping, and production-readiness review — with Terraform generation.
argument-hint: "[identity|tagging|aks|rbac|review] [description or Terraform snippet]"
title: "Azure Command"
sidebar_label: "azure"
custom_edit_url: null
---

# Azure Command

Structured guidance for Azure identity, resource governance, AKS platform patterns, and production-readiness review.

## Activation

```
/platform-skills:azure identity   # Workload Identity, OIDC federation, managed identities, Entra ID
/platform-skills:azure tagging    # common_tags pattern, Azure Policy enforce/remediate, AKS MC_ group
/platform-skills:azure aks        # AKS provisioning, add-ons, Flux/Argo bootstrap, node pools
/platform-skills:azure rbac       # role assignment scoping, custom roles, audit over-permissioned identities
/platform-skills:azure review     # production-readiness checklist for an Azure environment
```

---

## Interactive Wizard (fires when no mode is provided)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. identity  — Workload Identity, OIDC federation for GitHub Actions, managed identities, Entra ID
  2. tagging   — common_tags baseline, Azure Policy enforcement, MC_ resource group, cost analysis
  3. aks       — AKS cluster provisioning, node pools, workload identity, Flux/Argo bootstrap
  4. rbac      — role assignment scoping, custom roles, audit over-permissioned identities
  5. review    — production-readiness checklist (tagging, RBAC, OIDC, protected environments)

Enter 1–5 or mode name:
```

**Q2 — Context** (after mode selected):
- **identity**: `What needs Azure access — a GitHub Actions workflow, an in-cluster workload, or a human team?`
- **tagging**: `Paste your Terraform module or describe the resource types you need to tag.`
- **aks**: `New cluster or modifying existing? What add-ons are needed (Flux, Argo CD, ESO, Linkerd)?`
- **rbac**: `Describe the identity (user, group, managed identity) and what it needs to do.`
- **review**: `Describe the environment — how many subscriptions, which workloads, any compliance requirements?`

---

## Mode: identity

**Triggers:** Workload Identity, OIDC, managed identity, service principal, federated credential, GitHub Actions Azure login, Entra ID

Read `references/azure.md` before responding.

### GitHub Actions OIDC federation (no long-lived secrets)

```bash
# Create a user-assigned managed identity
az identity create \
  --name github-actions-deploy \
  --resource-group platform-rg \
  --location northeurope

# Get the identity's client ID
CLIENT_ID=$(az identity show \
  --name github-actions-deploy \
  --resource-group platform-rg \
  --query clientId -o tsv)

# Add a federated credential — scoped to a specific repo and branch
az identity federated-credential create \
  --name github-main-branch \
  --identity-name github-actions-deploy \
  --resource-group platform-rg \
  --issuer https://token.actions.githubusercontent.com \
  --subject repo:org/repo:ref:refs/heads/main \
  --audience api://AzureADTokenExchange
```

GitHub Actions workflow:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: azure/login@a65d910e8af852a8061c627c456678983e180302  # v2.2.0
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

### AKS Workload Identity (in-cluster pods)

```hcl
# Terraform — user-assigned managed identity for a workload
resource "azurerm_user_assigned_identity" "app" {
  name                = "app-workload-identity"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
}

# Federated credential — links the Kubernetes service account to the managed identity
resource "azurerm_federated_identity_credential" "app" {
  name                = "app-k8s-sa"
  resource_group_name = azurerm_resource_group.this.name
  parent_id           = azurerm_user_assigned_identity.app.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject             = "system:serviceaccount:app-team:app-sa"
}
```

Kubernetes service account with workload identity annotation:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: app-team
  annotations:
    azure.workload.identity/client-id: "<managed-identity-client-id>"
```

Pod label to opt in:

```yaml
spec:
  template:
    metadata:
      labels:
        azure.workload.identity/use: "true"
```

### Common identity mistakes

| Mistake | Fix |
|---|---|
| Using service principal secrets for GitHub Actions | Replace with OIDC federated credential |
| Forgetting `azure.workload.identity/use: "true"` label on pods | Add the label to the pod template spec |
| `subject` in federated credential does not match the SA namespace/name | `system:serviceaccount:<namespace>:<sa-name>` — must match exactly |
| Identity scoped at subscription level for app workloads | Scope role assignment to the resource group or specific resource |

---

## Mode: tagging

**Triggers:** tags, tagging, common_tags, Azure Policy, MC_, cost allocation, chargeback, compliance tags

Read `references/azure.md` → Tagging resources section before responding.

### Shared locals pattern (Terraform)

```hcl
# variables.tf
variable "common_tags" {
  description = "Baseline tags merged into every resource. Keys are defined by the organization."
  type        = map(string)
}

# locals.tf
locals {
  common_tags = var.common_tags
}

# Every resource uses merge — resource-level tags extend the baseline
resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  tags = merge(local.common_tags, {
    component = "aks-control-plane"
  })
}
```

### AKS managed resource group tagging

```hcl
resource "azurerm_kubernetes_cluster" "this" {
  node_resource_group = "mc-${var.cluster_name}-nodes"

  tags = merge(local.common_tags, {
    component = "aks-control-plane"
  })
}

# Tag the MC_ group explicitly — AKS does not inherit tags automatically
resource "azurerm_resource_group_tag" "mc_tags" {
  for_each            = local.common_tags
  resource_group_name = azurerm_kubernetes_cluster.this.node_resource_group
  tag_key             = each.key
  tag_value           = each.value

  depends_on = [azurerm_kubernetes_cluster.this]
}
```

### Azure Policy — enforce required tags

```bash
# Start with audit during rollout, then switch to deny once estate is clean
az policy assignment create \
  --name "require-team-tag" \
  --display-name "Require team tag on all resources" \
  --policy "/providers/Microsoft.Authorization/policyDefinitions/<built-in-id>" \
  --scope "/subscriptions/<subscription-id>" \
  --enforcement-mode DoNotEnforce   # change to Default when ready to enforce

# Remediate existing non-compliant resources
az policy remediation create \
  --name "tag-remediation-$(date +%Y%m%d)" \
  --policy-assignment <assignment-id> \
  --resource-discovery-mode ExistingNonCompliant
```

**Validation:**
```bash
# Check compliance state
az policy state summarize --subscription <subscription-id> \
  --filter "policyDefinitionName eq '<policy-id>'"
```

---

## Mode: aks

**Triggers:** AKS, cluster, node pool, provision, bootstrap, Flux on AKS, Argo on AKS, add-ons

Read `references/azure.md` before responding.

### Terraform AKS baseline

```hcl
resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  node_resource_group = "mc-${var.cluster_name}-nodes"

  # System node pool
  default_node_pool {
    name                = "system"
    vm_size             = "Standard_D4s_v5"
    node_count          = 3
    os_disk_size_gb     = 128
    type                = "VirtualMachineScaleSets"
    zones               = ["1", "2", "3"]
    only_critical_addons_enabled = true   # system pool: control-plane add-ons only
  }

  # Workload identity + OIDC issuer (required for managed identity federation)
  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  # Managed identity for the cluster itself
  identity {
    type = "SystemAssigned"
  }

  # Azure CNI Overlay — scales further than kubenet, simpler than full CNI
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "calico"
    service_cidr        = "10.96.0.0/16"
    dns_service_ip      = "10.96.0.10"
  }

  tags = merge(local.common_tags, {
    component = "aks-control-plane"
  })
}

# User node pool for workloads
resource "azurerm_kubernetes_cluster_node_pool" "workload" {
  name                  = "workload"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = "Standard_D8s_v5"
  node_count            = 3
  zones                 = ["1", "2", "3"]
  mode                  = "User"

  tags = merge(local.common_tags, {
    component = "aks-workload-nodes"
  })
}
```

### Post-provision bootstrap sequence

```bash
# Get credentials
az aks get-credentials \
  --resource-group <rg> \
  --name <cluster> \
  --overwrite-existing

# Verify nodes are ready
kubectl get nodes

# Bootstrap Flux (if using GitOps)
flux bootstrap github \
  --owner=<org> \
  --repository=<gitops-repo> \
  --branch=main \
  --path=clusters/<cluster-name>
```

For Flux patterns → `/platform-skills:gitops`
For Argo CD → `/platform-skills:gitops`

### Node pool strategy

| Pool | Purpose | Node type |
|---|---|---|
| `system` | kube-system, CoreDNS, metrics-server | Small, stable, zonal |
| `workload` | Application pods | Right-sized for workload type |
| `spot` | Batch jobs, non-critical | Spot VMs for cost reduction |

Taint system pool to prevent workload scheduling:

```hcl
node_taints = ["CriticalAddonsOnly=true:NoSchedule"]
```

---

## Mode: rbac

**Triggers:** role assignment, contributor, owner, custom role, over-permissioned, least privilege, audit RBAC

Read `references/azure.md` → RBAC and identity patterns before responding.

### Role assignment scoping rules

| Identity type | Assignment scope |
|---|---|
| Platform team | Management group or subscription |
| Workload team | Resource group |
| Automation / managed identity | Specific resource or resource group |
| Never | Owner or Contributor to a service principal |

```bash
# Assign a built-in role scoped to a resource group
az role assignment create \
  --assignee <managed-identity-client-id-or-user-upn> \
  --role "Contributor" \
  --scope "/subscriptions/<sub>/resourceGroups/<rg>"

# Scoped to a specific resource
az role assignment create \
  --assignee <managed-identity-client-id> \
  --role "Key Vault Secrets User" \
  --scope "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault-name>"
```

### Audit over-permissioned identities

```bash
# Find all Owner and Contributor assignments on a subscription
az role assignment list \
  --subscription <subscription-id> \
  --query "[?roleDefinitionName=='Owner' || roleDefinitionName=='Contributor']" \
  -o table

# Find service principals with Owner
az role assignment list \
  --subscription <subscription-id> \
  --query "[?principalType=='ServicePrincipal' && roleDefinitionName=='Owner']" \
  -o table
```

### Custom role — when built-ins are too permissive

```json
{
  "Name": "AKS Metrics Reader",
  "Description": "Can read AKS metrics and node pools. Cannot modify.",
  "Actions": [
    "Microsoft.ContainerService/managedClusters/read",
    "Microsoft.ContainerService/managedClusters/agentPools/read",
    "Microsoft.Insights/metrics/read"
  ],
  "NotActions": [],
  "AssignableScopes": ["/subscriptions/<sub>"]
}
```

```bash
az role definition create --role-definition custom-role.json
```

---

## Mode: review

**Triggers:** review, production ready, production checklist, audit my Azure config

Structured production-readiness review. Ask for:
1. Subscription and resource group structure
2. AKS cluster config (or Terraform)
3. Identity model (managed identities, OIDC, service principals in use)
4. Tag baseline enforcement approach

Then evaluate against:

**CRITICAL (must fix before production)**
```
❌ Long-lived service principal secrets for automation — replace with managed identity + OIDC
❌ Owner or Contributor assigned to a service principal — violates least privilege
❌ No resource tagging — blocks cost allocation, ownership tracking, and policy compliance
❌ AKS without workload_identity_enabled = true — forces static credentials in pods
❌ No protected environments in GitHub Actions for production subscription applies
```

**WARNING (should fix)**
```
⚠️  Tags missing from MC_ resource group — AKS does not inherit automatically
⚠️  Single subscription for all environments — mix prod and non-prod increases blast radius
⚠️  No Azure Policy enforce tagging — relies on developer discipline
⚠️  ClusterRoleBinding to workload identity — scope to RoleBinding unless cross-namespace access is required
⚠️  System and workload nodes in same pool — system pool should have CriticalAddonsOnly taint
```

**INFORMATIONAL**
```
ℹ️  Cost Management tags not validated in CI — add OPA/Conftest gate on terraform plan JSON
ℹ️  No Management Group hierarchy — direct subscription assignment makes policy rollout harder
ℹ️  AKS node pool not zone-redundant — add zones: ["1","2","3"] for HA
```

**Handoffs:**
- Terraform generation → `/platform-skills:terraform`
- In-cluster secrets strategy → `/platform-skills:secrets`
- GitOps bootstrap on AKS → `/platform-skills:gitops`

---

## Common mistakes

- **Tags not in every resource** — `azurerm` provider has no `default_tags`; use `merge(local.common_tags, {...})` in every resource and module. The merge pattern is mandatory.
- **Tags on resource group do not propagate** — Azure does not inherit tags from resource groups. Each resource must be tagged independently.
- **AKS MC_ group untagged** — `azurerm_resource_group_tag` or `node_resource_group_tags` must be added explicitly.
- **Service principal secrets for GitHub Actions** — OIDC federated credentials eliminate the need; rotate secrets before migrating.
- **`azurerm` version below 3.87** for `node_resource_group_tags` — check provider version in `versions.tf`.

---

## Reference

Full guidance: `references/azure.md`

For Terraform module generation: `/platform-skills:terraform`

For in-cluster secrets (Azure Key Vault via ESO): `/platform-skills:secrets`

Examples:
- `examples/azure/` — AKS cluster, workload identity, resource group baseline

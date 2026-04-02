# Azure Reference

## Contents

- Foundation scope
- Subscription and identity model
- Tagging resources
- RBAC and identity patterns
- AKS platform patterns
- Terraform and CI guidance

## Foundation scope

For Azure platform work, start from:

- Management group hierarchy
- Subscription segmentation
- Azure Policy and RBAC model
- Shared network and connectivity patterns

Prefer clear separation of subscriptions by environment or workload boundary instead of a flat single-subscription model.

## Subscription and identity model

- Use Entra ID-backed groups and role assignments for humans.
- Use GitHub Actions OIDC federation to avoid long-lived service principal secrets.
- Use workload identity for in-cluster components that need Azure APIs.

## Tagging resources

Tags in Azure drive cost allocation, ownership tracking, and policy compliance. The specific keys an organization uses are a local decision — what matters is that the baseline is consistent, enforced at scale, and covers the tag inheritance gap that Azure has by design.

### Apply a baseline via a shared local

The `azurerm` provider does not have a `default_tags` equivalent. The standard pattern is a `local.common_tags` map that every resource merges in:

```hcl
locals {
  common_tags = var.common_tags
}

variable "common_tags" {
  description = "Baseline tags merged into every resource. Keys are defined by the organization."
  type        = map(string)
}
```

Every resource uses `merge` so the baseline is additive — resource-level tags extend it rather than replace it:

```hcl
resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  tags = merge(local.common_tags, {
    component = "aks-control-plane"
  })
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location

  tags = local.common_tags
}
```

If a key exists in both `local.common_tags` and the inline map, the inline value wins. Use this only for intentional per-resource overrides.

### Tags do not inherit from resource groups

This is the most common tagging mistake in Azure. A resource group tagged with your baseline keys does **not** pass those tags to the resources inside it. Each resource must be tagged independently.

Two ways to handle this:

**Option 1 — Terraform `merge` (recommended for Terraform-managed resources):**
Pass `local.common_tags` explicitly to every resource. This is explicit and reliable.

**Option 2 — Azure Policy with `modify` effect (backstop for everything else):**
Use a policy that automatically appends missing tags by copying them from the resource group:

```json
{
  "policyRule": {
    "if": {
      "field": "tags['your-required-key']",
      "exists": "false"
    },
    "then": {
      "effect": "modify",
      "details": {
        "roleDefinitionIds": [
          "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
        ],
        "operations": [
          {
            "operation": "addOrReplace",
            "field": "tags['your-required-key']",
            "value": "[resourceGroup().tags['your-required-key']]"
          }
        ]
      }
    }
  }
}
```

Assign this policy at management group scope so it covers all subscriptions.

### Enforce required tags via Azure Policy

Use `deny` effect to block resource creation without required tags. Start with `audit` during rollout, switch to `deny` once the existing estate is clean:

```json
{
  "mode": "Indexed",
  "policyRule": {
    "if": {
      "field": "tags['your-required-key']",
      "exists": "false"
    },
    "then": {
      "effect": "deny"
    }
  }
}
```

Assign at the management group level for broadest coverage.

### Remediate existing untagged resources

After enabling a `modify` policy, run a remediation task to tag already-existing non-compliant resources:

```bash
az policy remediation create \
  --name "tag-remediation-$(date +%Y%m%d)" \
  --policy-assignment <assignment-id> \
  --resource-discovery-mode ExistingNonCompliant
```

Monitor the task until it completes — large subscriptions may take hours.

### AKS managed resource group

AKS creates a managed resource group (`MC_*`) automatically. Tags set on the `azurerm_kubernetes_cluster` resource do not apply to this group unless you explicitly target it.

Use `node_resource_group` to control the name, then tag it via a separate resource or the `node_resource_group_tags` argument (requires `azurerm` >= 3.87.0):

```hcl
resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  node_resource_group = "mc-${var.cluster_name}-nodes"

  tags = merge(local.common_tags, {
    component = "aks-control-plane"
  })
}
```

Tag the `mc-*` resource group explicitly if your policy covers resource groups:

```hcl
resource "azurerm_resource_group_tag" "mc_tags" {
  for_each            = local.common_tags
  resource_group_name = azurerm_kubernetes_cluster.this.node_resource_group
  tag_key             = each.key
  tag_value           = each.value

  depends_on = [azurerm_kubernetes_cluster.this]
}
```

### Cost analysis using tags

Tags appear in Azure Cost Management after being present for 24–48 hours.

- Navigate to **Cost Management → Cost analysis**.
- Group by the relevant tag key.
- Export a monthly view for chargeback or showback reporting.

Tags on resource groups and individual resources both appear in cost exports. If a resource is untagged but its resource group is tagged, the group-level tag does not automatically apply to the cost record for that resource.

## RBAC and identity patterns

- Prefer built-in roles over custom roles. Escalate to custom only when a built-in role is materially too permissive.
- Assign roles at management group or subscription level for platform teams. Assign at resource group level for workload teams.
- Never assign Owner or Contributor to service principals. Use the minimum built-in role or a scoped custom role.
- Use managed identities for all workloads. Avoid service principal secrets.

## AKS platform patterns

- Provision AKS, networking, managed identities, and shared services with Terraform.
- Reconcile cluster add-ons and workloads with Flux or Argo CD after bootstrap.
- Keep platform add-ons versioned and promoted through Git, not portal changes.

## Terraform and CI guidance

- Make subscription and tenant targeting explicit in code and workflow naming.
- Use `merge(local.common_tags, {...})` in every resource and module. Never leave `tags` empty.
- Keep role assignments narrow and auditable.
- Use protected environments for applies to production subscriptions.
- Fail CI if any planned resource is missing required tags — validate against `terraform plan -out=plan.json` using OPA, Conftest, or a custom script.

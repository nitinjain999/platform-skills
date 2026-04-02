terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.87.0"
    }
  }
}

variable "cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that contains the AKS cluster."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "app_namespace" {
  description = "Kubernetes namespace where the workload runs."
  type        = string
}

variable "app_name" {
  description = "Name of the application (used for identity and service account naming)."
  type        = string
}

variable "storage_account_id" {
  description = "Resource ID of the storage account to grant access to."
  type        = string
}

# Reference the existing AKS cluster to get its OIDC issuer URL.
data "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  resource_group_name = var.resource_group_name
}

# User-assigned managed identity for the workload.
resource "azurerm_user_assigned_identity" "workload" {
  name                = "${var.app_name}-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
}

# Federated credential: trusts tokens issued for this namespace/serviceaccount pair.
resource "azurerm_federated_identity_credential" "this" {
  name                = "${var.app_name}-federated"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.workload.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = data.azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject             = "system:serviceaccount:${var.app_namespace}:${var.app_name}-sa"
}

# Scope the role assignment to the specific resource, not a subscription.
resource "azurerm_role_assignment" "storage" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

output "client_id" {
  description = "Client ID to annotate on the Kubernetes ServiceAccount."
  value       = azurerm_user_assigned_identity.workload.client_id
}

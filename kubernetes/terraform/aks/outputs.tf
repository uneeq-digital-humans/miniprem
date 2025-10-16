# Terraform Outputs for AKS Cluster
#
# These values are used by deployment scripts and other automation
# Access with: terraform output <output_name>

output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_id" {
  description = "AKS cluster resource ID"
  value       = azurerm_kubernetes_cluster.main.id
}

output "kube_config" {
  description = "Kubernetes configuration for kubectl (base64 encoded)"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "resource_group_name" {
  description = "Resource group name containing the AKS cluster"
  value       = azurerm_resource_group.main.name
}

output "node_resource_group" {
  description = "Auto-generated resource group where AKS creates infrastructure (VM Scale Sets, Load Balancers, etc.)"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "autoscaler_identity_client_id" {
  description = "Client ID of the managed identity for cluster autoscaler (use in autoscaler Helm values)"
  value       = azurerm_user_assigned_identity.cluster_autoscaler.client_id
}

output "region" {
  description = "Azure region where cluster is deployed"
  value       = azurerm_resource_group.main.location
}

output "vnet_id" {
  description = "Virtual Network resource ID"
  value       = azurerm_virtual_network.main.id
}

output "subnet_id" {
  description = "Nodes subnet resource ID"
  value       = azurerm_subnet.nodes.id
}

output "cluster_fqdn" {
  description = "FQDN of the AKS cluster API server"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

# Usage Examples:
#
# Configure kubectl:
#   az aks get-credentials --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw cluster_name)
#
# Get kubeconfig directly:
#   terraform output -raw kube_config > ~/.kube/aks-config
#   export KUBECONFIG=~/.kube/aks-config
#
# Use autoscaler identity in Helm:
#   helm install cluster-autoscaler ... --set azureClientID=$(terraform output -raw autoscaler_identity_client_id)

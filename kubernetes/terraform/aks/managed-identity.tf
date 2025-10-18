# Managed Identity for Cluster Autoscaler
#
# Azure Managed Identity is the modern authentication method for Azure services
# Replaces service principals with automatic credential rotation and better security
#
# The cluster autoscaler needs permissions to:
#   - Scale node pools up/down based on pod resource requests
#   - Query VM Scale Set status
#   - Modify VM Scale Set capacity

# User-Assigned Managed Identity
# Created explicitly for cluster autoscaler to use
resource "azurerm_user_assigned_identity" "cluster_autoscaler" {
  name                = "${local.cluster_name}-autoscaler-identity"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = local.common_tags
}

# Role Assignment: Virtual Machine Contributor
# Grants the identity permissions to manage VM Scale Sets
# Scoped to the node resource group (where AKS creates infrastructure)
#
# The node resource group is auto-created by AKS and contains:
#   - VM Scale Sets for each node pool
#   - Load balancers
#   - Network interfaces
#   - Public IPs
#
# NOTE: These role assignments require the Terraform service principal to have
# "User Access Administrator" or "Owner" role. Commented out for initial deployment.
# You can enable cluster autoscaling manually in Azure Portal or via az CLI:
#   az role assignment create --assignee <identity-principal-id> \
#     --role "Virtual Machine Contributor" \
#     --scope "/subscriptions/${var.azure_subscription_id}/resourceGroups/MC_..."
#
# resource "azurerm_role_assignment" "cluster_autoscaler" {
#   scope                = "/subscriptions/${var.azure_subscription_id}/resourceGroups/${azurerm_kubernetes_cluster.main.node_resource_group}"
#   role_definition_name = "Virtual Machine Contributor"
#   principal_id         = azurerm_user_assigned_identity.cluster_autoscaler.principal_id
#
#   # Ensure node resource group exists before assigning role
#   depends_on = [
#     azurerm_kubernetes_cluster.main
#   ]
# }

# Additional role assignment for node resource group read access
# Allows the autoscaler to query current state
# resource "azurerm_role_assignment" "cluster_autoscaler_reader" {
#   scope                = "/subscriptions/${var.azure_subscription_id}/resourceGroups/${azurerm_kubernetes_cluster.main.node_resource_group}"
#   role_definition_name = "Reader"
#   principal_id         = azurerm_user_assigned_identity.cluster_autoscaler.principal_id
#
#   depends_on = [
#     azurerm_kubernetes_cluster.main
#   ]
# }

# Note: The identity client_id is used in cluster-autoscaler Helm values
# See kubernetes/manifests/cluster-autoscaler.yaml for usage

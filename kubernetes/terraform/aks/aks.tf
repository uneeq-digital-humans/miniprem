# Azure Kubernetes Service (AKS) Cluster Configuration
# This creates a production-ready AKS cluster with GPU node support

resource "azurerm_kubernetes_cluster" "main" {
  name                = local.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = local.cluster_name
  kubernetes_version  = var.kubernetes_version

  # Managed Identity for the cluster
  # Modern authentication method replacing service principals
  # Provides automatic credential rotation and Azure RBAC integration
  identity {
    type = "SystemAssigned"
  }

  # Default system node pool
  # Runs critical system pods (CoreDNS, metrics-server, etc.)
  # Uses non-GPU VMs for cost efficiency
  default_node_pool {
    name                = "system"
    node_count          = 2
    vm_size             = "Standard_D4s_v3" # 4 vCPU, 16GB RAM
    vnet_subnet_id      = azurerm_subnet.nodes.id
    enable_auto_scaling = false
    os_disk_size_gb     = 128
    os_disk_type        = "Managed"
    type                = "VirtualMachineScaleSets"

    # System workloads only
    node_labels = {
      "node-role" = "system"
    }

    tags = local.common_tags
  }

  # Azure CNI Networking
  # Production-grade networking with native Azure integration
  # Each pod gets an IP from the VNet subnet
  # Required for advanced networking features and better performance
  network_profile {
    network_plugin    = "azure"                        # Azure CNI vs kubenet (basic)
    network_policy    = "azure"                        # Azure Network Policy for pod-to-pod rules
    service_cidr      = var.service_cidr               # Internal service IPs (ClusterIP)
    dns_service_ip    = cidrhost(var.service_cidr, 10) # Must be within service_cidr
    load_balancer_sku = "standard"                     # Standard load balancer for production
  }

  # Enable RBAC for fine-grained access control
  role_based_access_control_enabled = true

  # Enable Azure Active Directory integration for authentication
  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  # Automatic upgrades disabled for production stability
  # Manual upgrades allow testing and validation first
  # (Omitting automatic_channel_upgrade leaves it disabled by default)

  # HTTP application routing addon (disabled)
  # Not recommended for production - use ingress controller instead
  http_application_routing_enabled = false

  tags = local.common_tags
}

# Store kubeconfig for kubectl access
# This is automatically configured after cluster creation
resource "local_file" "kubeconfig" {
  content  = azurerm_kubernetes_cluster.main.kube_config_raw
  filename = "${path.module}/kubeconfig"

  depends_on = [azurerm_kubernetes_cluster.main]
}

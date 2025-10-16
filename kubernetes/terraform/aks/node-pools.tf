# GPU Node Pool Configuration for Renny Digital Human Rendering
#
# CRITICAL DECISIONS:
#
# 1. VM Size: Standard_NC16as_T4_v3
#    - GPU: NVIDIA T4 (16GB VRAM)
#    - CPU: 16 vCPUs (AMD EPYC 7V12)
#    - Memory: 110GB RAM
#    - GPU Driver: Standard NVIDIA drivers (driver 580+)
#    - Cost: ~$1.20/hour per node
#
# 2. Why NOT NVads_A10_v5:
#    - Uses NVIDIA A10 with vGPU (virtualized GPU)
#    - Requires vGPU drivers (incompatible with GPU Operator standard workflow)
#    - More complex setup with GRID licensing
#    - NC16as_T4_v3 uses standard NVIDIA drivers (production tested)
#
# 3. SkipGPUDriverInstall Tag:
#    - Prevents Azure from pre-installing GPU drivers
#    - Allows GPU Operator to install driver 580 with proper config
#    - GPU Operator handles driver lifecycle (updates, rollbacks)
#    - Without this tag: driver conflicts and pod failures
#
# 4. Node Taints:
#    - nvidia.com/gpu=true:NoSchedule
#    - Prevents non-GPU workloads from consuming expensive GPU nodes
#    - Only pods with matching tolerations can schedule

resource "azurerm_kubernetes_cluster_node_pool" "renny" {
  name                  = "rennygpu"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.renny_vm_size
  vnet_subnet_id        = azurerm_subnet.nodes.id

  # Autoscaling configuration
  # Production: 10-20 nodes for handling variable load
  # Each node runs 4 Renny pods (time-slicing)
  enable_auto_scaling = true
  min_count           = var.renny_min_size
  max_count           = var.renny_max_size
  node_count          = var.renny_desired_size

  # Node configuration
  os_disk_size_gb = 256 # Larger disk for container images
  os_disk_type    = "Managed"
  os_type         = "Linux"

  # Node labels for pod scheduling
  # These labels are used by nodeSelector in Renny deployment
  node_labels = {
    "uneeq.io/node-type" = "renny"
    "workload-type"      = "gpu"
    "nvidia.com/gpu"     = "true"
  }

  # Node taints to reserve GPU nodes for GPU workloads only
  # Non-GPU pods will not schedule here unless they have matching tolerations
  node_taints = [
    "nvidia.com/gpu=true:NoSchedule"
  ]

  # CRITICAL: Skip automatic GPU driver installation
  # GPU Operator will install driver 580 with proper configuration
  # This tag is essential for GPU Operator compatibility
  tags = merge(local.common_tags, {
    SkipGPUDriverInstall = "true"
  })

  # Ensure system node pool is created first
  depends_on = [
    azurerm_kubernetes_cluster.main
  ]
}

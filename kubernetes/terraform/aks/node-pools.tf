# ============================================================================
# GPU Node Pool Configuration for Renny Digital Human Rendering
# ============================================================================
#
# ⚠️  IMPORTANT: GPU node pool is created via Azure CLI, NOT Terraform
#
# WHY: Driver 580+ Requirement
# - Unreal Engine 5.6 requires NVIDIA driver 580+
# - Azure Terraform provider doesn't support gpu_profile.driver="none" yet
# - Terraform would cause Azure to pre-install driver 570 (incompatible)
#
# SOLUTION: Azure CLI with aks-preview Extension
# - Node pool created in deploy-azure.sh using: az aks nodepool add
# - Uses --gpu-driver None parameter (requires aks-preview extension)
# - Allows GPU Operator to install driver 580+ without conflicts
#
# CONFIGURATION REFERENCE:
# The GPU node pool is created with these settings:
# - Name: rennygpu
# - VM Size: Standard_NC16as_T4_v3 (NVIDIA T4, 16GB VRAM)
# - Autoscaling: 2-4 nodes (configurable in terraform.tfvars)
# - Labels: uneeq.io/node-type=renny, workload-type=gpu, nvidia.com/gpu=true
# - Taints: nvidia.com/gpu=true:NoSchedule
# - GPU Driver: None (GPU Operator installs driver 580+)
#
# See: kubernetes/scripts/deploy-azure.sh (search for "az aks nodepool add")
# ============================================================================

# No Terraform resource here - node pool managed by Azure CLI in deployment script

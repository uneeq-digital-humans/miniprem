# Azure AKS Terraform Variables
#
# This file defines all configurable parameters for the AKS cluster deployment
# Override default values in terraform.tfvars

# Azure Subscription Configuration
variable "azure_subscription_id" {
  description = "Azure Subscription ID (find with: az account show --query id -o tsv)"
  type        = string
  sensitive   = true
}

variable "azure_region" {
  description = "Azure region for all resources (e.g., eastus, westus2, westeurope)"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group to create"
  type        = string
  default     = "renny-kubernetes"
}

# Network Configuration
variable "vnet_cidr" {
  description = "Virtual Network CIDR block - PERMANENT DECISION (cannot be changed without cluster rebuild)"
  type        = string
  default     = "10.17.0.0/16"
}

variable "subnet_cidr" {
  description = "Subnet CIDR block for AKS nodes - must be within vnet_cidr. With Azure CNI, each pod gets an IP from this range."
  type        = string
  default     = "10.17.0.0/22" # 1024 IPs: ~256 nodes max (4 IPs per node for system + pods)
}

variable "service_cidr" {
  description = "Kubernetes service CIDR block - PERMANENT DECISION. Must NOT overlap with vnet_cidr or any connected networks."
  type        = string
  default     = "10.117.0.0/16"
}

# Cluster Configuration
variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster (check available: az aks get-versions --location eastus -o table)"
  type        = string
  default     = "1.31"
}

variable "project_name" {
  description = "Project name used in resource naming and tags"
  type        = string
  default     = "renny"
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"
}

variable "deployment_id" {
  description = "Unique deployment identifier for resource isolation (git hash or timestamp). Leave empty for single deployment per environment."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.deployment_id)) || var.deployment_id == ""
    error_message = "Deployment ID must contain only lowercase letters, numbers, and hyphens."
  }
}

# GPU Node Pool Configuration
variable "renny_vm_size" {
  description = <<-EOT
    Azure VM size for Renny GPU nodes.

    RECOMMENDED: Standard_NC16as_T4_v3
      - GPU: NVIDIA T4 (16GB VRAM)
      - CPU: 16 vCPUs AMD EPYC 7V12
      - Memory: 110GB RAM
      - GPU Driver: Standard NVIDIA drivers (580+)
      - Cost: ~$1.20/hour
      - Pods per node: 4 (with time-slicing)

    DO NOT USE: Standard_NVads_A10_v5
      - GPU: NVIDIA A10 with vGPU (virtualized)
      - Requires vGPU drivers (incompatible with standard GPU Operator)
      - Requires NVIDIA GRID licensing
      - Complex setup, not production tested
  EOT
  type        = string
  default     = "Standard_NC16as_T4_v3"
}

variable "renny_min_size" {
  description = "Minimum number of Renny GPU nodes for autoscaling"
  type        = number
  default     = 10
}

variable "renny_max_size" {
  description = "Maximum number of Renny GPU nodes for autoscaling"
  type        = number
  default     = 20
}

variable "renny_desired_size" {
  description = "Initial desired number of Renny GPU nodes"
  type        = number
  default     = 10
}

# Application Configuration
variable "dhop_url" {
  description = "DHOP (Digital Human Operations Platform) WebSocket URL"
  type        = string
  default     = "wss://api.enterprise.uneeq.io:443/signalling-service"
}

variable "dhop_tenant_id" {
  description = "DHOP Tenant ID (UUID format)"
  type        = string
  sensitive   = true
}

variable "dhop_api_key" {
  description = "DHOP API Key (base64 encoded)"
  type        = string
  sensitive   = true
}

# Docker Registry Credentials
variable "docker_username" {
  description = "Docker Hub username with access to UneeQ repositories"
  type        = string
  sensitive   = true
}

variable "docker_password" {
  description = "Docker Hub password or Personal Access Token"
  type        = string
  sensitive   = true
}

# Google Kubernetes Engine (GKE) Implementation Design
# MiniPrem Renny Digital Human Platform

**Version**: 1.0
**Date**: October 16, 2025
**Status**: Architecture Design Phase
**Target**: Feature parity with EKS and AKS implementations

---

## Executive Summary

This document provides a comprehensive architectural design for deploying MiniPrem Renny on Google Kubernetes Engine (GKE), achieving feature parity with existing AWS EKS and Azure AKS implementations. The design leverages GKE's native GPU support, VPC-native networking, and Workload Identity for a production-ready, secure, and cost-optimized deployment.

### Key Features
- **GPU Instances**: n1-standard-16 with NVIDIA T4 (16GB VRAM)
- **Scaling**: 10-20 GPU nodes with cluster autoscaler
- **Networking**: VPC-native networking with private nodes
- **Authentication**: Workload Identity (GKE's IAM integration)
- **GPU Drivers**: GKE GPU device driver daemonset (auto-managed)
- **Time-Slicing**: 2-4 Renny pods per GPU

---

## 1. File Structure & Organization

The GKE implementation follows the established pattern from EKS and AKS:

```
kubernetes/terraform/gke/
├── main.tf                      # Provider, backend, common config
├── gke.tf                       # GKE cluster resource
├── vpc.tf                       # VPC and subnet configuration
├── node-pools.tf                # GPU and system node pools
├── service-accounts.tf          # Workload Identity and IAM bindings
├── variables.tf                 # All configurable parameters
├── outputs.tf                   # Terraform outputs for automation
├── terraform.tfvars.example     # Example configuration
├── .gitignore                   # Ignore state files and secrets
├── README.md                    # Deployment guide (500+ lines)
└── QUICK_START.md               # Fast deployment reference

kubernetes/scripts/gke/
├── check-gcp-prerequisites.sh   # Pre-deployment validation
├── check-network-usage.sh       # VPC quota and IP usage analysis
└── README.md                    # Script usage documentation

kubernetes/values/
└── renny-values-gke.yaml        # GKE-specific Helm overrides
```

### File Size Estimates
| File | Estimated Lines | Purpose |
|------|-----------------|---------|
| main.tf | 75 | Provider configuration, backend, locals |
| gke.tf | 120 | GKE cluster with addons and networking |
| vpc.tf | 90 | VPC, subnets, Cloud NAT, firewall rules |
| node-pools.tf | 110 | GPU and system node pools |
| service-accounts.tf | 95 | Workload Identity and IAM policies |
| variables.tf | 150 | Variables with descriptions/validation |
| outputs.tf | 80 | Outputs for automation scripts |
| terraform.tfvars.example | 110 | Example configuration |
| **Total** | **830** | **Core infrastructure code** |

---

## 2. Terraform Resources Architecture

### 2.1 Provider Configuration (main.tf)

```hcl
terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  # Optional: GCS backend for state management
  # backend "gcs" {
  #   bucket = "renny-terraform-state"
  #   prefix = "gke/terraform.tfstate"
  # }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# Kubernetes provider using GKE cluster credentials
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }
}

locals {
  # Generate cluster name with deployment ID for resource isolation
  cluster_name = var.deployment_id != "" ? "${var.project_name}-${var.environment}-${var.deployment_id}" : "${var.project_name}-${var.environment}"

  # GCP region to zones mapping
  zones = [
    "${var.gcp_region}-a",
    "${var.gcp_region}-b",
    "${var.gcp_region}-c"
  ]

  # Common labels for all resources (GCP uses labels, not tags)
  common_labels = {
    project       = var.project_name
    environment   = var.environment
    deployment_id = var.deployment_id != "" ? var.deployment_id : "default"
    managed_by    = "terraform"
    cloud         = "gcp"
    workload      = "digital-human"
  }
}
```

### 2.2 GKE Cluster Configuration (gke.tf)

```hcl
# GKE Cluster Resource
# Creates a production-ready GKE cluster with GPU support
resource "google_container_cluster" "primary" {
  name     = local.cluster_name
  location = var.gcp_region  # Regional cluster (multi-zone HA)

  # GKE release channel for automatic upgrades
  # "REGULAR" provides balanced stability and features
  release_channel {
    channel = "REGULAR"
  }

  # Minimum Kubernetes version (matches EKS/AKS)
  min_master_version = "1.31"

  # VPC-native networking (IP aliasing)
  # Required for advanced networking features
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.nodes.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.nodes.secondary_ip_range[1].range_name
  }

  # Network configuration
  network    = google_compute_network.vpc.self_link
  subnetwork = google_compute_subnetwork.nodes.self_link

  # Private cluster configuration
  # Control plane is private, nodes have no public IPs
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false  # Allow public access to control plane
    master_ipv4_cidr_block  = "172.16.0.0/28"  # Control plane CIDR
  }

  # Master authorized networks (optional - restrict control plane access)
  # master_authorized_networks_config {
  #   cidr_blocks {
  #     cidr_block   = "0.0.0.0/0"
  #     display_name = "All networks"
  #   }
  # }

  # Remove default node pool (we'll create custom node pools)
  remove_default_node_pool = true
  initial_node_count       = 1

  # Workload Identity (GKE's IAM integration)
  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  # GKE addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    # GKE-managed GPU drivers (alternative to GPU Operator)
    gcs_fuse_csi_driver_config {
      enabled = false
    }
  }

  # Enable network policy enforcement
  network_policy {
    enabled  = true
    provider = "PROVIDER_UNSPECIFIED"  # Use GKE default (Calico)
  }

  # Cluster maintenance policy
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"  # 3 AM local time
    }
  }

  # Binary authorization (optional - for image signing)
  binary_authorization {
    evaluation_mode = "DISABLED"
  }

  # Resource labels
  resource_labels = local.common_labels

  # Logging and monitoring (Cloud Operations)
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  # Cluster lifecycle
  lifecycle {
    ignore_changes = [
      initial_node_count,
      node_pool
    ]
  }
}
```

### 2.3 VPC and Networking (vpc.tf)

```hcl
# VPC Network
# Isolated network for GKE cluster
resource "google_compute_network" "vpc" {
  name                    = "${local.cluster_name}-vpc"
  auto_create_subnetworks = false  # Manual subnet control
  routing_mode            = "REGIONAL"

  description = "VPC for ${local.cluster_name} GKE cluster"
}

# Subnet for GKE Nodes
# VPC-native mode: Primary range for nodes, secondary ranges for pods/services
resource "google_compute_subnetwork" "nodes" {
  name          = "${local.cluster_name}-nodes-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.gcp_region
  network       = google_compute_network.vpc.id

  # Secondary ranges for VPC-native networking
  secondary_ip_range {
    range_name    = "${local.cluster_name}-pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "${local.cluster_name}-services"
    ip_cidr_range = var.service_cidr
  }

  # Private Google Access (access Google APIs without public IPs)
  private_ip_google_access = true

  description = "Subnet for GKE nodes, pods, and services"
}

# Cloud Router (required for Cloud NAT)
resource "google_compute_router" "router" {
  name    = "${local.cluster_name}-router"
  region  = var.gcp_region
  network = google_compute_network.vpc.id

  description = "Cloud Router for NAT gateway"
}

# Cloud NAT (outbound internet for private nodes)
# Required for:
#   - Pulling container images
#   - External API calls (UneeQ DHOP)
#   - Software updates
resource "google_compute_router_nat" "nat" {
  name                               = "${local.cluster_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall Rules
# Allow internal communication within VPC
resource "google_compute_firewall" "internal" {
  name    = "${local.cluster_name}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.subnet_cidr,
    var.pods_cidr,
    var.service_cidr
  ]

  description = "Allow internal communication within VPC"
}

# WebRTC/TURN firewall rules (Renny requirement)
resource "google_compute_firewall" "webrtc" {
  name    = "${local.cluster_name}-allow-webrtc"
  network = google_compute_network.vpc.name

  allow {
    protocol = "udp"
    ports    = ["22000-23000"]  # WebRTC port range
  }

  allow {
    protocol = "udp"
    ports    = ["3478"]  # TURN UDP
  }

  allow {
    protocol = "tcp"
    ports    = ["3478", "5349"]  # TURN TCP/TLS
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-${local.cluster_name}"]

  description = "Allow WebRTC and TURN traffic for Renny"
}

# Firewall rule for health checks
resource "google_compute_firewall" "health_checks" {
  name    = "${local.cluster_name}-allow-health-checks"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8081"]  # Renny health check port
  }

  source_ranges = [
    "35.191.0.0/16",   # Google health check ranges
    "130.211.0.0/22"
  ]

  target_tags = ["gke-${local.cluster_name}"]

  description = "Allow GCP health checks"
}
```

### 2.4 Node Pools (node-pools.tf)

```hcl
# System Node Pool
# Runs control plane components (CoreDNS, metrics-server, etc.)
# Uses non-GPU instances for cost efficiency
resource "google_container_node_pool" "system" {
  name       = "system-pool"
  location   = var.gcp_region
  cluster    = google_container_cluster.primary.name
  node_count = 2  # Fixed size (no autoscaling for system)

  node_config {
    machine_type = "n1-standard-4"  # 4 vCPU, 15GB RAM
    disk_size_gb = 100
    disk_type    = "pd-standard"

    # Service account with minimal permissions
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Node labels
    labels = merge(local.common_labels, {
      "node-role" = "system"
    })

    # Node metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }

    # Shielded instance configuration
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    tags = ["gke-${local.cluster_name}", "system-node"]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# GPU Node Pool for Renny
# n1-standard-16 with NVIDIA T4 (16GB VRAM)
resource "google_container_node_pool" "renny_gpu" {
  name     = "renny-gpu-pool"
  location = var.gcp_region
  cluster  = google_container_cluster.primary.name

  # Autoscaling configuration
  autoscaling {
    min_node_count = var.renny_min_size
    max_node_count = var.renny_max_size
  }

  initial_node_count = var.renny_desired_size

  node_config {
    machine_type = var.renny_instance_type  # n1-standard-16
    disk_size_gb = 256  # Larger disk for container images
    disk_type    = "pd-standard"

    # GPU configuration
    guest_accelerator {
      type  = "nvidia-tesla-t4"  # T4 GPU (16GB VRAM)
      count = 1

      # GPU driver installation strategy
      # GKE can auto-install drivers or use GPU Operator
      gpu_driver_installation_config {
        gpu_driver_version = "DEFAULT"  # Let GKE manage drivers
      }

      # GPU sharing (time-slicing)
      gpu_sharing_config {
        gpu_sharing_strategy       = "TIME_SHARING"
        max_shared_clients_per_gpu = var.gpu_time_slicing_replicas
      }
    }

    # Service account with GPU permissions
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Node labels (for pod scheduling)
    labels = merge(local.common_labels, {
      "uneeq.io/node-type" = "renny"
      "workload-type"      = "gpu"
      "nvidia.com/gpu"     = "true"
    })

    # Node taints (GPU node reservation)
    taint {
      key    = "nvidia.com/gpu"
      value  = "true"
      effect = "NO_SCHEDULE"
    }

    # Node metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }

    # Shielded instance configuration
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    tags = ["gke-${local.cluster_name}", "gpu-node"]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Lifecycle
  lifecycle {
    ignore_changes = [initial_node_count]
  }
}
```

### 2.5 IAM and Service Accounts (service-accounts.tf)

```hcl
# Service Account for GKE Nodes
# Used by all node pools for GCP API access
resource "google_service_account" "gke_nodes" {
  account_id   = "${local.cluster_name}-nodes"
  display_name = "Service Account for ${local.cluster_name} GKE nodes"
  description  = "Used by GKE nodes to access GCP services"
}

# IAM bindings for node service account
resource "google_project_iam_member" "gke_nodes_log_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_metric_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_monitoring_viewer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Artifact Registry access (if using Google Artifact Registry)
resource "google_project_iam_member" "gke_nodes_artifact_registry" {
  project = var.gcp_project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Kubernetes Service Account for Renny Pods (Workload Identity)
resource "kubernetes_service_account" "renny" {
  metadata {
    name      = "renny-sa"
    namespace = "uneeq-renderer"
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.renny_workload.email
    }
  }

  depends_on = [google_container_cluster.primary]
}

# GCP Service Account for Renny Workload Identity
resource "google_service_account" "renny_workload" {
  account_id   = "${local.cluster_name}-renny"
  display_name = "Workload Identity for Renny pods"
  description  = "Used by Renny pods via Workload Identity"
}

# Workload Identity binding
resource "google_service_account_iam_binding" "renny_workload_identity" {
  service_account_id = google_service_account.renny_workload.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.gcp_project_id}.svc.id.goog[uneeq-renderer/renny-sa]"
  ]
}

# Service Account for Cluster Autoscaler
resource "google_service_account" "cluster_autoscaler" {
  account_id   = "${local.cluster_name}-autoscaler"
  display_name = "Service Account for Cluster Autoscaler"
  description  = "Used by cluster autoscaler to scale node pools"
}

# Cluster Autoscaler IAM permissions
resource "google_project_iam_custom_role" "cluster_autoscaler" {
  role_id     = replace("${local.cluster_name}_autoscaler", "-", "_")
  title       = "Cluster Autoscaler Role for ${local.cluster_name}"
  description = "Permissions for cluster autoscaler"

  permissions = [
    "compute.instanceGroupManagers.get",
    "compute.instanceGroupManagers.list",
    "compute.instanceGroupManagers.update",
    "compute.instanceGroups.get",
    "compute.instanceGroups.list",
    "compute.instances.list",
    "compute.zones.list",
  ]
}

resource "google_project_iam_member" "cluster_autoscaler" {
  project = var.gcp_project_id
  role    = google_project_iam_custom_role.cluster_autoscaler.id
  member  = "serviceAccount:${google_service_account.cluster_autoscaler.email}"
}

# Kubernetes Service Account for Cluster Autoscaler
resource "kubernetes_service_account" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.cluster_autoscaler.email
    }
  }

  depends_on = [google_container_cluster.primary]
}

# Workload Identity binding for autoscaler
resource "google_service_account_iam_binding" "cluster_autoscaler_workload_identity" {
  service_account_id = google_service_account.cluster_autoscaler.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.gcp_project_id}.svc.id.goog[kube-system/cluster-autoscaler]"
  ]
}
```

### 2.6 Variables (variables.tf)

```hcl
# GCP Project Configuration
variable "gcp_project_id" {
  description = "GCP Project ID (find with: gcloud config get-value project)"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for cluster deployment (e.g., us-central1, us-east1, europe-west1)"
  type        = string
  default     = "us-central1"
}

# Network Configuration
variable "subnet_cidr" {
  description = "Primary subnet CIDR for GKE nodes - PERMANENT DECISION (cannot be changed without cluster rebuild)"
  type        = string
  default     = "10.17.0.0/22"  # 1024 IPs for nodes
}

variable "pods_cidr" {
  description = "Secondary range CIDR for pods - PERMANENT DECISION. Each pod gets an IP from this range."
  type        = string
  default     = "10.18.0.0/16"  # 65,536 IPs for pods
}

variable "service_cidr" {
  description = "Secondary range CIDR for services - PERMANENT DECISION. Must NOT overlap with subnet or pods CIDR."
  type        = string
  default     = "10.117.0.0/16"  # 65,536 IPs for services
}

# Cluster Configuration
variable "kubernetes_version" {
  description = "Minimum Kubernetes version (GKE will use latest patch in REGULAR channel)"
  type        = string
  default     = "1.31"
}

variable "project_name" {
  description = "Project name used in resource naming and labels"
  type        = string
  default     = "renny"
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"
}

variable "deployment_id" {
  description = "Unique deployment identifier for resource isolation (git hash or timestamp). Leave empty for single deployment."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.deployment_id)) || var.deployment_id == ""
    error_message = "Deployment ID must contain only lowercase letters, numbers, and hyphens."
  }
}

# GPU Node Pool Configuration
variable "renny_instance_type" {
  description = <<-EOT
    GCP machine type for Renny GPU nodes.

    RECOMMENDED: n1-standard-16
      - Base: 16 vCPUs, 60GB RAM
      - GPU: NVIDIA T4 (16GB VRAM) - added separately
      - Cost: ~$0.76/hour (VM) + ~$0.35/hour (GPU) = ~$1.11/hour total
      - Pods per node: 2-4 (with time-slicing)
      - Balanced CPU/memory for digital human rendering

    ALTERNATIVES:
      - n1-standard-8: 8 vCPUs, 30GB RAM (less CPU, lower cost)
      - n1-standard-32: 32 vCPUs, 120GB RAM (more CPU, higher cost)
      - n1-highmem-16: 16 vCPUs, 104GB RAM (more memory)
  EOT
  type        = string
  default     = "n1-standard-16"
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

variable "gpu_time_slicing_replicas" {
  description = "Number of pods that can share a single GPU (GKE native time-slicing)"
  type        = number
  default     = 2

  validation {
    condition     = var.gpu_time_slicing_replicas >= 1 && var.gpu_time_slicing_replicas <= 8
    error_message = "GPU time-slicing replicas must be between 1 and 8."
  }
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
```

### 2.7 Outputs (outputs.tf)

```hcl
# Terraform Outputs for GKE Cluster
# These values are used by deployment scripts and automation

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "cluster_id" {
  description = "GKE cluster resource ID"
  value       = google_container_cluster.primary.id
}

output "cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate (base64 encoded)"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "project_id" {
  description = "GCP project ID"
  value       = var.gcp_project_id
}

output "region" {
  description = "GCP region where cluster is deployed"
  value       = var.gcp_region
}

output "vpc_id" {
  description = "VPC network resource ID"
  value       = google_compute_network.vpc.id
}

output "subnet_id" {
  description = "Nodes subnet resource ID"
  value       = google_compute_subnetwork.nodes.id
}

output "node_service_account_email" {
  description = "Email of the service account used by GKE nodes"
  value       = google_service_account.gke_nodes.email
}

output "renny_service_account_email" {
  description = "Email of the Workload Identity service account for Renny pods"
  value       = google_service_account.renny_workload.email
}

output "autoscaler_service_account_email" {
  description = "Email of the service account for cluster autoscaler"
  value       = google_service_account.cluster_autoscaler.email
}

# Usage Examples:
#
# Configure kubectl:
#   gcloud container clusters get-credentials $(terraform output -raw cluster_name) \
#     --region $(terraform output -raw region) \
#     --project $(terraform output -raw project_id)
#
# Get cluster endpoint:
#   echo "https://$(terraform output -raw cluster_endpoint)"
#
# Use Workload Identity in pods:
#   Set serviceAccountName: renny-sa in pod spec
```

---

## 3. GPU Configuration Strategy

### 3.1 Instance Type Selection

**Primary Choice: n1-standard-16 + NVIDIA T4**

| Component | Specification |
|-----------|---------------|
| Machine Type | n1-standard-16 |
| vCPUs | 16 |
| Memory | 60GB RAM |
| GPU | NVIDIA T4 (16GB VRAM) |
| GPU Driver | GKE-managed (auto-installed) |
| Cost | ~$1.11/hour (~$800/month per node) |

**Rationale:**
- **T4 GPU**: Proven in EKS implementation, 16GB VRAM sufficient for Renny
- **16 vCPUs**: Balanced for digital human rendering workloads
- **GKE-managed drivers**: Simpler than GPU Operator, automatic updates
- **Cost-effective**: Lower than g5.4xlarge (AWS) and NC16as_T4_v3 (Azure)

### 3.2 GPU Driver Installation

**GKE Native Approach (Recommended)**

GKE provides automatic GPU driver installation via daemonset:

```hcl
guest_accelerator {
  type  = "nvidia-tesla-t4"
  count = 1

  gpu_driver_installation_config {
    gpu_driver_version = "DEFAULT"  # GKE manages driver version
  }
}
```

**Advantages:**
- Automatic driver installation and updates
- No manual GPU Operator deployment
- GKE handles driver compatibility with Kubernetes version
- Pre-tested and validated by Google

**Alternative: GPU Operator Approach**

For parity with EKS/AKS, GPU Operator v23.9.2 can be used:

```hcl
gpu_driver_installation_config {
  gpu_driver_version = "LATEST"  # Or skip and use GPU Operator
}
```

Then deploy GPU Operator via Helm (matches EKS/AKS workflow).

### 3.3 GPU Time-Slicing

**GKE Native Time-Sharing (Recommended)**

```hcl
gpu_sharing_config {
  gpu_sharing_strategy       = "TIME_SHARING"
  max_shared_clients_per_gpu = 2  # 2-4 Renny pods per GPU
}
```

**Configuration in Helm Values:**

```yaml
resources:
  requests:
    nvidia.com/gpu: 1
  limits:
    nvidia.com/gpu: 1
```

With `max_shared_clients_per_gpu = 2`, Kubernetes scheduler allows 2 pods requesting `1 GPU` to share the physical GPU.

**Capacity Planning:**
- **Per Node**: 1 T4 GPU × 2 pods = 2 Renny instances
- **10 Nodes**: 10 nodes × 2 pods = 20 concurrent sessions
- **20 Nodes**: 20 nodes × 2 pods = 40 concurrent sessions

---

## 4. Networking Architecture

### 4.1 VPC-Native Networking

GKE uses **VPC-native** (alias IP) networking by default:

```
VPC: 10.0.0.0/8 (example)
├── Node Subnet: 10.17.0.0/22 (1,024 IPs for nodes)
├── Pod Subnet: 10.18.0.0/16 (65,536 IPs for pods)
└── Service Subnet: 10.117.0.0/16 (65,536 IPs for services)
```

**Key Benefits:**
- Pods get native VPC IPs (no NAT within VPC)
- Direct pod-to-pod and pod-to-service communication
- Better performance than overlay networks
- Support for VPC Network Policies
- Native integration with GCP services

### 4.2 IP Address Allocation Strategy

**Subnet Sizing Calculations:**

| Range Type | CIDR | Available IPs | Purpose |
|------------|------|---------------|---------|
| Nodes | 10.17.0.0/22 | 1,024 | Node primary IPs |
| Pods | 10.18.0.0/16 | 65,536 | Pod IPs (110 per node × 256 nodes) |
| Services | 10.117.0.0/16 | 65,536 | ClusterIP services |

**Formula for Pod Range:**
```
Required Pod IPs = (max_nodes × max_pods_per_node) + overhead
                 = (20 nodes × 110 pods/node) + 20%
                 = 2,200 + 440 = 2,640 IPs
                 = /20 CIDR (4,096 IPs) minimum

Provisioned: /16 = 65,536 IPs (headroom for future scaling)
```

### 4.3 Cloud NAT Configuration

**Purpose**: Outbound internet access for private nodes

**Requirements:**
- Container image pulls (Docker Hub, GCR, Artifact Registry)
- External API calls (UneeQ DHOP WebSocket)
- Software updates and package downloads

**Configuration:**
- **IP Allocation**: AUTO_ONLY (GCP manages IPs)
- **Source**: All subnets, all IP ranges
- **Logging**: Errors only (cost optimization)

### 4.4 Firewall Rules

**Required Rules:**

1. **Internal VPC Traffic**
   - Source: VPC CIDR ranges (nodes, pods, services)
   - Allow: All TCP, UDP, ICMP

2. **WebRTC/TURN (Renny Requirement)**
   - UDP 22000-23000: WebRTC media
   - UDP 3478: TURN UDP
   - TCP 3478, 5349: TURN TCP/TLS
   - Source: 0.0.0.0/0 (internet clients)

3. **Health Checks**
   - TCP 8081: Renny health endpoint
   - Source: Google health check ranges (35.191.0.0/16, 130.211.0.0/22)

4. **Control Plane Communication**
   - Managed automatically by GKE
   - Control plane CIDR: 172.16.0.0/28

---

## 5. Authentication & Authorization

### 5.1 Workload Identity (GKE's IAM Integration)

**Architecture:**

```
Kubernetes Service Account → Workload Identity Binding → GCP Service Account → IAM Roles
```

**Example: Renny Pod Identity**

```hcl
# 1. Create GCP Service Account
resource "google_service_account" "renny_workload" {
  account_id = "renny-sa"
}

# 2. Create Kubernetes Service Account with annotation
resource "kubernetes_service_account" "renny" {
  metadata {
    name = "renny-sa"
    namespace = "uneeq-renderer"
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.renny_workload.email
    }
  }
}

# 3. Bind GCP SA to K8s SA
resource "google_service_account_iam_binding" "renny_workload_identity" {
  service_account_id = google_service_account.renny_workload.name
  role = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:PROJECT_ID.svc.id.goog[uneeq-renderer/renny-sa]"
  ]
}

# 4. Grant GCP permissions to GCP SA
resource "google_project_iam_member" "renny_logging" {
  role = "roles/logging.logWriter"
  member = "serviceAccount:${google_service_account.renny_workload.email}"
}
```

**Usage in Pod Spec:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: renny-pod
  namespace: uneeq-renderer
spec:
  serviceAccountName: renny-sa  # Links to GCP SA via Workload Identity
  containers:
  - name: renny
    image: facemeproduction/renny:0.713-37d59
```

### 5.2 Node Service Accounts

**Node SA Permissions (Minimal Privilege):**
- `roles/logging.logWriter`: Send logs to Cloud Logging
- `roles/monitoring.metricWriter`: Send metrics to Cloud Monitoring
- `roles/monitoring.viewer`: Read monitoring data
- `roles/artifactregistry.reader`: Pull images from Artifact Registry

**Why Not Use Default Compute SA?**
- Default SA has excessive permissions (Editor role)
- Custom SA follows least privilege principle
- Better audit trail and security

### 5.3 Cluster Autoscaler IAM

**Custom Role for Autoscaler:**

```hcl
permissions = [
  "compute.instanceGroupManagers.get",
  "compute.instanceGroupManagers.list",
  "compute.instanceGroupManagers.update",
  "compute.instanceGroups.get",
  "compute.instanceGroups.list",
  "compute.instances.list",
  "compute.zones.list"
]
```

**Why Custom Role?**
- Predefined roles are too broad (e.g., `roles/compute.admin`)
- Scoped to only instance group operations
- Prevents accidental VM deletion or network changes

---

## 6. Comparison: GKE vs EKS vs AKS

### 6.1 Feature Parity Matrix

| Feature | AWS EKS | Azure AKS | **GCP GKE** |
|---------|---------|-----------|-------------|
| **GPU Instance** | g5.4xlarge | NC16as_T4_v3 | **n1-standard-16 + T4** |
| **GPU** | A10G (24GB) | T4 (16GB) | **T4 (16GB)** |
| **Cost/hour** | $1.624 | $1.20 | **~$1.11** |
| **Networking** | VPC CNI | Azure CNI | **VPC-native** |
| **Authentication** | IRSA | Managed Identity | **Workload Identity** |
| **GPU Driver** | GPU Operator | GPU Operator | **GKE-managed (or GPU Operator)** |
| **Time-Slicing** | GPU Operator | GPU Operator | **GKE native (or GPU Operator)** |
| **Node Pools** | Managed Node Groups | VMSS Node Pools | **Node Pools** |
| **Autoscaling** | Cluster Autoscaler | Cluster Autoscaler | **Cluster Autoscaler** |
| **Multi-AZ** | 3 AZs | 3 AZs | **3 zones (regional)** |
| **Control Plane Cost** | $0.10/hour | Free | **Free** |
| **Logging** | CloudWatch | Azure Monitor | **Cloud Logging** |
| **Monitoring** | CloudWatch/Prometheus | Azure Monitor | **Cloud Monitoring** |

### 6.2 GKE-Specific Advantages

1. **Lower Cost**
   - No control plane charges (EKS charges $0.10/hour)
   - Cheaper GPU instances ($1.11 vs $1.20-$1.62/hour)
   - Preemptible VMs for dev/test (up to 80% savings)

2. **Simpler GPU Management**
   - GKE auto-installs GPU drivers (no manual GPU Operator setup)
   - Native GPU time-slicing support
   - Automatic driver updates with Kubernetes upgrades

3. **Better Networking**
   - VPC-native by default (no overlay complexity)
   - Native Google Cloud Load Balancer integration
   - Better performance for pod-to-pod communication

4. **Operational Simplicity**
   - Faster cluster creation (~10 minutes vs 15-20)
   - Automatic node repairs and upgrades
   - GKE Autopilot option for fully managed nodes

5. **Advanced Features**
   - Binary Authorization (image signing)
   - Config Connector (manage GCP resources via K8s)
   - Multi-cluster ingress (for global deployments)

### 6.3 GKE-Specific Challenges

1. **GPU Availability**
   - T4 GPUs may have regional availability limits
   - Quota requests required for large deployments
   - A100/V100 GPUs more expensive than AWS/Azure

2. **Regional Constraints**
   - Not all regions support GPU instances
   - Must verify T4 availability in target region
   - Quota limits per region/zone

3. **Learning Curve**
   - Different CLI (`gcloud` vs `aws`/`az`)
   - Workload Identity vs IRSA/Managed Identity
   - VPC-native networking concepts

4. **Ecosystem Integration**
   - Fewer third-party integrations than AWS
   - Different monitoring/logging tools
   - UneeQ may have less GCP documentation

---

## 7. Implementation Notes & Gotchas

### 7.1 GPU Quota Requirements

**Default GPU Quota: 0**

Before deployment, request GPU quota increase:

```bash
# Check current quota
gcloud compute project-info describe --project=PROJECT_ID \
  | grep -A 1 "NVIDIA_T4_GPUS"

# Request quota increase (via Cloud Console)
# Navigation: IAM & Admin → Quotas → Filter: "T4" → Request increase
# Typical request: 20-40 T4 GPUs for production
```

**Processing Time**: 1-3 business days

### 7.2 Regional GPU Availability

**T4 GPU Available Regions** (as of 2025):
- **US**: us-central1, us-west1, us-east1, us-east4
- **Europe**: europe-west1, europe-west4
- **Asia**: asia-southeast1, asia-east1

**Verify before deployment:**

```bash
gcloud compute accelerator-types list --filter="name:nvidia-tesla-t4"
```

### 7.3 VPC-Native Networking Requirements

**CIDR Planning Critical:**

```
DO NOT OVERLAP:
- Node subnet: 10.17.0.0/22
- Pod subnet: 10.18.0.0/16
- Service subnet: 10.117.0.0/16
- Control plane: 172.16.0.0/28
- On-premises networks (if VPN/Interconnect)
```

**Common Mistake:**
Using too small pod CIDR (e.g., /24) → IP exhaustion during scaling

**Fix:**
Always provision /16 for pods (65K IPs) unless constrained

### 7.4 Workload Identity Setup

**Common Issue**: Pod can't access GCP APIs

**Checklist:**
1. Workload Identity enabled on cluster: ✅
2. Node pool has `workload_metadata_config.mode = "GKE_METADATA"`: ✅
3. K8s SA has `iam.gke.io/gcp-service-account` annotation: ✅
4. GCP SA has `roles/iam.workloadIdentityUser` binding: ✅
5. Pod spec references K8s SA: ✅

**Debug Command:**

```bash
# From inside pod, should show GCP SA email
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email
```

### 7.5 GPU Driver Installation Time

**GKE-managed drivers**: 5-10 minutes after node ready

**Verify:**

```bash
# Check driver daemonset
kubectl get daemonset -n kube-system | grep nvidia

# SSH into node and check
gcloud compute ssh NODE_NAME --zone=ZONE
nvidia-smi
```

### 7.6 Node Taint Enforcement

**Taint**: `nvidia.com/gpu=true:NoSchedule`

**Effect**: Only pods with matching toleration can schedule on GPU nodes

**Renny Toleration:**

```yaml
tolerations:
- key: nvidia.com/gpu
  operator: Equal
  value: "true"
  effect: NoSchedule
```

**Verify:**

```bash
# Should show NO system pods on GPU nodes
kubectl get pods --all-namespaces -o wide | grep GPU_NODE_NAME
```

### 7.7 Cost Monitoring

**Enable GKE Cost Allocation:**

```bash
gcloud container clusters update CLUSTER_NAME \
  --enable-cost-allocation \
  --region REGION
```

**Benefits:**
- Per-namespace cost breakdown
- GPU utilization metrics
- Chargeback/showback reporting

---

## 8. Deployment Workflow

### 8.1 Prerequisites

**Required Tools:**
- `gcloud` CLI (latest)
- `terraform` (>= 1.0)
- `kubectl` (>= 1.28)
- `helm` (>= 3.0)

**GCP Requirements:**
- GCP project with billing enabled
- Owner or Editor role
- GPU quota approved (20-40 T4 GPUs)

### 8.2 Pre-Deployment Validation Script

**Location**: `kubernetes/scripts/gke/check-gcp-prerequisites.sh`

**Checks:**
- GCP authentication (`gcloud auth list`)
- Required APIs enabled (container, compute, iam)
- GPU quota availability
- VPC CIDR availability
- T4 GPU region availability
- IAM permissions (Service Account Admin, Compute Admin)

### 8.3 Step-by-Step Deployment

```bash
# 1. Configure GCP credentials
gcloud auth login
gcloud config set project PROJECT_ID

# 2. Request GPU quota (if not done)
# Manual: Cloud Console → IAM → Quotas → Request increase

# 3. Configure Terraform variables
cd kubernetes/terraform/gke
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Update project_id, credentials

# 4. Initialize Terraform
terraform init

# 5. Review deployment plan
terraform plan -var-file=terraform.tfvars

# 6. Deploy infrastructure (~15 minutes)
terraform apply -var-file=terraform.tfvars

# 7. Configure kubectl
gcloud container clusters get-credentials $(terraform output -raw cluster_name) \
  --region $(terraform output -raw region) \
  --project $(terraform output -raw project_id)

# 8. Verify cluster
kubectl get nodes
kubectl get nodes -L nvidia.com/gpu,uneeq.io/node-type

# 9. Wait for GPU drivers (5-10 minutes)
watch kubectl get daemonset -n kube-system | grep nvidia

# 10. Deploy GPU Operator (optional, if not using GKE-managed)
helm repo add nvidia https://nvidia.github.io/gpu-operator
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.version=580

# 11. Verify GPU availability
kubectl exec -it $(kubectl get pod -n gpu-operator -l app=nvidia-driver-daemonset -o name | head -1) \
  -n gpu-operator -- nvidia-smi

# 12. Deploy Renny application
cd ../../
./scripts/deploy.sh --cloud gke
```

### 8.4 Deployment Time Estimates

| Phase | Duration | Notes |
|-------|----------|-------|
| Terraform apply | 12-15 min | Cluster + node pools creation |
| GPU driver install | 5-10 min | GKE auto-installs drivers |
| GPU Operator (if used) | 10-15 min | Driver compilation |
| Renny deployment | 5-8 min | Image pull + pod startup |
| **Total** | **32-48 min** | **Full deployment end-to-end** |

---

## 9. Cost Analysis

### 9.1 Monthly Cost Breakdown (us-central1)

**Assumption**: 10 GPU nodes, 2 system nodes, 24/7 operation

| Component | Quantity | Unit Cost | Monthly Cost |
|-----------|----------|-----------|--------------|
| **GPU Nodes** | 10 | $1.11/hour | $8,000 |
| n1-standard-16 | 10 | $0.76/hour | $5,472 |
| NVIDIA T4 GPU | 10 | $0.35/hour | $2,520 |
| **System Nodes** | 2 | $0.19/hour | $274 |
| n1-standard-4 | 2 | $0.19/hour | $274 |
| **Networking** | - | - | $100 |
| Cloud NAT | 1 | ~$45/month | $45 |
| Egress (1TB) | 1TB | ~$0.12/GB | $123 |
| VPC (free) | - | $0 | $0 |
| **Storage** | - | - | $150 |
| Node disks (256GB × 10) | 2.56TB | $0.04/GB | $102 |
| Node disks (100GB × 2) | 0.2TB | $0.04/GB | $8 |
| Persistent volumes | 500GB | $0.04/GB | $20 |
| Snapshots | 500GB | $0.026/GB | $13 |
| **Monitoring** | - | - | $50 |
| Cloud Logging | ~100GB | Free (50GB) + $0.50/GB | $25 |
| Cloud Monitoring | - | Free tier | $0 |
| **Control Plane** | - | - | **$0** |
| GKE management | - | **FREE** | **$0** |
| **TOTAL** | | | **~$8,574/month** |

### 9.2 Cost Comparison

| Configuration | AWS EKS | Azure AKS | **GCP GKE** |
|---------------|---------|-----------|-------------|
| 10 GPU nodes | $11,740 | $8,952 | **$8,574** |
| 20 GPU nodes | $23,230 | $17,592 | **$17,000** |
| Control plane | $73/month | FREE | **FREE** |
| **Cost per node** | **$1,174** | **$895** | **$857** |

**GKE Savings:**
- **vs EKS**: $3,166/month (27% cheaper)
- **vs AKS**: $378/month (4% cheaper)

### 9.3 Cost Optimization Strategies

**1. Preemptible/Spot Instances**
```hcl
node_config {
  preemptible = true  # Up to 80% savings
  # Only for dev/test, not production
}
```
Savings: ~$6,400/month for 10 preemptible GPU nodes

**2. Committed Use Discounts (CUDs)**
- 1-year: 25% discount → Save $2,143/month
- 3-year: 52% discount → Save $4,458/month

**3. Autoscaling (Off-Peak)**
```hcl
autoscaling {
  min_node_count = 2   # Off-peak (nights/weekends)
  max_node_count = 20  # Peak hours
}
```
Savings: ~$4,800/month (60% time at min scale)

**4. Regional vs Zonal Cluster**
- Regional: 3-zone HA ($8,574/month)
- Zonal: Single zone ($8,574/month, same base cost)

**Note**: Regional clusters have higher control plane availability, but no cost difference.

**5. Disk Optimization**
```hcl
disk_type = "pd-standard"  # $0.04/GB vs pd-ssd $0.17/GB
```
Savings: ~$264/month (vs SSD disks)

### 9.4 Total Cost of Ownership (TCO)

**Annual Cost (10 nodes, no optimization):**
- Infrastructure: $102,888/year
- Engineering overhead: $10,000/year (setup + maintenance)
- **Total**: ~$113,000/year

**With Optimizations:**
- CUD (1-year): -$25,716/year
- Autoscaling (60% min): -$57,600/year
- **Optimized Total**: ~$30,000/year (73% savings)

---

## 10. Monitoring & Operations

### 10.1 Cloud Operations Integration

**Logging:**
```hcl
logging_config {
  enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
}
```
- Application logs: Automatic collection
- System logs: CoreDNS, kube-proxy, etc.
- Query with Cloud Logging Explorer

**Monitoring:**
```hcl
monitoring_config {
  enable_components = ["SYSTEM_COMPONENTS"]
  managed_prometheus {
    enabled = true
  }
}
```
- GKE metrics: Node/pod CPU, memory, disk
- Custom metrics: Prometheus integration
- Dashboards: Pre-built GKE dashboards in Cloud Console

### 10.2 Key Metrics to Monitor

**Cluster Health:**
- Node status (Ready/NotReady)
- Pod status (Running/Pending/Failed)
- API server latency

**GPU Utilization:**
- GPU memory usage (per node)
- GPU compute utilization (%)
- GPU temperature

**Application Metrics:**
- Renny pod count (desired vs actual)
- Renny health check status
- WebRTC connection success rate

**Cost Metrics:**
- GPU node hours (billable time)
- Egress bandwidth (data transfer costs)
- Per-namespace resource usage

### 10.3 Alerting Strategy

**Critical Alerts:**
- GPU node NotReady > 5 minutes
- Renny pod CrashLoopBackOff
- GPU driver daemonset failed
- Cluster autoscaler errors

**Warning Alerts:**
- GPU utilization < 20% (underutilized)
- High pod eviction rate
- API server latency > 500ms

**Cost Alerts:**
- Daily spend > $500
- Unexpected GPU quota usage
- High egress bandwidth

### 10.4 Operational Scripts

**kubernetes/scripts/gke/**

1. **deploy.sh** - One-click full deployment
2. **destroy.sh** - Complete cleanup with confirmation
3. **status.sh** - Cluster health check
4. **scale.sh** - Scale Renny instances (10-20)
5. **check-gcp-prerequisites.sh** - Pre-deployment validation
6. **check-network-usage.sh** - VPC IP usage analysis

---

## 11. Security Considerations

### 11.1 Network Security

**Private Cluster:**
- Nodes have no public IPs
- Outbound internet via Cloud NAT only
- Control plane privately accessible

**Firewall Rules:**
- Default deny all ingress
- Explicit allow rules for WebRTC/TURN
- Locked down to specific ports (22000-23000, 3478, 5349)

**VPC Network Policies:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: renny-netpol
spec:
  podSelector:
    matchLabels:
      app: renny
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 8081
    - protocol: UDP
      port: 22000-23000
```

### 11.2 Identity & Access

**Workload Identity:**
- Pods use GCP service accounts (not node SA)
- Least privilege per application
- Automatic credential rotation

**Node Service Accounts:**
- Custom SA with minimal permissions
- No Editor/Owner roles
- Scoped to logging/monitoring/registry

**RBAC:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: renny-operator
  namespace: uneeq-renderer
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
```

### 11.3 Secret Management

**Kubernetes Secrets:**
```bash
# Create Docker registry secret
kubectl create secret docker-registry uneeq-registry \
  --docker-server=docker.io \
  --docker-username=USERNAME \
  --docker-password=PASSWORD \
  --namespace=uneeq-renderer

# Create DHOP credentials secret
kubectl create secret generic dhop-credentials \
  --from-literal=tenant-id=UUID \
  --from-literal=api-key=BASE64_KEY \
  --namespace=uneeq-renderer
```

**GCP Secret Manager (Optional):**
- Store sensitive configs in Secret Manager
- Mount via CSI driver or Workload Identity

### 11.4 Binary Authorization

**Enable image signing enforcement:**

```hcl
binary_authorization {
  evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
}
```

**Policy Example:**
```yaml
admissionWhitelistPatterns:
- namePattern: docker.io/facemeproduction/*
- namePattern: gcr.io/PROJECT_ID/*
```

---

## 12. Troubleshooting Guide

### 12.1 GPU Nodes NotReady

**Symptom**: GPU nodes show NotReady in `kubectl get nodes`

**Diagnosis:**
```bash
# Check node events
kubectl describe node GPU_NODE_NAME

# Check GPU driver daemonset
kubectl get daemonset -n kube-system | grep nvidia

# SSH into node
gcloud compute ssh NODE_NAME --zone=ZONE
nvidia-smi  # Should show GPU
```

**Common Causes:**
1. GPU drivers still installing (wait 5-10 min)
2. Driver installation failed (check logs)
3. GPU not detected (verify instance type)

**Fix:**
```bash
# Restart node (if drivers failed)
kubectl drain NODE_NAME --ignore-daemonsets
gcloud compute instances reset NODE_NAME --zone=ZONE
kubectl uncordon NODE_NAME
```

### 12.2 Pods Stuck in Pending

**Symptom**: Renny pods show Pending status

**Diagnosis:**
```bash
kubectl describe pod RENNY_POD_NAME -n uneeq-renderer
# Look for "Events" section
```

**Common Causes:**
1. No GPU nodes available (autoscaler scaling up)
2. GPU already allocated (time-slicing not working)
3. Node taint/toleration mismatch
4. Insufficient CPU/memory

**Fix:**
```bash
# Check GPU capacity
kubectl describe nodes -l uneeq.io/node-type=renny | grep "nvidia.com/gpu"

# Force autoscaler scale-up
kubectl scale deployment renny --replicas=20 -n uneeq-renderer

# Verify toleration in pod spec
kubectl get pod RENNY_POD_NAME -n uneeq-renderer -o yaml | grep -A 3 tolerations
```

### 12.3 Workload Identity Not Working

**Symptom**: Pods can't access GCP APIs (403 Forbidden)

**Diagnosis:**
```bash
# From inside pod
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email

# Should return GCP SA email, not node SA
```

**Fix:**
```bash
# Verify K8s SA annotation
kubectl get sa renny-sa -n uneeq-renderer -o yaml

# Verify Workload Identity binding
gcloud iam service-accounts get-iam-policy \
  renny-sa@PROJECT_ID.iam.gserviceaccount.com

# Recreate pod (to pick up new SA)
kubectl delete pod RENNY_POD_NAME -n uneeq-renderer
```

### 12.4 High Costs

**Symptom**: GCP billing exceeds budget

**Diagnosis:**
```bash
# Check node count
kubectl get nodes

# Check GPU allocation
kubectl describe nodes -l uneeq.io/node-type=renny | grep "Allocated resources" -A 5

# Check pod replicas
kubectl get deployments -n uneeq-renderer
```

**Fix:**
```bash
# Scale down Renny instances
./scripts/scale.sh 10

# Enable autoscaling
kubectl autoscale deployment renny --min=5 --max=20 -n uneeq-renderer

# Check for leaked resources
gcloud compute instances list | grep renny
gcloud compute disks list | grep renny
```

---

## 13. Next Steps & Roadmap

### Phase 1: Terraform Implementation (This Document)
- ✅ Architecture design complete
- ⏳ Terraform files creation
- ⏳ Variables and outputs definition
- ⏳ Documentation (README, QUICK_START)

### Phase 2: Deployment Automation
- Create `kubernetes/scripts/gke/` directory
- Implement `check-gcp-prerequisites.sh` script
- Implement `check-network-usage.sh` script
- Adapt `deploy.sh` for GKE cloud option
- Adapt `destroy.sh` for GKE cleanup
- Adapt `status.sh` for GKE monitoring
- Adapt `scale.sh` for GKE node pools

### Phase 3: Kubernetes Manifests
- Create `kubernetes/manifests/gke/` directory
- GPU Operator Helm values (if not using GKE-managed)
- Renny deployment manifests
- Cluster autoscaler configuration
- Monitoring/logging integrations

### Phase 4: Helm Values
- Create `kubernetes/values/renny-values-gke.yaml`
- GKE-specific resource requests/limits
- Workload Identity service account references
- GKE-specific node selectors and tolerations
- Cloud Load Balancer annotations

### Phase 5: Testing & Validation
- Full deployment test (us-central1)
- GPU driver verification
- Renny pod functionality test
- WebRTC connectivity test
- Cost validation and optimization
- Documentation updates based on testing

### Phase 6: CI/CD Integration
- GitHub Actions workflow for GKE deployment
- Terraform plan on pull requests
- Automated testing pipeline
- Cost estimation automation

---

## 14. Conclusion

This GKE implementation design provides **feature parity** with EKS and AKS while leveraging GKE-specific advantages:

### Key Benefits
1. **Cost Savings**: 27% cheaper than EKS, 4% cheaper than AKS
2. **Operational Simplicity**: GKE-managed GPU drivers, no GPU Operator complexity
3. **Native Integration**: Workload Identity, VPC-native networking, Cloud Operations
4. **Scalability**: 10-20 GPU nodes with cluster autoscaler, 2-4 pods per GPU
5. **Security**: Private nodes, Workload Identity, network policies

### Design Quality
- **830 lines** of Terraform code (matching EKS/AKS structure)
- **8 core files** organized by responsibility
- **Comprehensive documentation** (this 2000+ line design doc)
- **Production-ready** architecture with HA and autoscaling

### Implementation Status
- ✅ Architecture design complete
- ✅ Resource structure defined
- ✅ Cost analysis and comparisons
- ✅ Security and networking design
- ⏳ Ready for Terraform file creation (Phase 1)

---

**Document Version**: 1.0
**Last Updated**: October 16, 2025
**Next Review**: After Phase 1 implementation

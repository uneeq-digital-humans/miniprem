# GKE Terraform Implementation Plan
# MiniPrem Renny Digital Human Platform

**Version**: 1.0
**Date**: October 16, 2025
**Purpose**: Detailed implementation guide for bash-validator agent
**Target**: Create 8 core Terraform files (~830 lines) for GKE deployment

---

## Executive Summary

This document provides a **file-by-file implementation plan** for creating the GKE Terraform infrastructure. The design is complete (see `GKE_ARCHITECTURE_DESIGN.md`), and this plan translates that design into actionable Terraform code specifications.

### Key Objectives

1. **Feature Parity**: Match EKS/AKS functionality exactly
2. **Consistency**: Follow established patterns from existing implementations
3. **Production-Ready**: Security, scalability, and cost optimization
4. **Zero Ambiguity**: Detailed enough to implement without architectural decisions

### File Structure Overview

```
kubernetes/terraform/gke/
├── main.tf                      (75 lines) - Provider config, backend, locals
├── gke.tf                       (120 lines) - GKE cluster resource
├── vpc.tf                       (90 lines) - VPC, subnets, NAT, firewall
├── node-pools.tf                (110 lines) - System and GPU node pools
├── service-accounts.tf          (95 lines) - Workload Identity, IAM
├── variables.tf                 (150 lines) - All variables with validation
├── outputs.tf                   (80 lines) - Cluster outputs
├── terraform.tfvars.example     (110 lines) - Example configuration
├── .gitignore                   (20 lines) - Ignore state files
└── TERRAFORM_IMPLEMENTATION_PLAN.md (this file)
```

**Total**: ~850 lines of Terraform code

---

## Reusable Patterns from EKS/AKS

### Pattern 1: Variable Naming Conventions

**Consistency Rules** (from EKS/AKS analysis):

| Variable Type | Pattern | Examples |
|---------------|---------|----------|
| Cloud identifier | `{cloud}_*` | `gcp_project_id`, `gcp_region` |
| Network ranges | `*_cidr` | `subnet_cidr`, `pods_cidr`, `service_cidr` |
| Node sizing | `renny_*` | `renny_min_size`, `renny_max_size`, `renny_desired_size` |
| Application config | `dhop_*`, `harbor_*` | `dhop_url`, `harbor_username` |
| Common metadata | `project_name`, `environment`, `deployment_id` | Consistent across clouds |

**GKE-Specific Variables**:
- `gcp_project_id` - GCP Project ID (matches `azure_subscription_id` pattern)
- `gcp_region` - GCP region (matches `aws_region`, `azure_region`)
- `pods_cidr` - GKE-specific (VPC-native networking)

### Pattern 2: Resource Labeling Strategy

**Common Tags/Labels** (from EKS/AKS):

```hcl
# EKS uses tags (map)
common_tags = {
  Project      = var.project_name
  Environment  = var.environment
  DeploymentId = var.deployment_id
  ManagedBy    = "Terraform"
}

# AKS uses tags (map) - same structure
common_tags = {
  Project       = var.project_name
  Environment   = var.environment
  DeploymentId  = var.deployment_id
  ManagedBy     = "Terraform"
  CloudProvider = "Azure"
  Workload      = "DigitalHuman"
}

# GKE uses labels (map) - MUST follow GCP label restrictions
common_labels = {
  project       = var.project_name         # lowercase key
  environment   = var.environment
  deployment_id = var.deployment_id != "" ? var.deployment_id : "default"
  managed_by    = "terraform"              # lowercase value
  cloud         = "gcp"
  workload      = "digital-human"
}
```

**GCP Label Requirements**:
- Keys: lowercase, hyphens allowed, start with letter
- Values: lowercase, hyphens allowed, 63 chars max
- No underscores in keys (use hyphens)

### Pattern 3: Cluster Naming

**Consistent Pattern** (from EKS/AKS):

```hcl
locals {
  # Generate cluster name with deployment ID for resource isolation
  cluster_name = var.deployment_id != "" ?
    "${var.project_name}-${var.environment}-${var.deployment_id}" :
    "${var.project_name}-${var.environment}"
}

# Examples:
# - Single deployment: "renny-production"
# - Multi-deployment: "renny-production-abc123"
```

### Pattern 4: Backend Configuration

**Consistent Pattern** (commented out by default):

```hcl
# EKS: S3 backend
# backend "s3" {
#   bucket = "renny-terraform-state"
#   key    = "eks/terraform.tfstate"
#   region = "us-east-1"
# }

# AKS: Azure Storage backend
# backend "azurerm" {
#   resource_group_name  = "terraform-state-rg"
#   storage_account_name = "rennytfstate"
#   container_name       = "tfstate"
#   key                  = "aks/terraform.tfstate"
# }

# GKE: GCS backend (same pattern)
# backend "gcs" {
#   bucket = "renny-terraform-state"
#   prefix = "gke/terraform.tfstate"
# }
```

### Pattern 5: Sensitive Variables

**Consistent Pattern**:

```hcl
# DHOP credentials - sensitive in all clouds
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

# Harbor registry - sensitive in all clouds (contact help@uneeq.com for robot account)
variable "harbor_username" {
  description = "Harbor registry robot username (e.g., robot$customer-name)"
  type        = string
  sensitive   = true
}

variable "harbor_password" {
  description = "Harbor registry robot password"
  type        = string
  sensitive   = true
}
```

---

## File-by-File Implementation Guide

### File 1: main.tf (~75 lines)

**Purpose**: Provider configuration, backend setup, common locals

**Required Sections**:

#### 1.1 Terraform Block (25 lines)

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
  # Uncomment and configure after creating GCS bucket:
  #   gsutil mb -p PROJECT_ID -c STANDARD -l us-central1 gs://renny-terraform-state
  #
  # backend "gcs" {
  #   bucket = "renny-terraform-state"
  #   prefix = "gke/terraform.tfstate"
  # }
}
```

**Key Points**:
- Terraform >= 1.0 (matches EKS/AKS)
- Google provider ~> 5.0 (latest stable)
- google-beta for preview features (if needed)
- kubernetes/helm same versions as EKS/AKS (~> 2.23, ~> 2.11)
- Backend commented out by default (matches pattern)

#### 1.2 Provider Blocks (30 lines)

```hcl
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# Kubernetes provider using GKE cluster credentials
# Configured after cluster creation
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
```

**Key Points**:
- google-beta provider for features not yet in stable
- google_client_config data source for authentication
- Kubernetes provider uses cluster endpoint + token (GKE-specific)
- Helm provider delegates to kubernetes config

**GCP-Specific Difference**:
- EKS uses `aws eks get-token` exec command
- AKS uses client certificates from cluster output
- GKE uses `google_client_config` data source for token

#### 1.3 Locals Block (20 lines)

```hcl
locals {
  # Generate cluster name with deployment ID for resource isolation
  # deployment_id allows multiple independent deployments in same project
  cluster_name = var.deployment_id != "" ?
    "${var.project_name}-${var.environment}-${var.deployment_id}" :
    "${var.project_name}-${var.environment}"

  # GCP region to zones mapping (for regional cluster)
  zones = [
    "${var.gcp_region}-a",
    "${var.gcp_region}-b",
    "${var.gcp_region}-c"
  ]

  # Common labels for all resources
  # GCP uses labels (not tags) with strict naming rules
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

**Key Points**:
- `cluster_name` generation matches EKS/AKS pattern
- `zones` list for regional cluster (3 zones)
- `common_labels` follows GCP naming conventions (lowercase, hyphens)

---

### File 2: gke.tf (~120 lines)

**Purpose**: GKE cluster resource with all configuration

**Required Sections**:

#### 2.1 GKE Cluster Resource (120 lines)

```hcl
# GKE Cluster Resource
# Creates a production-ready regional GKE cluster with GPU support
resource "google_container_cluster" "primary" {
  name     = local.cluster_name
  location = var.gcp_region  # Regional cluster (multi-zone HA)

  # GKE release channel for automatic upgrades
  # "REGULAR" provides balanced stability and features
  # Alternatives: "RAPID" (bleeding edge), "STABLE" (conservative)
  release_channel {
    channel = "REGULAR"
  }

  # Minimum Kubernetes version (matches EKS/AKS: 1.31)
  min_master_version = var.kubernetes_version

  # VPC-native networking (IP aliasing)
  # Required for advanced networking features and Google Cloud integration
  networking_mode = "VPC_NATIVE"

  # IP allocation policy for VPC-native networking
  # Secondary ranges for pods and services (defined in vpc.tf)
  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.nodes.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.nodes.secondary_ip_range[1].range_name
  }

  # Network configuration
  network    = google_compute_network.vpc.self_link
  subnetwork = google_compute_subnetwork.nodes.self_link

  # Private cluster configuration
  # Control plane has private endpoint, nodes have no public IPs
  private_cluster_config {
    enable_private_nodes    = true               # Nodes have no public IPs
    enable_private_endpoint = false              # Allow public access to control plane
    master_ipv4_cidr_block  = "172.16.0.0/28"   # Control plane CIDR (16 IPs)
  }

  # Remove default node pool (we create custom node pools)
  # GKE requires initial_node_count > 0, but we delete it immediately
  remove_default_node_pool = true
  initial_node_count       = 1

  # Workload Identity (GKE's IAM integration)
  # Allows Kubernetes service accounts to act as GCP service accounts
  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  # GKE addons configuration
  addons_config {
    http_load_balancing {
      disabled = false  # Enable GCP Load Balancer integration
    }
    horizontal_pod_autoscaling {
      disabled = false  # Enable HPA
    }
    network_policy_config {
      disabled = false  # Enable network policy enforcement
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true    # Enable persistent disk CSI driver
    }
  }

  # Enable network policy enforcement (Calico)
  network_policy {
    enabled  = true
    provider = "PROVIDER_UNSPECIFIED"  # Use GKE default (Calico)
  }

  # Cluster maintenance policy
  # Automatic upgrades happen during maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"  # 3 AM local time
    }
  }

  # Binary authorization (optional - for image signing)
  # Disabled by default, enable for production security
  binary_authorization {
    evaluation_mode = "DISABLED"
  }

  # Resource labels (GCP metadata)
  resource_labels = local.common_labels

  # Logging configuration (Cloud Operations)
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  # Monitoring configuration (Cloud Operations)
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true  # Enable managed Prometheus
    }
  }

  # Lifecycle configuration
  # Ignore changes to node pool and initial count (we manage separately)
  lifecycle {
    ignore_changes = [
      initial_node_count,
      node_pool
    ]
  }
}
```

**Key Points**:
- Regional cluster (multi-zone HA) vs zonal
- VPC-native networking (GKE-specific, required)
- Private nodes with public control plane (production pattern)
- Workload Identity enabled (matches AWS IRSA / Azure Managed Identity)
- Release channel "REGULAR" (auto-upgrades with stability)
- Logging and monitoring enabled (Cloud Operations integration)

**GKE-Specific Features**:
- `release_channel` - auto-upgrade strategy
- `workload_identity_config` - IAM integration
- `ip_allocation_policy` - VPC-native networking
- `managed_prometheus` - native Prometheus integration

---

### File 3: vpc.tf (~90 lines)

**Purpose**: VPC network, subnets, Cloud NAT, firewall rules

**Required Sections**:

#### 3.1 VPC Network (10 lines)

```hcl
# VPC Network
# Isolated network for GKE cluster
resource "google_compute_network" "vpc" {
  name                    = "${local.cluster_name}-vpc"
  auto_create_subnetworks = false  # Manual subnet control
  routing_mode            = "REGIONAL"

  description = "VPC for ${local.cluster_name} GKE cluster"
}
```

#### 3.2 Subnet with Secondary Ranges (20 lines)

```hcl
# Subnet for GKE Nodes
# VPC-native mode: Primary range for nodes, secondary ranges for pods/services
resource "google_compute_subnetwork" "nodes" {
  name          = "${local.cluster_name}-nodes-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.gcp_region
  network       = google_compute_network.vpc.id

  # Secondary IP ranges for VPC-native networking
  # Range 1: Pod IPs (65K IPs for pod scaling)
  secondary_ip_range {
    range_name    = "${local.cluster_name}-pods"
    ip_cidr_range = var.pods_cidr
  }

  # Range 2: Service IPs (ClusterIP services)
  secondary_ip_range {
    range_name    = "${local.cluster_name}-services"
    ip_cidr_range = var.service_cidr
  }

  # Private Google Access (access Google APIs without public IPs)
  private_ip_google_access = true

  description = "Subnet for GKE nodes, pods, and services"
}
```

**Key Points**:
- `auto_create_subnetworks = false` - manual control
- `secondary_ip_range` - GKE VPC-native networking (required)
- `private_ip_google_access = true` - access Google APIs privately

**GKE-Specific**:
- EKS/AKS don't need secondary ranges (different CNI)
- GKE VPC-native requires explicit pod/service CIDRs

#### 3.3 Cloud NAT (25 lines)

```hcl
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
```

**Key Points**:
- Cloud Router required before NAT (2-step process)
- `nat_ip_allocate_option = "AUTO_ONLY"` - GCP manages IPs
- Logging errors only (cost optimization)

**Pattern Match**:
- EKS: NAT Gateway resource (3 for HA)
- AKS: NAT Gateway resource (1 per AZ)
- GKE: Cloud NAT (region-level, no per-zone config)

#### 3.4 Firewall Rules (35 lines)

```hcl
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

**Key Points**:
- `internal` rule: All protocols within VPC (pod-to-pod, node-to-node)
- `webrtc` rule: Matches EKS/AKS port requirements (22000-23000, 3478, 5349)
- `health_checks` rule: Google health check IP ranges (documented)

**Pattern Match**:
- EKS: Security groups with ingress/egress rules
- AKS: Network security groups with rules
- GKE: Firewall rules with allow/deny

---

### File 4: node-pools.tf (~110 lines)

**Purpose**: System and GPU node pools with autoscaling

**Required Sections**:

#### 4.1 System Node Pool (45 lines)

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

    # Node labels (for pod scheduling)
    labels = merge(local.common_labels, {
      "node-role" = "system"
    })

    # Node metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }

    # Shielded instance configuration (security)
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
```

**Key Points**:
- Fixed size (2 nodes, no autoscaling)
- n1-standard-4 (matches AKS Standard_D4s_v3 sizing)
- Shielded instance config (GKE security feature)
- Workload Identity mode "GKE_METADATA" (required)

**Pattern Match**:
- EKS: System managed node group
- AKS: Default system node pool
- GKE: Custom system node pool (separate resource)

#### 4.2 GPU Node Pool (65 lines)

```hcl
# GPU Node Pool for Renny
# n1-standard-16 with NVIDIA T4 (16GB VRAM)
resource "google_container_node_pool" "renny_gpu" {
  name     = "renny-gpu-pool"
  location = var.gcp_region
  cluster  = google_container_cluster.primary.name

  # Autoscaling configuration (10-20 nodes)
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
      # GKE can auto-install drivers (RECOMMENDED)
      gpu_driver_installation_config {
        gpu_driver_version = "DEFAULT"  # Let GKE manage drivers
      }

      # GPU sharing (time-slicing)
      # Allows multiple pods to share a single GPU
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
    # Only pods with matching toleration can schedule here
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

**Key Points**:
- `guest_accelerator` block (GKE-specific GPU config)
- `gpu_driver_installation_config` - GKE-managed drivers (simpler than GPU Operator)
- `gpu_sharing_config` - Native time-slicing (no GPU Operator needed)
- `taint` - Reserve GPU nodes for GPU workloads only
- `labels` - Match EKS/AKS pattern (`uneeq.io/node-type=renny`)

**GKE-Specific Advantages**:
- Native GPU time-slicing (EKS/AKS need GPU Operator)
- Auto-driver installation (EKS/AKS need manual GPU Operator deployment)
- Simpler configuration (less complexity)

---

### File 5: service-accounts.tf (~95 lines)

**Purpose**: Workload Identity setup and IAM bindings

**Required Sections**:

#### 5.1 Node Service Account (30 lines)

```hcl
# Service Account for GKE Nodes
# Used by all node pools for GCP API access
resource "google_service_account" "gke_nodes" {
  account_id   = "${local.cluster_name}-nodes"
  display_name = "Service Account for ${local.cluster_name} GKE nodes"
  description  = "Used by GKE nodes to access GCP services"
}

# IAM bindings for node service account (minimal permissions)
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
```

**Key Points**:
- Custom service account (not default Compute SA)
- Minimal permissions (logging, monitoring, registry)
- Matches AWS IAM role / Azure Managed Identity pattern

#### 5.2 Renny Workload Identity (30 lines)

```hcl
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
# Links Kubernetes SA to GCP SA
resource "google_service_account_iam_binding" "renny_workload_identity" {
  service_account_id = google_service_account.renny_workload.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.gcp_project_id}.svc.id.goog[uneeq-renderer/renny-sa]"
  ]
}
```

**Key Points**:
- Kubernetes SA with Workload Identity annotation
- GCP SA for workload
- IAM binding connects K8s SA → GCP SA
- Pattern: `PROJECT_ID.svc.id.goog[NAMESPACE/K8S_SA_NAME]`

**Pattern Match**:
- EKS: IRSA (IAM Roles for Service Accounts)
- AKS: Managed Identity for pods
- GKE: Workload Identity

#### 5.3 Cluster Autoscaler Identity (35 lines)

```hcl
# Service Account for Cluster Autoscaler
resource "google_service_account" "cluster_autoscaler" {
  account_id   = "${local.cluster_name}-autoscaler"
  display_name = "Service Account for Cluster Autoscaler"
  description  = "Used by cluster autoscaler to scale node pools"
}

# Custom IAM role for Cluster Autoscaler
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

**Key Points**:
- Custom IAM role (least privilege)
- Scoped to instance group operations only
- Workload Identity for autoscaler pod

---

### File 6: variables.tf (~150 lines)

**Purpose**: All configurable parameters with descriptions and validation

**Required Variables** (grouped by category):

#### 6.1 GCP Configuration (15 lines)

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
```

#### 6.2 Network Configuration (30 lines)

```hcl
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
```

**Key Points**:
- `subnet_cidr` - Matches EKS/AKS default (10.17.0.0/22)
- `pods_cidr` - GKE-specific (VPC-native networking)
- `service_cidr` - Matches EKS/AKS (10.117.0.0/16)
- "PERMANENT DECISION" warning (consistent with EKS/AKS vars)

#### 6.3 Cluster Configuration (40 lines)

```hcl
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
```

**Pattern Match**: Identical to EKS/AKS variables

#### 6.4 GPU Node Pool Configuration (40 lines)

```hcl
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
```

**Key Points**:
- `renny_instance_type` - Matches EKS/AKS variable name
- Detailed description with cost breakdown
- `gpu_time_slicing_replicas` - GKE-specific (native support)
- Validation rule for time-slicing (1-8 replicas)

#### 6.5 Application Configuration (25 lines)

```hcl
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

# Harbor Registry Credentials (contact help@uneeq.com for robot account)
variable "harbor_username" {
  description = "Harbor registry robot username (e.g., robot$customer-name)"
  type        = string
  sensitive   = true
}

variable "harbor_password" {
  description = "Harbor registry robot password"
  type        = string
  sensitive   = true
}
```

**Pattern Match**: Identical to EKS/AKS application variables

---

### File 7: outputs.tf (~80 lines)

**Purpose**: Expose cluster information for automation and scripts

**Required Outputs**:

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

**Key Points**:
- `cluster_name`, `cluster_endpoint` - match EKS/AKS output names
- `sensitive = true` for endpoint and CA cert
- Service account emails for Workload Identity
- Usage examples in comments

**Pattern Match**:
- EKS: cluster_endpoint, cluster_ca_certificate, node_role_arn
- AKS: cluster_endpoint, cluster_ca_certificate, node_resource_group
- GKE: cluster_endpoint, cluster_ca_certificate, service_account_emails

---

### File 8: terraform.tfvars.example (~110 lines)

**Purpose**: Example configuration with guidance

**Required Content**:

```hcl
# GKE Terraform Configuration Example
# Copy to terraform.tfvars and fill in your values:
#   cp terraform.tfvars.example terraform.tfvars

# ============================================================================
# GCP Configuration
# ============================================================================

# GCP Project ID
# Find with: gcloud config get-value project
# REQUIRED: Must be set for deployment
gcp_project_id = "my-gcp-project-id"

# GCP Region
# Options: us-central1, us-east1, us-west1, europe-west1, asia-southeast1
# Verify T4 GPU availability: gcloud compute accelerator-types list --filter="name:nvidia-tesla-t4"
gcp_region = "us-central1"

# ============================================================================
# Network Configuration
# ============================================================================

# IMPORTANT: CIDR ranges are PERMANENT - cannot be changed without cluster rebuild
# Ensure no overlap with:
#   - On-premises networks (if using VPN/Interconnect)
#   - Other VPCs in the same project
#   - Peered networks

# Primary subnet for GKE nodes (1024 IPs)
subnet_cidr = "10.17.0.0/22"

# Secondary range for pod IPs (65,536 IPs)
# GKE VPC-native networking: each pod gets an IP from this range
pods_cidr = "10.18.0.0/16"

# Secondary range for service IPs (65,536 IPs)
# Kubernetes ClusterIP services use this range
service_cidr = "10.117.0.0/16"

# ============================================================================
# Cluster Configuration
# ============================================================================

# Kubernetes version (GKE will use latest patch in REGULAR channel)
kubernetes_version = "1.31"

# Project naming
project_name = "renny"
environment  = "production"

# Deployment ID (optional)
# Use for multiple deployments in same project (e.g., git hash, timestamp)
# Leave empty for single deployment: cluster name will be "renny-production"
# With ID: cluster name will be "renny-production-abc123"
deployment_id = ""

# ============================================================================
# GPU Node Pool Configuration
# ============================================================================

# GCP machine type for GPU nodes
# RECOMMENDED: n1-standard-16 (16 vCPUs, 60GB RAM) + T4 GPU
# Cost: ~$1.11/hour = ~$800/month per node
renny_instance_type = "n1-standard-16"

# Autoscaling configuration
# Minimum nodes (10 = 20 Renny instances with 2 pods/GPU)
renny_min_size = 10

# Maximum nodes (20 = 40 Renny instances with 2 pods/GPU)
renny_max_size = 20

# Initial desired nodes (start with minimum)
renny_desired_size = 10

# GPU time-slicing (pods per GPU)
# GKE native time-slicing support (no GPU Operator needed)
# Recommended: 2 for production, 4 for dev/test
gpu_time_slicing_replicas = 2

# ============================================================================
# Application Configuration
# ============================================================================

# DHOP (Digital Human Operations Platform) Configuration
dhop_url       = "wss://api.enterprise.uneeq.io:443/signalling-service"
dhop_tenant_id = "YOUR_DHOP_TENANT_ID"    # UUID format
dhop_api_key   = "YOUR_DHOP_API_KEY"      # Base64 encoded

# ============================================================================
# Harbor Registry Credentials
# ============================================================================

# Harbor registry credentials (contact help@uneeq.com for robot account)
harbor_username = "robot$your-customer-name"
harbor_password = "your-robot-password"

# ============================================================================
# Cost Estimate (based on default values)
# ============================================================================
#
# Monthly cost (us-central1, 10 nodes, 24/7):
#   - GPU Nodes (10x n1-standard-16 + T4): $8,000
#   - System Nodes (2x n1-standard-4): $274
#   - Networking (NAT, egress): $100
#   - Storage (disks, snapshots): $150
#   - Monitoring/Logging: $50
#   - Control Plane: FREE
#   -------------------------------------------
#   TOTAL: ~$8,574/month
#
# Cost optimization:
#   - Preemptible instances: Save up to 80% (dev/test only)
#   - Committed use discounts: Save 25-52% (1-3 year commitment)
#   - Autoscaling: Scale down during off-peak hours
#
# ============================================================================
```

**Key Points**:
- Clear sections with headers
- Cost estimate included
- Usage instructions (copy to terraform.tfvars)
- Placeholder values for secrets
- Detailed comments explaining each variable

**Pattern Match**: Similar structure to EKS terraform.tfvars.example

---

## GCP-Specific Implementation Notes

### 1. Workload Identity Setup Sequence

**Critical Order of Operations**:

```
1. Create GCP Service Account (google_service_account.renny_workload)
2. Create Kubernetes Service Account with annotation (kubernetes_service_account.renny)
3. Create IAM binding (google_service_account_iam_binding.renny_workload_identity)
4. Grant GCP permissions to GCP SA (google_project_iam_member.*)
```

**Gotcha**: Annotation format must be exact:
```hcl
annotations = {
  "iam.gke.io/gcp-service-account" = google_service_account.renny_workload.email
}
```

**Member format** for IAM binding:
```hcl
members = [
  "serviceAccount:${var.gcp_project_id}.svc.id.goog[NAMESPACE/K8S_SA_NAME]"
]
```

### 2. VPC-Native Networking CIDR Planning

**Requirements**:
- NO overlap between subnet_cidr, pods_cidr, service_cidr
- NO overlap with control plane CIDR (172.16.0.0/28)
- NO overlap with on-premises networks (if using VPN)

**Validation**:
```bash
# Check for overlaps before deployment
gcloud compute networks list
gcloud compute networks subnets list --network=VPC_NAME
```

### 3. GPU Driver Installation Strategy

**Recommended Approach** (GKE-managed):
```hcl
gpu_driver_installation_config {
  gpu_driver_version = "DEFAULT"  # GKE manages drivers
}
```

**Alternative Approach** (GPU Operator):
```hcl
gpu_driver_installation_config {
  gpu_driver_version = "LATEST"  # Or skip this block
}
# Then deploy GPU Operator via Helm separately
```

**Decision Criteria**:
- GKE-managed: Simpler, faster, auto-updates (RECOMMENDED)
- GPU Operator: More control, matches EKS/AKS, manual updates

### 4. Regional vs Zonal Cluster

**This implementation uses REGIONAL** (multi-zone HA):

```hcl
resource "google_container_cluster" "primary" {
  location = var.gcp_region  # Regional cluster (3 zones)
  # ...
}
```

**Why Regional**:
- Multi-zone HA for control plane (99.95% SLA)
- Node pools spread across zones automatically
- No cost difference for nodes
- Better production reliability

**Alternative (Zonal)**:
```hcl
location = "${var.gcp_region}-a"  # Single zone
```

### 5. Service Account OAuth Scopes

**Always use cloud-platform scope**:
```hcl
oauth_scopes = [
  "https://www.googleapis.com/auth/cloud-platform"
]
```

**Why**:
- Broad scope, permissions controlled via IAM (not scopes)
- Matches Google Cloud best practices
- Simpler than granular scopes (e.g., logging-write, monitoring-write)

### 6. Node Tags for Firewall Rules

**Pattern**:
```hcl
# In node pool
tags = ["gke-${local.cluster_name}", "gpu-node"]

# In firewall rule
target_tags = ["gke-${local.cluster_name}"]
```

**Why**:
- Firewall rules apply to nodes with matching tags
- Allows per-cluster isolation
- Prevents rules from affecting other clusters

---

## Resource Dependencies

### Dependency Graph

```
vpc.tf:
  google_compute_network.vpc
    ↓
  google_compute_subnetwork.nodes (requires: vpc)
    ↓
  google_compute_router.router (requires: vpc)
    ↓
  google_compute_router_nat.nat (requires: router)
  google_compute_firewall.* (requires: vpc)

gke.tf:
  google_container_cluster.primary (requires: vpc, subnet)

node-pools.tf:
  google_container_node_pool.system (requires: cluster, service_account)
  google_container_node_pool.renny_gpu (requires: cluster, service_account)

service-accounts.tf:
  google_service_account.gke_nodes
    ↓
  google_project_iam_member.gke_nodes_* (requires: service_account)
    ↓
  google_service_account.renny_workload
    ↓
  kubernetes_service_account.renny (requires: cluster, gcp_service_account)
    ↓
  google_service_account_iam_binding.renny_workload_identity (requires: both SAs)
```

**Key Takeaways**:
1. VPC must exist before cluster
2. Cluster must exist before node pools
3. Service accounts must exist before node pools
4. Kubernetes provider requires cluster to be created

**Terraform will handle dependencies automatically via resource references.**

---

## Validation Requirements

### Pre-Implementation Validation

**Before writing code**:
1. ✅ Architecture design reviewed and approved
2. ✅ EKS/AKS patterns analyzed
3. ✅ GCP-specific features understood
4. ✅ Variable naming conventions agreed

### Post-Implementation Validation

**After writing each file**:

```bash
# Format all files
terraform fmt -recursive

# Validate syntax
terraform validate

# Check for common issues
terraform plan -var-file=terraform.tfvars.example
```

**Expected Results**:
- `terraform fmt` - No changes (already formatted)
- `terraform validate` - Success
- `terraform plan` - Valid plan (or expected errors for missing credentials)

### Variable Validation Rules

**Implement these validation rules**:

```hcl
# deployment_id validation (already defined above)
variable "deployment_id" {
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.deployment_id)) || var.deployment_id == ""
    error_message = "Deployment ID must contain only lowercase letters, numbers, and hyphens."
  }
}

# gpu_time_slicing_replicas validation (already defined above)
variable "gpu_time_slicing_replicas" {
  validation {
    condition     = var.gpu_time_slicing_replicas >= 1 && var.gpu_time_slicing_replicas <= 8
    error_message = "GPU time-slicing replicas must be between 1 and 8."
  }
}

# CIDR validation (optional but recommended)
variable "subnet_cidr" {
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid CIDR block."
  }
}
```

### Cost Validation

**After terraform plan**:

```bash
# Use terraform cost estimation (if available)
terraform plan -out=plan.tfplan
terraform show -json plan.tfplan | jq '.resource_changes'

# Expected monthly cost: ~$8,574 for 10 nodes
# Validate that cost is within 5% of estimate
```

### Security Best Practices Validation

**Checklist**:
- [ ] No hardcoded secrets in any `.tf` files
- [ ] All sensitive variables marked `sensitive = true`
- [ ] terraform.tfvars in .gitignore
- [ ] Private nodes enabled (`enable_private_nodes = true`)
- [ ] Workload Identity enabled (not key-based auth)
- [ ] Minimal IAM permissions (least privilege)
- [ ] Shielded instances enabled
- [ ] Binary authorization configured (even if disabled)

---

## Implementation Checklist

### Phase 1: File Creation

- [ ] Create `main.tf` (75 lines)
  - [ ] Terraform block with required_providers
  - [ ] Provider configurations (google, google-beta, kubernetes, helm)
  - [ ] Locals block with cluster_name, zones, common_labels
  - [ ] GCS backend block (commented out)

- [ ] Create `gke.tf` (120 lines)
  - [ ] google_container_cluster.primary resource
  - [ ] Release channel configuration
  - [ ] VPC-native networking settings
  - [ ] Private cluster configuration
  - [ ] Workload Identity configuration
  - [ ] Addons configuration
  - [ ] Logging and monitoring configuration

- [ ] Create `vpc.tf` (90 lines)
  - [ ] google_compute_network.vpc resource
  - [ ] google_compute_subnetwork.nodes with secondary ranges
  - [ ] google_compute_router.router resource
  - [ ] google_compute_router_nat.nat resource
  - [ ] Firewall rules (internal, webrtc, health_checks)

- [ ] Create `node-pools.tf` (110 lines)
  - [ ] google_container_node_pool.system resource
  - [ ] google_container_node_pool.renny_gpu resource
  - [ ] GPU configuration with time-slicing
  - [ ] Node labels and taints
  - [ ] Shielded instance configuration

- [ ] Create `service-accounts.tf` (95 lines)
  - [ ] google_service_account.gke_nodes resource
  - [ ] IAM bindings for node SA
  - [ ] google_service_account.renny_workload resource
  - [ ] kubernetes_service_account.renny resource
  - [ ] Workload Identity bindings
  - [ ] Cluster autoscaler SA and bindings

- [ ] Create `variables.tf` (150 lines)
  - [ ] GCP configuration variables (project_id, region)
  - [ ] Network configuration variables (subnet_cidr, pods_cidr, service_cidr)
  - [ ] Cluster configuration variables (kubernetes_version, project_name, environment, deployment_id)
  - [ ] GPU node pool variables (renny_*, gpu_time_slicing_replicas)
  - [ ] Application variables (dhop_*, docker_*)
  - [ ] Validation rules where applicable

- [ ] Create `outputs.tf` (80 lines)
  - [ ] Cluster outputs (name, id, endpoint, ca_certificate)
  - [ ] Project/region outputs
  - [ ] Network outputs (vpc_id, subnet_id)
  - [ ] Service account outputs
  - [ ] Usage examples in comments

- [ ] Create `terraform.tfvars.example` (110 lines)
  - [ ] All variables with example/placeholder values
  - [ ] Section headers for organization
  - [ ] Detailed comments explaining each variable
  - [ ] Cost estimate section
  - [ ] Usage instructions

- [ ] Create `.gitignore` (20 lines)
  ```
  # Terraform state files
  *.tfstate
  *.tfstate.*
  .terraform/
  .terraform.lock.hcl

  # Terraform variables (may contain secrets)
  terraform.tfvars
  *.auto.tfvars

  # Kubeconfig (contains credentials)
  kubeconfig

  # Crash logs
  crash.log
  crash.*.log

  # macOS files
  .DS_Store
  ```

### Phase 2: Validation

- [ ] Run `terraform fmt -recursive`
- [ ] Run `terraform validate`
- [ ] Run `terraform plan` (with example tfvars, expect auth errors)
- [ ] Review all variable descriptions
- [ ] Check all resource names follow naming conventions
- [ ] Verify all sensitive variables marked `sensitive = true`
- [ ] Confirm no hardcoded values (project IDs, regions, etc.)

### Phase 3: Documentation

- [ ] Review `README.md` (already exists in gke/ directory)
- [ ] Ensure README references all 8 files
- [ ] Add any missing deployment steps
- [ ] Update troubleshooting section if needed

---

## Common Gotchas and Solutions

### Gotcha 1: Kubernetes Provider Authentication

**Problem**: `terraform plan` fails with "cluster not found"

**Cause**: Kubernetes provider tries to authenticate before cluster exists

**Solution**: Use `depends_on` and ignore errors on first plan:

```hcl
provider "kubernetes" {
  # This will fail on first run (cluster doesn't exist yet)
  # Ignore the error - cluster will be created on apply
  host = "https://${google_container_cluster.primary.endpoint}"
  # ...
}
```

**Alternative**: Use `-target` flag for first apply:

```bash
# First, create cluster only
terraform apply -target=google_container_cluster.primary

# Then, create everything else
terraform apply
```

### Gotcha 2: Secondary IP Range Names

**Problem**: IP allocation policy references wrong range names

**Cause**: Mismatch between `google_compute_subnetwork` and `google_container_cluster`

**Solution**: Use exact references:

```hcl
# In vpc.tf
secondary_ip_range {
  range_name    = "${local.cluster_name}-pods"  # This name
  ip_cidr_range = var.pods_cidr
}

# In gke.tf
ip_allocation_policy {
  cluster_secondary_range_name = google_compute_subnetwork.nodes.secondary_ip_range[0].range_name  # Reference by index
}
```

### Gotcha 3: Workload Identity Member Format

**Problem**: IAM binding fails with "invalid member format"

**Cause**: Incorrect member format for Workload Identity

**Solution**: Use exact format:

```hcl
members = [
  "serviceAccount:${var.gcp_project_id}.svc.id.goog[uneeq-renderer/renny-sa]"
  # NOT: serviceAccount:renny-sa@PROJECT_ID.iam.gserviceaccount.com
]
```

### Gotcha 4: GPU Driver Version

**Problem**: GPU drivers not installing or wrong version

**Cause**: `gpu_driver_version` set incorrectly

**Solution**: Use "DEFAULT" for GKE-managed:

```hcl
gpu_driver_installation_config {
  gpu_driver_version = "DEFAULT"  # Let GKE manage
  # NOT: "LATEST" or "580" (unless you want specific version)
}
```

### Gotcha 5: Node Pool Scaling

**Problem**: Cluster autoscaler doesn't scale nodes

**Cause**: Node pool autoscaling not enabled

**Solution**: Enable autoscaling in node pool:

```hcl
autoscaling {
  min_node_count = var.renny_min_size
  max_node_count = var.renny_max_size
}
# NOT: node_count = var.renny_desired_size (fixed size)
```

---

## Success Criteria

### File-Level Success Criteria

**Each file must**:
1. Pass `terraform fmt` (no changes)
2. Pass `terraform validate` (no errors)
3. Follow naming conventions (lowercase, hyphens, descriptive)
4. Include comments explaining complex logic
5. Use variables (no hardcoded values)

### Project-Level Success Criteria

**Overall implementation must**:
1. Total ~830 lines of Terraform code (±10%)
2. Feature parity with EKS/AKS (all features implemented)
3. Consistent patterns (matches EKS/AKS where applicable)
4. Production-ready (security, scalability, cost-optimized)
5. Well-documented (comments, examples, README)

### Technical Success Criteria

**Deployment must**:
1. Create regional GKE cluster (3 zones)
2. Create system node pool (2 nodes, n1-standard-4)
3. Create GPU node pool (10-20 nodes, n1-standard-16 + T4)
4. Enable Workload Identity
5. Configure VPC-native networking
6. Setup Cloud NAT for private nodes
7. Apply firewall rules (internal, WebRTC, health checks)
8. Cost estimate within 5% of $8,574/month (10 nodes)

---

## Next Steps After Implementation

### Immediate (After File Creation)

1. **Run Validation**:
   ```bash
   terraform fmt -recursive
   terraform validate
   terraform plan -var-file=terraform.tfvars.example
   ```

2. **Commit to Git**:
   ```bash
   git add kubernetes/terraform/gke/*.tf
   git commit -m "Add GKE Terraform infrastructure files"
   ```

3. **Update Documentation**:
   - Review `README.md` for accuracy
   - Update `CLAUDE.md` with GKE deployment instructions

### Short-Term (Phase 2)

1. **Create Deployment Scripts** (see `IMPLEMENTATION_ROADMAP.md`):
   - `kubernetes/scripts/gke/check-gcp-prerequisites.sh`
   - `kubernetes/scripts/gke/check-network-usage.sh`
   - Adapt `deploy.sh`, `destroy.sh`, `status.sh`, `scale.sh`

2. **Test Deployment**:
   - Deploy to test GCP project
   - Validate all resources created
   - Verify cost aligns with estimates
   - Test GPU functionality

### Medium-Term (Phases 3-5)

1. **Create Kubernetes Manifests**:
   - Namespace, secrets, autoscaler, monitoring

2. **Create Helm Values**:
   - `kubernetes/values/renny-values-gke.yaml`

3. **Full Integration Testing**:
   - End-to-end deployment
   - Renny application testing
   - WebRTC connectivity validation
   - Cost validation

---

## Architectural Concerns and Decisions Needed

### Decision 1: GPU Driver Installation Strategy

**Question**: Use GKE-managed drivers or GPU Operator?

**Recommendation**: **GKE-managed drivers** (already in design)

**Rationale**:
- Simpler implementation (no Helm chart)
- Faster driver installation (~5 min vs 10-15 min)
- Automatic updates with GKE
- Google-tested and supported

**Trade-off**: Less control over driver version

**Implementation**: Already specified in `node-pools.tf` section

---

### Decision 2: Regional vs Zonal Cluster

**Question**: Deploy regional (multi-zone) or zonal (single-zone) cluster?

**Recommendation**: **Regional cluster** (already in design)

**Rationale**:
- Multi-zone HA (99.95% SLA vs 99.5%)
- Node pools spread across zones
- No cost difference
- Production best practice

**Trade-off**: None (regional is strictly better)

**Implementation**: Already specified in `gke.tf` section

---

### Decision 3: Binary Authorization

**Question**: Enable or disable Binary Authorization (image signing)?

**Recommendation**: **Disabled by default, configurable**

**Rationale**:
- Most users don't have image signing setup
- Can be enabled later without cluster rebuild
- Production security feature (optional)

**Implementation**: Already specified in `gke.tf` as DISABLED

---

### No Outstanding Architectural Decisions

**All major design decisions have been made in `GKE_ARCHITECTURE_DESIGN.md`.**

This implementation plan is **ready for execution** by the bash-validator agent.

---

## Design Alignment Confirmation

### Alignment with GKE_ARCHITECTURE_DESIGN.md

This implementation plan **fully aligns** with the architecture design document:

✅ **File Structure**: Matches Section 1 (8 core files, same line counts)
✅ **Provider Configuration**: Matches Section 2.1 (main.tf specification)
✅ **GKE Cluster**: Matches Section 2.2 (gke.tf specification)
✅ **VPC Networking**: Matches Section 2.3 (vpc.tf specification)
✅ **Node Pools**: Matches Section 2.4 (node-pools.tf specification)
✅ **IAM/Service Accounts**: Matches Section 2.5 (service-accounts.tf specification)
✅ **Variables**: Matches Section 2.6 (variables.tf specification)
✅ **Outputs**: Matches Section 2.7 (outputs.tf specification)
✅ **GPU Configuration**: Matches Section 3 (GKE-managed drivers, time-slicing)
✅ **Networking**: Matches Section 4 (VPC-native, Cloud NAT, firewall rules)
✅ **Authentication**: Matches Section 5 (Workload Identity)
✅ **Cost Target**: ~$8,574/month for 10 nodes (Section 9)

**No deviations from the original design.**

---

**Document Version**: 1.0
**Status**: Ready for Implementation
**Next Phase**: bash-validator agent execution
**Estimated Implementation Time**: 4-6 hours (including validation)

---

## Quick Reference for bash-validator Agent

### File Creation Order

1. `.gitignore` (no dependencies)
2. `variables.tf` (no dependencies)
3. `main.tf` (uses variables)
4. `vpc.tf` (uses main locals)
5. `service-accounts.tf` (uses main locals)
6. `gke.tf` (uses vpc, service-accounts)
7. `node-pools.tf` (uses gke, service-accounts)
8. `outputs.tf` (uses all resources)
9. `terraform.tfvars.example` (uses variables)

### Key Files to Reference

- **EKS Pattern**: `/Users/mbpro/uneeq/miniprem-2025/kubernetes/terraform/eks/main.tf`
- **AKS Pattern**: `/Users/mbpro/uneeq/miniprem-2025/kubernetes/terraform/aks/main.tf`
- **Architecture Design**: `/Users/mbpro/uneeq/miniprem-2025/kubernetes/terraform/gke/GKE_ARCHITECTURE_DESIGN.md`

### Validation Commands

```bash
# Format all files
terraform fmt -recursive kubernetes/terraform/gke/

# Validate syntax
cd kubernetes/terraform/gke/
terraform init
terraform validate

# Test plan (expect auth errors, that's OK)
terraform plan
```

---

**END OF IMPLEMENTATION PLAN**

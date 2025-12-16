# GCP Project Configuration
variable "gcp_project_id" {
  description = "GCP project ID where resources will be created"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.gcp_project_id))
    error_message = "GCP project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "gcp_region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

# Network Configuration
variable "subnet_cidr" {
  description = "CIDR block for the GKE subnet"
  type        = string
  default     = "10.17.0.0/22"
}

variable "pods_cidr" {
  description = "CIDR block for Kubernetes pods (secondary range)"
  type        = string
  default     = "10.18.0.0/16"
}

variable "services_cidr" {
  description = "CIDR block for Kubernetes services (secondary range)"
  type        = string
  default     = "10.117.0.0/16"
}

# Kubernetes Configuration
variable "kubernetes_version" {
  description = "GKE cluster version"
  type        = string
  default     = "1.31"
}

# Project Identification
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "miniprem"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "deployment_id" {
  description = "Unique deployment identifier"
  type        = string
  default     = ""
}

# Renny Node Pool Configuration
variable "renny_instance_type" {
  description = "GCP machine type for Renny nodes"
  type        = string
  default     = "n1-standard-16"
}

variable "renny_min_size" {
  description = "Minimum number of Renny nodes"
  type        = number
  default     = 10
}

variable "renny_max_size" {
  description = "Maximum number of Renny nodes"
  type        = number
  default     = 20
}

variable "renny_desired_size" {
  description = "Desired number of Renny nodes"
  type        = number
  default     = 10
}

# GPU Time-Slicing Configuration
variable "gpu_time_slicing_replicas" {
  description = "Number of pods per GPU"
  type        = number
  default     = 2

  validation {
    condition     = var.gpu_time_slicing_replicas >= 1 && var.gpu_time_slicing_replicas <= 8
    error_message = "GPU time-slicing replicas must be between 1 and 8."
  }
}

# UneeQ Configuration
variable "dhop_url" {
  description = "UneeQ DHOP URL"
  type        = string
  default     = "wss://api.enterprise.uneeq.io:443/signalling-service"
}

variable "dhop_tenant_id" {
  description = "UneeQ DHOP tenant ID"
  type        = string
  sensitive   = true
}

variable "dhop_api_key" {
  description = "UneeQ DHOP API key"
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

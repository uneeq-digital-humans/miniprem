variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Network Configuration
variable "vpc_cidr" {
  description = "VPC CIDR block - PERMANENT DECISION (cannot be changed without cluster rebuild)"
  type        = string
  default     = "10.17.0.0/16"
}

variable "service_cidr" {
  description = "EKS service CIDR block - PERMANENT DECISION (cannot be changed without cluster rebuild)"
  type        = string
  default     = "10.117.0.0/16"
}

variable "enable_nat_ha" {
  description = "Enable high availability NAT gateways (3 vs 1) - Can be changed later"
  type        = bool
  default     = true
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "renny"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "deployment_id" {
  description = "Unique deployment identifier (git hash or timestamp)"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.deployment_id)) || var.deployment_id == ""
    error_message = "Deployment ID must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

# Node group configurations
variable "renny_instance_type" {
  description = "Instance type for Renny GPU nodes"
  type        = string
  default     = "g5.4xlarge"
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


# DHOP Configuration
variable "dhop_url" {
  description = "DHOP URL"
  type        = string
  default     = "wss://api.enterprise.uneeq.io:443/signalling-service"
}

variable "dhop_tenant_id" {
  description = "DHOP Tenant ID"
  type        = string
  sensitive   = true
}

variable "dhop_api_key" {
  description = "DHOP API Key (base64 encoded)"
  type        = string
  sensitive   = true
}

# Harbor registry credentials (contact help@uneeq.com for robot account)
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
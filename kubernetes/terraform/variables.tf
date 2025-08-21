variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
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

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

# Node group configurations
variable "renny_instance_type" {
  description = "Instance type for Renny GPU nodes"
  type        = string
  default     = "g5.2xlarge"
}

variable "a2f_instance_type" {
  description = "Instance type for Audio2Face GPU nodes"
  type        = string
  default     = "g5.2xlarge"
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

variable "a2f_min_size" {
  description = "Minimum number of A2F nodes"
  type        = number
  default     = 2
}

variable "a2f_max_size" {
  description = "Maximum number of A2F nodes"
  type        = number
  default     = 5
}

variable "a2f_desired_size" {
  description = "Desired number of A2F nodes"
  type        = number
  default     = 2
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

# Docker Hub credentials
variable "docker_username" {
  description = "Docker Hub username"
  type        = string
  sensitive   = true
}

variable "docker_password" {
  description = "Docker Hub password"
  type        = string
  sensitive   = true
}
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

  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "terraform/state"
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
  deployment_id = var.deployment_id != "" ? var.deployment_id : substr(md5(timestamp()), 0, 8)
  cluster_name  = "${var.project_name}-${var.environment}-${local.deployment_id}"

  zones = [
    "${var.gcp_region}-a",
    "${var.gcp_region}-b",
    "${var.gcp_region}-c"
  ]

  common_labels = {
    project     = var.project_name
    environment = var.environment
    deployment  = local.deployment_id
    managed_by  = "terraform"
  }
}

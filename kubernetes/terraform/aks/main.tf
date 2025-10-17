terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
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

  # Optional: Azure Storage backend for state
  # Uncomment and configure after creating storage account:
  #   az group create --name terraform-state-rg --location eastus
  #   az storage account create --name rennytfstate --resource-group terraform-state-rg --location eastus --sku Standard_LRS
  #   az storage container create --name tfstate --account-name rennytfstate
  #
  # backend "azurerm" {
  #   resource_group_name  = "terraform-state-rg"
  #   storage_account_name = "rennytfstate"
  #   container_name       = "tfstate"
  #   key                  = "aks/terraform.tfstate"
  # }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.azure_subscription_id
  tenant_id       = var.azure_tenant_id
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
}

# Kubernetes provider using AKS cluster credentials
# Note: This provider is configured after the cluster is created
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.main.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.main.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
  }
}

locals {
  # Generate cluster name with deployment ID for resource isolation
  # deployment_id allows multiple independent deployments in same subscription
  cluster_name = var.deployment_id != "" ? "${var.project_name}-${var.environment}-${var.deployment_id}" : "${var.project_name}-${var.environment}"

  # Common tags applied to all resources for cost tracking and organization
  common_tags = {
    Project       = var.project_name
    Environment   = var.environment
    DeploymentId  = var.deployment_id
    ManagedBy     = "Terraform"
    CloudProvider = "Azure"
    Workload      = "DigitalHuman"
  }
}

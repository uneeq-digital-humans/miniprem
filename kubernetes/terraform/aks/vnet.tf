# Azure Virtual Network Configuration
# Creates isolated network infrastructure for the AKS cluster

# Resource Group
# All Azure resources are organized within a resource group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.azure_region
  tags     = local.common_tags
}

# Virtual Network (VNet)
# Provides network isolation and address space for all cluster resources
resource "azurerm_virtual_network" "main" {
  name                = "${local.cluster_name}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.vnet_cidr]

  tags = local.common_tags
}

# Subnet for AKS Nodes
# All cluster nodes (system and GPU) are deployed in this subnet
# Must be large enough to accommodate all pods when using Azure CNI
# With Azure CNI, each pod gets an IP from this subnet
# Note: AKS handles subnet delegation automatically - do not pre-delegate
resource "azurerm_subnet" "nodes" {
  name                 = "${local.cluster_name}-nodes-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_cidr]
}

# Public IP for NAT Gateway
# Required for outbound internet connectivity from private nodes
resource "azurerm_public_ip" "nat" {
  name                = "${local.cluster_name}-nat-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.common_tags
}

# NAT Gateway
# Provides secure outbound internet access for nodes
# Required for:
#   - Pulling container images from Harbor/ACR
#   - Kubernetes API calls
#   - External service communication (UneeQ DHOP, etc.)
resource "azurerm_nat_gateway" "main" {
  name                = "${local.cluster_name}-nat-gateway"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard"

  tags = local.common_tags
}

# Associate NAT Gateway with Public IP
resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# Associate NAT Gateway with Nodes Subnet
# All egress traffic from nodes will route through NAT gateway
resource "azurerm_subnet_nat_gateway_association" "nodes" {
  subnet_id      = azurerm_subnet.nodes.id
  nat_gateway_id = azurerm_nat_gateway.main.id

  depends_on = [azurerm_nat_gateway_public_ip_association.main]
}

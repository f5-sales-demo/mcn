resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "hub" {
  name                = "hub-vnet"
  address_space       = [var.hub_cidr]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_subnet" "management" {
  name                 = "snet-hub-management"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.mgmt_subnet_prefix]
}

resource "azurerm_subnet" "external" {
  name                 = "snet-hub-external"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.external_subnet_prefix]
}

resource "azurerm_subnet" "internal" {
  name                 = "snet-hub-internal"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.internal_subnet_prefix]
}

# RouteServerSubnet: name is literal, /27, and has NO NSG and NO route table
# association (both are unsupported on the Route Server subnet).
resource "azurerm_subnet" "route_server" {
  name                 = "RouteServerSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.route_server_subnet_prefix]
}

resource "azurerm_public_ip" "route_server" {
  name                = "${var.route_server_name}-pip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Azure Route Server. ASN is fixed by Azure at 65515; virtual_router_ips are the
# two BGP peer addresses (10.0.4.4 / 10.0.4.5) the CEs peer to.
resource "azurerm_route_server" "this" {
  name                 = var.route_server_name
  location             = azurerm_resource_group.this.location
  resource_group_name  = azurerm_resource_group.this.name
  sku                  = "Standard"
  public_ip_address_id = azurerm_public_ip.route_server.id
  subnet_id            = azurerm_subnet.route_server.id
  tags                 = var.tags
}

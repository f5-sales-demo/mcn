# Plan-level test for the azure-hub module. Mocks azurerm so no Azure credentials
# are contacted. Asserts on the statically-known names (subnet/VNet/RS names are
# literal; resource IDs are known-after-apply and are not asserted).

mock_provider "azurerm" {}

run "hub_names_and_subnets" {
  command = plan

  module {
    source = "./modules/azure-hub"
  }

  variables {
    resource_group_name        = "rmordasiewicz-f5-xc-ce-infra"
    location                   = "eastus"
    hub_cidr                   = "10.0.0.0/16"
    mgmt_subnet_prefix         = "10.0.1.0/26"
    external_subnet_prefix     = "10.0.2.0/26"
    internal_subnet_prefix     = "10.0.3.0/26"
    route_server_subnet_prefix = "10.0.4.0/27"
    route_server_name          = "ce-ha-lab-rrs"
    tags                       = {}
  }

  assert {
    condition     = output.vnet_name == "hub-vnet"
    error_message = "Hub VNet must be named hub-vnet."
  }

  assert {
    condition     = azurerm_subnet.route_server.name == "RouteServerSubnet"
    error_message = "Route Server subnet must be named literally RouteServerSubnet."
  }

  assert {
    condition     = azurerm_subnet.route_server.address_prefixes[0] == "10.0.4.0/27"
    error_message = "RouteServerSubnet must be a /27."
  }

  assert {
    condition     = azurerm_route_server.this.sku == "Standard"
    error_message = "Route Server must use the Standard SKU."
  }
}

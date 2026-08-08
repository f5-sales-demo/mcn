# ---------------------------------------------------------
# Canadian Regional Extension: Azure Internal Load Balancer (ILB)
# ---------------------------------------------------------

resource "azurerm_lb" "ca_ilb" {
  #checkov:skip=CKV_AZURE_27:Lab environment ILB - diagnostic logging not required
  count               = var.enable_canada && var.enable_canada_ilb ? 1 : 0
  name                = "${var.component}-ca-ilb"
  location            = var.ca_location
  resource_group_name = module.azure_hub_ca[0].resource_group_name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "ca-ilb-frontend"
    subnet_id                     = module.azure_hub_ca[0].management_subnet_id
    private_ip_address            = var.ca_vip
    private_ip_address_allocation = "Static"
  }

  tags = local.tags
}

resource "azurerm_lb_backend_address_pool" "ca_ce_backend" {
  count           = var.enable_canada && var.enable_canada_ilb ? 1 : 0
  name            = "ca-ce-backend-pool"
  loadbalancer_id = azurerm_lb.ca_ilb[0].id
}

resource "azurerm_network_interface_backend_address_pool_association" "ca_ce" {
  for_each = var.enable_canada && var.enable_canada_ilb ? module.ce_topology_ca[0].ce_nodes : {}

  network_interface_id    = module.ce_node_ca[each.key].mgmt_nic_id
  ip_configuration_name   = "management"
  backend_address_pool_id = azurerm_lb_backend_address_pool.ca_ce_backend[0].id
}

resource "azurerm_lb_probe" "ca_site_console" {
  count               = var.enable_canada && var.enable_canada_ilb ? 1 : 0
  name                = "site-console-probe"
  loadbalancer_id     = azurerm_lb.ca_ilb[0].id
  protocol            = "Tcp"
  port                = 65500
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "ca_ha_ports" {
  count                          = var.enable_canada && var.enable_canada_ilb ? 1 : 0
  name                           = "ha-ports-rule"
  loadbalancer_id                = azurerm_lb.ca_ilb[0].id
  frontend_ip_configuration_name = "ca-ilb-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.ca_ce_backend[0].id]
  probe_id                       = azurerm_lb_probe.ca_site_console[0].id
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  floating_ip_enabled            = true
  idle_timeout_in_minutes        = 4
}

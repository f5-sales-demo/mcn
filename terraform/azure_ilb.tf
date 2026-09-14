# Azure US Internal Load Balancer is the supported replacement for the deferred
# Route Server path. It probes and distributes TCP/65500 Site Console traffic to
# the CE management NICs; it does not claim BGP, ECMP, or VIP-route convergence.
resource "azurerm_lb" "azure_ilb" {
  count               = var.enable_azure && var.enable_azure_ilb ? 1 : 0
  name                = "${var.component}-ilb"
  location            = module.azure_hub[0].location
  resource_group_name = module.azure_hub[0].resource_group_name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "ilb-frontend"
    subnet_id                     = module.azure_hub[0].management_subnet_id
    private_ip_address            = cidrhost(var.mgmt_subnet_prefix, 10)
    private_ip_address_allocation = "Static"
  }

  tags = local.tags
}

resource "azurerm_lb_backend_address_pool" "azure_ce_backend" {
  count           = var.enable_azure && var.enable_azure_ilb ? 1 : 0
  name            = "ce-backend-pool"
  loadbalancer_id = azurerm_lb.azure_ilb[0].id
}

resource "azurerm_network_interface_backend_address_pool_association" "azure_ce" {
  for_each = var.enable_azure && var.enable_azure_ilb ? module.ce_topology.ce_nodes : {}

  network_interface_id    = module.ce_node[each.key].mgmt_nic_id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.azure_ce_backend[0].id
}

resource "azurerm_lb_probe" "azure_site_console" {
  count               = var.enable_azure && var.enable_azure_ilb ? 1 : 0
  name                = "site-console-probe"
  loadbalancer_id     = azurerm_lb.azure_ilb[0].id
  protocol            = "Tcp"
  port                = 65500
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "azure_ha_ports" {
  count                          = var.enable_azure && var.enable_azure_ilb ? 1 : 0
  name                           = "ha-ports-rule"
  loadbalancer_id                = azurerm_lb.azure_ilb[0].id
  frontend_ip_configuration_name = "ilb-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.azure_ce_backend[0].id]
  probe_id                       = azurerm_lb_probe.azure_site_console[0].id
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  floating_ip_enabled            = true
  idle_timeout_in_minutes        = 4
}

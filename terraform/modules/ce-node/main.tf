# Per-CE Azure resources: managed identity, three NICs (mgmt/external/internal,
# all with IP forwarding on and accelerated networking OFF), and the volterra-node
# VM. The mgmt NIC is the VM's FIRST NIC = eth0 = the SLO/BGP local address.

resource "azurerm_user_assigned_identity" "this" {
  name                = "${var.hostname}-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_public_ip" "mgmt" {
  name                = "${var.hostname}-mgmt-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# eth0 / SLO — mgmt subnet, static private IP (the BGP local address), public IP.
resource "azurerm_network_interface" "mgmt" {
  name                           = "${var.hostname}-mgmt-nic"
  resource_group_name            = var.resource_group_name
  location                       = var.location
  ip_forwarding_enabled          = true
  accelerated_networking_enabled = false

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.mgmt_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.mgmt_private_ip
    public_ip_address_id          = azurerm_public_ip.mgmt.id
  }

  tags = var.tags
}

resource "azurerm_network_interface" "external" {
  name                           = "${var.hostname}-external-nic"
  resource_group_name            = var.resource_group_name
  location                       = var.location
  ip_forwarding_enabled          = true
  accelerated_networking_enabled = false

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.external_subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

resource "azurerm_network_interface" "internal" {
  name                           = "${var.hostname}-internal-nic"
  resource_group_name            = var.resource_group_name
  location                       = var.location
  ip_forwarding_enabled          = true
  accelerated_networking_enabled = false

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.internal_subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "this" {
  name                = var.hostname
  computer_name       = var.hostname
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  zone                = var.zone

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  # eth0 first = mgmt/SLO NIC (BGP local + MAC-bound to the XC site interface).
  network_interface_ids = [
    azurerm_network_interface.mgmt.id,
    azurerm_network_interface.external.id,
    azurerm_network_interface.internal.id,
  ]

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  os_disk {
    name                 = "${var.hostname}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "volterraedgeservices"
    offer     = "volterra-node"
    sku       = "volterra-node"
    version   = "latest"
  }

  # Marketplace plan is REQUIRED for the volterra-node image or VM create fails.
  plan {
    name      = "volterra-node"
    product   = "volterra-node"
    publisher = "volterraedgeservices"
  }

  custom_data = var.custom_data

  tags = var.tags
}

# Private Ubuntu test client in snet-hub-internal. Azure Run Command generates
# traffic without a public address, inbound management rule, or private key.

resource "azurerm_network_interface" "this" {
  name                = "${var.name}VMNic"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "this" {
  #checkov:skip=CKV_AZURE_50:Lab VM - no extensions required
  #checkov:skip=CKV_AZURE_93:Lab VM - platform-managed encryption sufficient
  name                = var.name
  computer_name       = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  network_interface_ids = [azurerm_network_interface.this.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = var.custom_data != "" ? var.custom_data : null

  tags = var.tags
}

output "private_ip" {
  description = "Private IP of the test client."
  value       = azurerm_network_interface.this.private_ip_address
}

output "vm_name" {
  description = "Test client VM name."
  value       = azurerm_linux_virtual_machine.this.name
}

output "nic_name" {
  description = "Test client NIC name (read effective routes from this NIC)."
  value       = azurerm_network_interface.this.name
}

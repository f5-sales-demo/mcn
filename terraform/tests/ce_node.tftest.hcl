# Plan-level test for the ce-node module. Mocks azurerm so no Azure credentials
# are contacted. Asserts CE NIC hardening invariants (IP forwarding on,
# accelerated networking off) and the required marketplace plan block.

mock_provider "azurerm" {}

run "ce_vm_and_nics" {
  command = plan

  module {
    source = "./modules/ce-node"
  }

  variables {
    hostname            = "f5-xc-ce-vm-01"
    resource_group_name = "rmordasiewicz-f5-xc-ce-infra"
    location            = "eastus"
    zone                = "1"
    vm_size             = "Standard_D8_v4"
    mgmt_subnet_id      = "/subscriptions/x/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/hub-vnet/subnets/snet-hub-management"
    external_subnet_id  = "/subscriptions/x/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/hub-vnet/subnets/snet-hub-external"
    internal_subnet_id  = "/subscriptions/x/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/hub-vnet/subnets/snet-hub-internal"
    mgmt_private_ip     = "10.0.1.4"
    admin_username      = "azureuser"
    ssh_public_key      = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
    custom_data         = "IyNjbG91ZC1jb25maWcK"
    tags                = {}
  }

  assert {
    condition     = output.vm_name == "f5-xc-ce-vm-01"
    error_message = "CE VM name must equal the hostname."
  }

  assert {
    condition     = azurerm_network_interface.mgmt.ip_forwarding_enabled == true
    error_message = "The mgmt NIC must have IP forwarding enabled."
  }

  assert {
    condition     = azurerm_network_interface.mgmt.accelerated_networking_enabled == false
    error_message = "The mgmt NIC must have accelerated networking DISABLED (so eth0 comes up raw at the mgmt IP)."
  }

  assert {
    condition     = azurerm_network_interface.external.ip_forwarding_enabled == true && azurerm_network_interface.internal.ip_forwarding_enabled == true
    error_message = "All CE NICs must have IP forwarding enabled."
  }

  assert {
    condition     = azurerm_network_interface.mgmt.ip_configuration[0].private_ip_address == "10.0.1.4"
    error_message = "The mgmt NIC must use the static SLO/BGP local IP."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this.plan[0].name == "volterra-node"
    error_message = "The volterra-node marketplace plan block is required."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this.os_disk[0].storage_account_type == "StandardSSD_LRS"
    error_message = "CE OS disk must be StandardSSD_LRS."
  }
}

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

  # Azure Serial Console requires boot diagnostics. It is the only way into a CE that
  # has not finished its first boot: the vpm/debug API used for every other diagnostic
  # is reached through the XC control plane, so it answers only once the node is
  # ONLINE, and operator SSH only exists after cloud-init has written admin's
  # authorized_keys. Losing this block would silently remove the break-glass path for
  # the exact failure it exists to debug.
  assert {
    condition     = length(azurerm_linux_virtual_machine.this.boot_diagnostics) == 1
    error_message = "CE VM must enable boot diagnostics, or Azure Serial Console cannot attach."
  }

  # An empty block means Azure-managed storage, so there is no diagnostics storage
  # account, lifecycle policy or access key for us to own.
  assert {
    condition     = azurerm_linux_virtual_machine.this.boot_diagnostics[0].storage_account_uri == null
    error_message = "CE boot diagnostics must use Azure-managed storage (no storage_account_uri)."
  }

}

# modules/xc-site couples the XC site object's lifecycle to vm_instance_id, so it
# has to identify the VM INSTANCE. The ARM resource id looks like a perfectly
# good identifier and is the obvious thing to reach for, but it is
# ".../virtualMachines/<hostname>" — byte-identical before and after a
# replacement — so wiring it would leave the coupling permanently inert and bring
# back #674 with no visible symptom.
#
# This run applies (against the mocked provider — still no Azure credentials)
# because both candidate attributes are computed, and a plan leaves them
# known-after-apply and therefore unassertable. Only virtual_machine_id is
# overridden; every other computed attribute keeps the value the mock invents, so
# reading the wrong one fails the comparison instead of quietly passing.
run "vm_instance_id_is_the_instance_id_not_the_arm_resource_id" {
  command = apply

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

  # The mocked provider invents ids like "7251r305", and azurerm parses resource
  # ids client-side, so every id this module feeds into another resource needs a
  # well-formed one or the apply fails before any assertion runs.
  override_resource {
    target = azurerm_public_ip.mgmt
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/f5-xc-ce-vm-01-mgmt-pip"
    }
  }

  override_resource {
    target = azurerm_network_interface.mgmt
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/networkInterfaces/f5-xc-ce-vm-01-mgmt-nic"
    }
  }

  override_resource {
    target = azurerm_network_interface.external
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/networkInterfaces/f5-xc-ce-vm-01-external-nic"
    }
  }

  override_resource {
    target = azurerm_network_interface.internal
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/networkInterfaces/f5-xc-ce-vm-01-internal-nic"
    }
  }

  override_resource {
    target = azurerm_user_assigned_identity.this
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/f5-xc-ce-vm-01-identity"
    }
  }

  override_resource {
    target = azurerm_linux_virtual_machine.this
    values = {
      virtual_machine_id = "5efa1cf7-73ec-4bd2-b8d1-1e0d0a41bd12"
    }
  }

  assert {
    condition     = output.vm_instance_id == "5efa1cf7-73ec-4bd2-b8d1-1e0d0a41bd12"
    error_message = "vm_instance_id must expose virtual_machine_id (regenerated per instance), not the name-derived ARM resource id."
  }
}

output "mgmt_nic_mac" {
  description = "MAC address of the eth0/SLO (mgmt) NIC. Wired into the XC site interface binding so a NIC recreate updates the site."
  value       = azurerm_network_interface.mgmt.mac_address
}

output "mgmt_private_ip" {
  description = "Private IP of the eth0/SLO (mgmt) NIC — the BGP local address and the Route Server BGP connection peer_ip."
  value       = azurerm_network_interface.mgmt.private_ip_address
}

output "vm_name" {
  description = "CE VM name."
  value       = azurerm_linux_virtual_machine.this.name
}

output "vm_id" {
  description = "CE VM resource ID."
  value       = azurerm_linux_virtual_machine.this.id
}

output "identity_id" {
  description = "User-assigned managed identity resource ID."
  value       = azurerm_user_assigned_identity.this.id
}

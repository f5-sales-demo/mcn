output "mgmt_nic_id" {
  description = "Resource ID of the eth0/SLO (mgmt) NIC."
  value       = azurerm_network_interface.mgmt.id
}

output "mgmt_private_ip" {
  description = "Private IP of the eth0/SLO (mgmt) NIC — the BGP local address and the Route Server BGP connection peer_ip."
  value       = azurerm_network_interface.mgmt.private_ip_address
}

output "sli_private_ip" {
  description = "Private IP of the internal/SLI NIC — the only one of the CE's three private addresses that answers, and where the Site Console web UI (TCP 65500) is served. Reach it from a workstation with `az network bastion tunnel --target-resource-id <this CE's vm_id> --resource-port 65500`; the mgmt/SLO and external addresses serve nothing."
  value       = azurerm_network_interface.internal.private_ip_address
}

output "vm_name" {
  description = "CE VM name."
  value       = azurerm_linux_virtual_machine.this.name
}

output "vm_id" {
  description = "CE VM ARM resource ID. Addresses the VM (this is what `az network bastion tunnel --target-resource-id` wants) — it is NOT a per-instance identity: see vm_instance_id."
  value       = azurerm_linux_virtual_machine.this.id
}

output "vm_instance_id" {
  description = "Azure VM instance identifier, regenerated when the VM is replaced."
  value       = azurerm_linux_virtual_machine.this.virtual_machine_id
}

output "identity_id" {
  description = "User-assigned managed identity resource ID."
  value       = azurerm_user_assigned_identity.this.id
}

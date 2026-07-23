output "resource_group_name" {
  description = "Name of the hub resource group."
  value       = azurerm_resource_group.this.name
}

output "location" {
  description = "Azure region."
  value       = azurerm_resource_group.this.location
}

output "vnet_name" {
  description = "Hub VNet name."
  value       = azurerm_virtual_network.hub.name
}

output "vnet_id" {
  description = "Hub VNet resource ID."
  value       = azurerm_virtual_network.hub.id
}

output "management_subnet_id" {
  description = "snet-hub-management subnet ID."
  value       = azurerm_subnet.management.id
}

output "external_subnet_id" {
  description = "snet-hub-external subnet ID."
  value       = azurerm_subnet.external.id
}

output "internal_subnet_id" {
  description = "snet-hub-internal subnet ID."
  value       = azurerm_subnet.internal.id
}

output "route_server_subnet_id" {
  description = "RouteServerSubnet subnet ID."
  value       = azurerm_subnet.route_server.id
}

output "route_server_id" {
  description = "Azure Route Server resource ID."
  value       = azurerm_route_server.this.id
}

output "rs_peer_ips" {
  description = "The two Route Server BGP peer IPs (virtual_router_ips) the CEs peer to."
  value       = azurerm_route_server.this.virtual_router_ips
}

output "rs_asn" {
  description = "Route Server ASN (fixed by Azure at 65515)."
  value       = azurerm_route_server.this.virtual_router_asn
}

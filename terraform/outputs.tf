# ---------------------------------------------------------
# Topology
# ---------------------------------------------------------

output "ce_nodes" {
  description = "Expanded per-CE node map (hostname, site_name, slo_ip, az, interface_name)."
  value       = module.ce_topology.ce_nodes
}

output "ce_count" {
  description = "Number of CE nodes deployed."
  value       = module.ce_topology.ce_count
}

# ---------------------------------------------------------
# Azure hub / Route Server
# ---------------------------------------------------------

output "resource_group_name" {
  description = "Hub resource group name."
  value       = module.azure_hub.resource_group_name
}

output "route_server_id" {
  description = "Azure Route Server resource ID."
  value       = module.azure_hub.route_server_id
}

output "route_server_peer_ips" {
  description = "Route Server BGP peer IPs (the CE external BGP peer addresses)."
  value       = module.azure_hub.rs_peer_ips
}

output "ce_mgmt_private_ips" {
  description = "Per-CE eth0/SLO private IPs (BGP local addresses / RS bgpConnection peer IPs)."
  value       = { for k, m in module.ce_node : k => m.mgmt_private_ip }
}

output "ce_vm_names" {
  description = "Per-CE VM names."
  value       = { for k, m in module.ce_node : k => m.vm_name }
}

output "client_public_ip" {
  description = "Public IP of the test client."
  value       = module.client_vm.public_ip
}

output "client_nic_name" {
  description = "Test client NIC name (read effective routes here to prove ECMP)."
  value       = module.client_vm.nic_name
}

# ---------------------------------------------------------
# XC data-plane
# ---------------------------------------------------------

output "xc_site_names" {
  description = "Per-CE XC site names."
  value       = { for k, m in module.xc_site : k => m.site_name }
}

output "xc_interface_names" {
  description = "Per-CE auto-derived network_interface object names (BGP peer bind target)."
  value       = { for k, m in module.xc_site : k => m.interface_name }
}

output "loadbalancer_name" {
  description = "HTTP load balancer name."
  value       = xcsh_http_loadbalancer.this.name
}

output "origin_pool_name" {
  description = "Origin pool name."
  value       = xcsh_origin_pool.this.name
}

output "vip" {
  description = "HA VIP advertised via eBGP/ECMP."
  value       = var.vip
}

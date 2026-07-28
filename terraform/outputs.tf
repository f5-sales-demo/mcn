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

output "ce_sli_private_ips" {
  description = "Per-CE internal/SLI private IPs — where each CE serves its Site Console web UI (TCP 65500). Informational: the Bastion tunnel is targeted by VM resource id (ce_vm_ids), because Azure does not allow a custom resource port over an IP-targeted tunnel."
  value       = { for k, m in module.ce_node : k => m.sli_private_ip }
}

output "ce_vm_ids" {
  description = "Per-CE VM resource IDs — the --target-resource-id of `az network bastion tunnel` when opening the Site Console web UI on 65500."
  value       = { for k, m in module.ce_node : k => m.vm_id }
}

output "bastion_name" {
  description = "Azure Bastion host name, or null when enable_bastion is false. Feed it to `az network bastion tunnel --name`."
  value       = module.azure_hub.bastion_name
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

# Makes the site-to-node binding that closes #674 observable from the CLI. Each
# value is the CE VM instance id its XC site object is coupled to; the matching
# registration reports the same value as infra.instance_id. When the two disagree
# the site is bound to a node that no longer exists — the state in which a
# rebuilt CE can never register. (The registration side is not on the
# xcsh_site_registration data source yet: provider issue #1376.)
output "ce_bound_instance_ids" {
  description = "Per-CE VM instance id each XC site object is bound to. Compare with the registration's infra.instance_id to spot a site still bound to a destroyed node."
  value       = { for k, m in module.xc_site : k => m.bound_vm_instance_id }
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

# ---------------------------------------------------------
# CE registration token
# ---------------------------------------------------------

output "registration_token_name" {
  description = "Name (metadata id) of the generated xcsh_token used for CE registration."
  value       = xcsh_token.ce.name
}

output "registration_token_is_generated" {
  description = "True when the CE cloud-init token feed uses the generated xcsh_token.ce.uid (no override supplied)."
  # Whether an override was supplied is not itself secret (the token value is).
  value = nonsensitive(var.registration_token == "")
}

output "ce_registration_token" {
  description = "Resolved CE registration token fed to cloud-init: the generated xcsh_token.ce.uid, or var.registration_token when overridden."
  value       = local.ce_registration_token
  sensitive   = true
}

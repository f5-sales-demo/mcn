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

# The four outputs below exist so the documentation can name nothing. Every
# operational value a reader needs has to be readable from the deployment rather
# than copied out of prose, because prose goes stale silently and a reader cannot
# tell. Anything documented as a command therefore needs an output behind it.
output "route_server_name" {
  description = "Azure Route Server name — the --routeserver argument of `az network routeserver peering list-learned-routes`."
  value       = local.route_server_name
}

output "client_vm_name" {
  description = "Test client VM name — the -n argument of `az vm run-command invoke` when driving traffic at the VIP from inside the VNet."
  value       = local.client_vm_name
}

output "lb_domain" {
  description = "Domain the HTTP load balancer matches on. Requests to the VIP MUST send it as the Host header; without it the load balancer has no matching domain and answers 404."
  value       = var.lb_domain
}

output "origin_ip" {
  description = "Origin the pool targets. Useful as a control: a batch straight to the origin, bypassing the VIP, separates an origin fault from a VIP/ECMP/CE fault."
  value       = var.origin_ip
}

output "route_server_peer_ips" {
  description = "Route Server BGP peer IPs (the CE external BGP peer addresses)."
  value       = module.azure_hub.rs_peer_ips
}

output "route_server_bgp_connection_names" {
  description = "Azure Route Server BGP connection names used to inspect learned routes."
  value       = { for key, connection in module.azure_route_server_bgp : key => connection.connection_name }
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

output "site_console_admin_passwords" {
  description = "Generated per-site passwords for the F5XC-managed node-local admin user. Retrieve only for an active access session and keep them out of logs and published documentation."
  value = merge(
    { for key, password in random_password.site_console_admin : module.xc_site[key].site_name => password.result },
    { for key, password in random_password.site_console_admin_ca : module.xc_site_ca[key].site_name => password.result },
    { for key, password in random_password.site_console_admin_aws : local.aws_sites[key].site_name => password.result },
    var.enable_kvm ? { (xcsh_securemesh_site_v2.kvm[0].name) = random_password.site_console_admin_kvm[0].result } : {}
  )
  sensitive = true
}

output "bastion_name" {
  description = "Azure Bastion host name, or null when enable_bastion is false. Feed it to `az network bastion tunnel --name`."
  value       = module.azure_hub.bastion_name
}

output "client_nic_name" {
  description = "Test client NIC name (read effective routes here to prove ECMP)."
  value       = module.client_vm.nic_name
}

# ---------------------------------------------------------
# XC tenant
# ---------------------------------------------------------

output "xc_tenant" {
  description = "F5 XC tenant this deployment writes to. Config-controlled (var.expected_xc_tenant), not taken from XCSH_API_URL."
  value       = var.expected_xc_tenant
}

output "xc_api_url" {
  description = "F5 XC API endpoint the xcsh provider is pinned to, derived from var.expected_xc_tenant."
  value       = local.xc_api_url
}

# The other half of the tenant guard's comparison, published so an operator can
# see what their shell is claiming without having to trip the guard to find out —
# `terraform output xc_env_tenant` answers "which tenant am I sourced for?".
# Empty means XCSH_API_URL is unset, which is the CI case and which the guard
# treats as no opinion rather than as a mismatch.
output "xc_env_tenant" {
  description = "F5 XC tenant named by XCSH_API_URL in the environment this ran in, or empty when unset. Diagnostic only: xc_tenant is what the deployment actually targets."
  value       = data.external.xc_env_tenant.result.tenant
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

# ---------------------------------------------------------
# Canada Regional outputs
# ---------------------------------------------------------

output "ca_lb_domain" {
  description = "Domain served by the Canada HTTP load balancer."
  value       = var.ca_lb_domain
}

output "ca_resource_group_name" {
  description = "Canadian Azure resource group name."
  value       = try(module.azure_hub_ca[0].resource_group_name, null)
}

output "ca_route_server_name" {
  description = "Canadian Azure Route Server name."
  value       = var.enable_canada ? local.ca_route_server_name : null
}

output "ca_route_server_bgp_connection_names" {
  description = "Canadian Azure Route Server BGP connection names used to inspect learned routes."
  value       = { for key, connection in module.azure_route_server_bgp_ca : key => connection.connection_name }
}

output "ca_client_vm_name" {
  description = "Canadian Azure test-client VM name."
  value       = try(module.client_vm_ca[0].vm_name, null)
}

output "ca_client_nic_name" {
  description = "Canadian Azure test-client NIC name used to inspect effective routes."
  value       = try(module.client_vm_ca[0].nic_name, null)
}

output "ca_ce_vm_names" {
  description = "Canadian Customer Edge VM names."
  value       = { for key, node in module.ce_node_ca : key => node.vm_name }
}

output "ca_ce_mgmt_private_ips" {
  description = "Canadian Customer Edge SLO addresses used as Azure Route Server BGP next hops."
  value       = { for key, node in module.ce_node_ca : key => node.mgmt_private_ip }
}

output "ca_site_names" {
  description = "Canadian Secure Mesh site names."
  value       = { for key, site in module.xc_site_ca : key => site.site_name }
}

output "ca_re_virtual_site_name" {
  description = "Name of the Canadian Regional Edge virtual site."
  value       = try(xcsh_virtual_site.canada_re[0].name, null)
}

output "ca_ce_virtual_site_name" {
  description = "Name of the Canadian Customer Edge virtual site."
  value       = try(xcsh_virtual_site.canada_ce[0].name, null)
}

output "ca_loadbalancer_name" {
  description = "Name of the Canadian HTTP load balancer."
  value       = try(xcsh_http_loadbalancer.canada[0].name, null)
}

output "ca_origin_pool_name" {
  description = "Name of the Canadian origin pool."
  value       = try(xcsh_origin_pool.canada[0].name, null)
}

output "ca_vip" {
  description = "HA VIP for Canadian CEs advertised through eBGP/ECMP. This is distinct from ca_ilb_frontend_ip."
  value       = var.enable_canada ? var.ca_vip : null
}

output "ca_ilb_id" {
  description = "Azure Internal Load Balancer ID for Canadian regional path."
  value       = try(azurerm_lb.ca_ilb[0].id, null)
}

output "ca_ilb_rule_name" {
  description = "Azure Internal Load Balancer rule whose backend health is part of showcase evidence."
  value       = try(azurerm_lb_rule.ca_ha_ports[0].name, null)
}

output "ca_ilb_frontend_ip" {
  description = "Azure Internal Load Balancer frontend private IP for Canadian regional path."
  value       = try(azurerm_lb.ca_ilb[0].frontend_ip_configuration[0].private_ip_address, null)
}

# ---------------------------------------------------------
# AWS outputs
# ---------------------------------------------------------

output "aws_vpc_id" {
  description = "AWS VPC ID."
  value       = try(aws_vpc.aws[0].id, null)
}

output "aws_region" {
  description = "AWS Region containing the showcase resources."
  value       = var.enable_aws ? var.aws_location : null
}

output "aws_ce_instance_ids" {
  description = "EC2 instance IDs of the AWS Customer Edge nodes."
  value       = { for key, ce in aws_instance.ce : key => ce.id }
}

output "aws_ce_public_ips" {
  description = "Elastic IPs assigned to the AWS Customer Edge nodes."
  value       = { for key, address in aws_eip.ce : key => address.public_ip }
}

output "aws_lb_domain" {
  description = "Domain served by the AWS HTTP load balancer."
  value       = var.aws_lb_domain
}

output "aws_loadbalancer_name" {
  description = "Name of the AWS HTTP load balancer."
  value       = try(xcsh_http_loadbalancer.aws[0].name, null)
}

output "aws_origin_pool_name" {
  description = "Name of the AWS origin pool."
  value       = try(xcsh_origin_pool.aws[0].name, null)
}

output "aws_vip" {
  description = "HA VIP for AWS CEs advertised via eBGP/ECMP."
  value       = var.enable_aws ? var.aws_vip : null
}

output "aws_route_server_id" {
  description = "AWS VPC Route Server identifier."
  value       = try(aws_vpc_route_server.aws[0].route_server_id, null)
}

output "aws_route_server_endpoint_addresses" {
  description = "AWS Route Server endpoint addresses used by the CE BGP sessions."
  value       = [for endpoint in aws_vpc_route_server_endpoint.aws : endpoint.eni_address]
}

output "aws_route_server_peer_ids" {
  description = "Route Server peer ID for each independent AWS CE site."
  value       = { for key, peer in aws_vpc_route_server_peer.ce : key => peer.route_server_peer_id }
}

output "aws_route_server_propagated_route_tables" {
  description = "Route tables where Route Server learned routes, including the AWS VIP, are propagated."
  value       = { for key, propagation in aws_vpc_route_server_propagation.aws : key => propagation.route_table_id }
}

output "aws_site_names" {
  description = "Three independent AWS Secure Mesh site names."
  value       = { for key, site in xcsh_securemesh_site_v2.aws : key => site.name }
}

output "aws_test_client_instance_id" {
  description = "AWS test-client instance ID for VIP traffic checks."
  value       = try(aws_instance.test_client[0].id, null)
}

output "aws_test_client_public_ip" {
  description = "Public IP of the AWS test client."
  value       = try(aws_instance.test_client[0].public_ip, null)
}

# ---------------------------------------------------------
# KVM outputs
# ---------------------------------------------------------

output "kvm_site_name" {
  description = "KVM Secure Mesh site name."
  value       = try(xcsh_securemesh_site_v2.kvm[0].name, null)
}

output "kvm_domain_name" {
  description = "Libvirt domain that runs the KVM Customer Edge."
  value       = var.enable_kvm ? var.kvm_domain_name : null
}

output "kvm_frr_container_name" {
  description = "FRR container paired with the KVM CE for BGP verification."
  value       = try(docker_container.kvm_frr[0].name, null)
}

output "kvm_client_container_name" {
  description = "Local curl test-client container name."
  value       = try(docker_container.kvm_client[0].name, null)
}

output "kvm_network_name" {
  description = "Libvirt network used by the KVM CE, FRR, and client."
  value       = var.enable_kvm ? var.kvm_network_name : null
}

output "kvm_ce_address" {
  description = "KVM Customer Edge address on the libvirt network."
  value       = var.enable_kvm ? var.kvm_ce_address : null
}

output "kvm_frr_address" {
  description = "FRR BGP peer address on the libvirt network."
  value       = var.enable_kvm ? var.kvm_frr_address : null
}

output "kvm_vip" {
  description = "External VIP advertised by the KVM CE to FRR."
  value       = var.enable_kvm ? var.kvm_vip : null
}

output "kvm_lb_domain" {
  description = "Domain served by the HTTP load balancer advertised on the KVM VIP."
  value       = var.enable_kvm ? var.kvm_lb_domain : null
}

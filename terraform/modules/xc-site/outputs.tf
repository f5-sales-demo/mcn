output "site_name" {
  description = "XC securemesh_site_v2 name."
  value       = xcsh_securemesh_site_v2.this.name
}

output "bgp_name" {
  description = "XC bgp object name (null when enable_bgp is false)."
  value       = one(xcsh_bgp.this[*].name)
}

output "interface_name" {
  description = "Auto-derived network_interface object name the BGP peer binds to."
  value       = var.interface_name
}

output "peer_count" {
  description = "Number of external BGP peers configured (one per Route Server IP; 0 when enable_bgp is false)."
  value       = var.enable_bgp ? var.rs_peer_count : 0
}

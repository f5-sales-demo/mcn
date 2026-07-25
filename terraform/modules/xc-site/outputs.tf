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

output "registration_name" {
  description = "Runtime registration name (r-<uuid>) resolved from the site name; null until the CE has registered."
  value       = data.xcsh_site_registration.this.found ? data.xcsh_site_registration.this.name : null
}

output "registration_state" {
  description = "Current registration state reported by XC (NEW, APPROVED, ONLINE, ...); null until the CE has registered."
  value       = data.xcsh_site_registration.this.found ? data.xcsh_site_registration.this.state : null
}

output "registration_approval_name" {
  description = "Name of the approved registration (null when approve_registration is false or the CE has not registered yet)."
  value       = one(xcsh_registration_approval.this[*].name)
}

output "peer_count" {
  description = "Number of external BGP peers configured (one per Route Server IP; 0 when enable_bgp is false)."
  value       = var.enable_bgp ? var.rs_peer_count : 0
}

variable "site_name" {
  description = "XC securemesh_site_v2 name (e.g. mcn-ce-ha-eastus01), created in namespace system."
  type        = string
}

variable "hostname" {
  description = "CE node hostname, must match the Azure VM computer name."
  type        = string
}

variable "admin_password" {
  description = "Password for the site-managed node-local admin account. The API receives its Base64 form through authenticated HTTPS."
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "Public key for the site-managed node-local admin account."
  type        = string
}

variable "interface_name" {
  description = "Auto-derived network_interface object name the BGP peer references: ves-io-securemesh-site-v2-<site>-network-<hostname>-eth0-0."
  type        = string
}

variable "rs_peer_ips" {
  description = "List of Azure Route Server BGP peer IPs (virtual_router_ips), e.g. [10.0.4.4, 10.0.4.5]. Values may be unknown until apply; the count of peers comes from rs_peer_count so the peers block expands at plan time."
  type        = list(string)
}

variable "rs_peer_count" {
  description = "Number of external BGP peers (Azure Route Server always exposes exactly 2 virtual router IPs). Drives the peers block with a plan-known count so for_each never sees an unknown value."
  type        = number
  default     = 2
}

variable "ce_asn" {
  description = "CE (local) BGP ASN."
  type        = number
  default     = 64512
}

variable "rs_asn" {
  description = "Route Server (peer) BGP ASN."
  type        = number
  default     = 65515
}

variable "peer_port" {
  description = "BGP peer TCP port."
  type        = number
  default     = 179
}

variable "labels" {
  description = "Labels applied to the site object."
  type        = map(string)
  default     = {}
}

variable "enable_bgp" {
  description = "Create the xcsh_bgp object. Defaults true, and nothing gates it: the object-ref name length blocker that once forced it false was removed in provider v3.74.0. Retained only as an escape hatch for planning or deploying the graph without BGP. See main.tf."
  type        = bool
  default     = true
}

variable "os_version" {
  description = "CE operating system version. Empty deliberately selects the server-advertised latest version; set a value only to reproduce an older build."
  type        = string
  default     = ""
}

variable "sw_version" {
  description = "CE F5 Distributed Cloud software version. Empty deliberately selects the server-advertised latest build; set a value only to reproduce an older build."
  type        = string
  default     = ""
}

variable "site_name" {
  description = "XC securemesh_site_v2 name (e.g. ar-bgp-eastus01), created in namespace system."
  type        = string
}

variable "hostname" {
  description = "CE node hostname, must match the Azure VM computer name."
  type        = string
}

variable "interface_name" {
  description = "Auto-derived network_interface object name the BGP peer references: ves-io-securemesh-site-v2-<site>-network-<hostname>-eth0-0."
  type        = string
}

variable "mgmt_nic_mac" {
  description = "MAC address of the CE eth0/SLO NIC. Pins the SMSv2 interface to the NIC."
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
  description = "Create the xcsh_bgp object. Defaults true (faithful intent). BLOCKED by a provider validator bug (object-ref name capped at 63 < the real 71-char XC interface name); set false to plan the rest of the graph until the provider is fixed. See main.tf."
  type        = bool
  default     = true
}

variable "os_version" {
  description = "Pin the CE operating_system_version (e.g. 9.2024.6) to avoid a force-upgrade; empty = server default (latest)."
  type        = string
  default     = ""
}

variable "sw_version" {
  description = "Pin the CE volterra_software_version (e.g. crt-20250613-3382) to avoid a force-upgrade; empty = server default (latest)."
  type        = string
  default     = ""
}

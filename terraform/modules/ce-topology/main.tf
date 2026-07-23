# Pure computation module: expands ce_count into the per-CE node map that drives
# the ce-node, xc-site and azure-route-server-bgp for_each loops. Has NO
# providers and NO data sources, so it is fully hermetic and plan-testable at
# any N without Azure/XC credentials (see tests/n_scaling.tftest.hcl).

terraform {
  required_version = ">= 1.8"
}

variable "ce_count" {
  description = "Number of CE nodes (1..3)."
  type        = number
  default     = 3

  validation {
    condition     = var.ce_count >= 1 && var.ce_count <= 3
    error_message = "ce_count must be between 1 and 3."
  }
}

variable "region_short" {
  description = "Short region token (e.g. eastus)."
  type        = string
  default     = "eastus"
}

variable "mgmt_subnet_prefix" {
  description = "Management subnet prefix. The eth0/SLO IP is derived from it (4 + index)."
  type        = string
  default     = "10.0.1.0/26"
}

variable "hostname_prefix" {
  description = "Prefix for CE VM hostnames (hostname = <prefix>-0<n>)."
  type        = string
  default     = "f5-xc-ce-vm"
}

variable "site_prefix" {
  description = "Prefix for XC site names (site = <prefix>-<region_short>0<n>)."
  type        = string
  default     = "ar-bgp"
}

locals {
  ce_nodes = {
    for i in range(var.ce_count) : "${var.region_short}0${i + 1}" => {
      index     = i
      hostname  = "${var.hostname_prefix}-0${i + 1}"
      site_name = "${var.site_prefix}-${var.region_short}0${i + 1}"
      # eth0/SLO IP: 10.0.1.4, .5, .6 for i = 0, 1, 2.
      slo_ip = cidrhost(var.mgmt_subnet_prefix, 4 + i)
      # Availability zone 1, 2, 3.
      az = element(["1", "2", "3"], i)
      # The network_interface object XC auto-creates for the explicit SLO
      # interface. The bgp peer references it by this exact name.
      interface_name = "ves-io-securemesh-site-v2-${var.site_prefix}-${var.region_short}0${i + 1}-network-${var.hostname_prefix}-0${i + 1}-eth0-0"
    }
  }
}

output "ce_nodes" {
  description = "Map keyed by <region_short>0<n> of per-CE attributes (hostname, site_name, slo_ip, az, interface_name, index)."
  value       = local.ce_nodes
}

output "ce_count" {
  description = "Number of CE nodes expanded."
  value       = length(local.ce_nodes)
}

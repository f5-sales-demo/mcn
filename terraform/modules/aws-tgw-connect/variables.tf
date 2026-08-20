# Inputs originate only from an authenticated, schema-attested telemetry source.
# This module does not infer CE interfaces, GRE endpoints, BGP parameters, MTU, or routes.

variable "vpc_id" {
  description = "AWS VPC ID used as the Transit Gateway Connect transport attachment."
  type        = string
}

variable "amazon_side_asn" {
  description = "Amazon-side ASN attested by the runtime telemetry response."
  type        = number

  validation {
    condition     = var.amazon_side_asn >= 1 && var.amazon_side_asn <= 4294967295
    error_message = "amazon_side_asn must be a valid 32-bit ASN."
  }
}

variable "transport_subnet_ids" {
  description = "One ordered transport subnet ID per selected availability zone."
  type        = list(string)

  validation {
    condition     = length(var.transport_subnet_ids) > 0 && length(var.transport_subnet_ids) == length(toset(var.transport_subnet_ids))
    error_message = "transport_subnet_ids must contain one or more unique subnet IDs."
  }
}

variable "interfaces" {
  description = "Ordered CE GRE/BGP interface semantics supplied by authoritative runtime telemetry."
  type = map(object({
    interface_order   = number
    gre_peer_address  = string
    inside_cidr_block = string
    bgp_local_asn     = number
    bgp_remote_asn    = number
    effective_mtu     = number
  }))

  validation {
    condition     = length(var.interfaces) > 0 && length(var.interfaces) == length(toset([for peer in values(var.interfaces) : peer.interface_order]))
    error_message = "interfaces must contain one or more uniquely ordered telemetry-attested CE interfaces."
  }
}

variable "routes" {
  description = "Route CIDR to CE-interface key mapping supplied by authoritative runtime telemetry."
  type        = map(string)

  validation {
    condition     = alltrue([for interface_key in values(var.routes) : contains(keys(var.interfaces), interface_key)])
    error_message = "Each route must name an interface present in interfaces."
  }
}

variable "name_prefix" {
  description = "Non-sensitive prefix used only for AWS resource tags."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create for the hub."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "hub_cidr" {
  description = "Hub VNet address space."
  type        = string
}

variable "mgmt_subnet_prefix" {
  description = "snet-hub-management prefix."
  type        = string
}

variable "external_subnet_prefix" {
  description = "snet-hub-external prefix."
  type        = string
}

variable "internal_subnet_prefix" {
  description = "snet-hub-internal prefix."
  type        = string
}

variable "route_server_subnet_prefix" {
  description = "RouteServerSubnet prefix (/27, no NSG, no route table)."
  type        = string
}

variable "route_server_name" {
  description = "Azure Route Server name."
  type        = string
  default     = "ce-ha-lab-rrs"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

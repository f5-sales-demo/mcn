variable "vpc_id" {
  description = "AWS VPC ID used as the Transit Gateway Connect transport attachment."
  type        = string
}
variable "amazon_side_asn" {
  description = "Amazon-side ASN configured on the Transit Gateway."
  type        = number
  validation {
    condition     = var.amazon_side_asn >= 1 && var.amazon_side_asn <= 4294967295
    error_message = "amazon_side_asn must be a valid 32-bit ASN."
  }
}
variable "transit_gateway_cidr_block" {
  description = "Non-overlapping IPv4 CIDR owned by the Transit Gateway for GRE endpoints."
  type        = string
  validation {
    condition     = can(cidrhost(var.transit_gateway_cidr_block, 0))
    error_message = "transit_gateway_cidr_block must be a valid IPv4 CIDR."
  }
}
variable "transport_subnet_ids" {
  description = "One transport subnet ID per selected availability zone."
  type        = list(string)
  validation {
    condition     = length(var.transport_subnet_ids) == 3 && length(var.transport_subnet_ids) == length(toset(var.transport_subnet_ids))
    error_message = "transport_subnet_ids must contain exactly three unique subnet IDs."
  }
}
variable "name_prefix" {
  description = "Non-sensitive prefix used only for AWS resource tags."
  type        = string
}

# ---------------------------------------------------------
# AWS site deployment & placement
# ---------------------------------------------------------

variable "enable_aws" {
  description = "Enable deployment of the AWS Customer Edge site, VPC, EC2 instances, and XC resources."
  type        = bool
  default     = false
}

variable "aws_ce_ami_id" {
  description = "Explicit approved AWS Marketplace AMI ID for Customer Edge instances. A deployment must not select the most-recent image dynamically."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.aws_ce_ami_id == null || can(regex("^ami-[0-9a-f]+$", var.aws_ce_ami_id))
    error_message = "aws_ce_ami_id must be an AWS AMI ID such as ami-0123456789abcdef0."
  }
}

variable "enable_aws_tgw_connect" {
  description = "Enable the v6-only SMSv2 AWS Transit Gateway Connect topology."
  type        = bool
  default     = false
}

variable "aws_tgw_asn" {
  description = "Amazon-side BGP ASN for the Transit Gateway."
  type        = number
  default     = 64520

  validation {
    condition     = var.aws_tgw_asn >= 1 && var.aws_tgw_asn <= 4294967295
    error_message = "aws_tgw_asn must be a valid 32-bit ASN."
  }
}

variable "aws_ce_bgp_asn" {
  description = "BGP ASN used by the AWS Customer Edge site."
  type        = number
  default     = 64513

  validation {
    condition     = var.aws_ce_bgp_asn >= 1 && var.aws_ce_bgp_asn <= 4294967295 && var.aws_ce_bgp_asn != var.aws_tgw_asn
    error_message = "aws_ce_bgp_asn must be a valid 32-bit ASN different from aws_tgw_asn."
  }
}

variable "aws_tgw_gre_cidr" {
  description = "Non-overlapping /24 CIDR owned by the Transit Gateway for GRE endpoints."
  type        = string
  default     = "100.64.0.0/24"

  validation {
    condition     = can(cidrhost(var.aws_tgw_gre_cidr, 0)) && try(tonumber(split("/", var.aws_tgw_gre_cidr)[1]), 0) == 24
    error_message = "aws_tgw_gre_cidr must be a valid IPv4 /24."
  }
}

variable "aws_tgw_inside_cidr" {
  description = "Link-local /24 subdivided into one AWS-owned /29 per physical CE interface."
  type        = string
  default     = "169.254.100.0/24"

  validation {
    condition     = can(cidrhost(var.aws_tgw_inside_cidr, 0)) && try(tonumber(split("/", var.aws_tgw_inside_cidr)[1]), 0) == 24
    error_message = "aws_tgw_inside_cidr must be a valid IPv4 /24."
  }
}

variable "aws_smsv2_interface_mtu" {
  description = "Expected MTU configured on every AWS SMSv2 SLO and SLI interface."
  type        = number
  default     = 1500
}

variable "aws_bgp_convergence_timeout_seconds" {
  description = "Maximum bounded wait for authoritative BGP and route convergence."
  type        = number
  default     = 600
}

variable "aws_bgp_poll_interval_seconds" {
  description = "Polling interval for authoritative BGP and route observations."
  type        = number
  default     = 10
}

variable "aws_bgp_max_observation_age_seconds" {
  description = "Maximum age accepted for an F5 XC BGP observation."
  type        = number
  default     = 120
}

variable "aws_location" {
  description = "AWS region for all AWS resources."
  type        = string
  default     = "us-east-2"
}

variable "aws_vpc_cidr" {
  description = "AWS VPC address space."
  type        = string
  default     = "10.150.0.0/16"
}

variable "aws_ce_count" {
  description = "Number of Customer Edge EC2 nodes to deploy in AWS."
  type        = number
  default     = 3
}

variable "aws_instance_type" {
  description = "EC2 instance size for the Customer Edge nodes."
  type        = string
  default     = "m5.2xlarge"
}

variable "aws_vip" {
  description = "HA VIP for AWS CEs advertised as a /32 via eBGP."
  type        = string
  default     = "10.150.0.10"

  validation {
    condition     = can(cidrhost("${var.aws_vip}/32", 0))
    error_message = "aws_vip must be a valid IPv4 address."
  }
}

variable "aws_lb_domain" {
  description = "Domain name for the HTTP Load Balancer serving the AWS CE site."
  type        = string
  default     = "aws.mcn-ce-ha.f5-sales-demo.com"
}

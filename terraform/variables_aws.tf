# ---------------------------------------------------------
# AWS site deployment & placement
# ---------------------------------------------------------

variable "enable_aws" {
  description = "Enable the AWS Route Server showcase: VPC, three independent Customer Edge sites, Route Server peers, route propagation, and a test client."
  type        = bool
  default     = true
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

variable "aws_instance_type" {
  description = "EC2 instance size for the Customer Edge nodes."
  type        = string
  default     = "m5.2xlarge"
}

variable "aws_root_volume_size_gb" {
  description = "Encrypted gp3 root volume size for each AWS Customer Edge. F5 requires at least 80 GB; the marketplace snapshot is only 79 GiB."
  type        = number
  default     = 80

  validation {
    condition     = var.aws_root_volume_size_gb >= 80
    error_message = "aws_root_volume_size_gb must be at least 80 GB for a supported Customer Edge."
  }
}

variable "aws_vip" {
  description = "VIP advertised as a /32 by every AWS Customer Edge. It must be outside aws_vpc_cidr so the Route Server can install it dynamically."
  type        = string
  default     = "198.51.100.10"

  validation {
    condition     = can(cidrhost("${var.aws_vip}/32", 0))
    error_message = "aws_vip must be a valid IPv4 address."
  }
}

variable "aws_route_server_asn" {
  description = "Amazon-side ASN for the VPC Route Server."
  type        = number
  default     = 64513
}

variable "aws_ce_asn" {
  description = "ASN used by the independent AWS Customer Edge sites."
  type        = number
  default     = 64512
}

variable "aws_site_prefix" {
  description = "Prefix for AWS single-node F5 site names. Each CE receives <aws_site_prefix>-01, -02, or -03."
  type        = string
  default     = null
}

variable "aws_test_client_instance_type" {
  description = "EC2 instance type for the AWS HTTP test client."
  type        = string
  default     = "t3.micro"
}

variable "aws_lb_domain" {
  description = "Domain name for the HTTP Load Balancer serving the AWS CE site."
  type        = string
  default     = "aws.mcn-ce-ha.f5-sales-demo.com"

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.aws_lb_domain))
    error_message = "aws_lb_domain must be a fully-qualified lowercase domain name (for example aws.mcn-ce-ha.f5-sales-demo.com)."
  }
}

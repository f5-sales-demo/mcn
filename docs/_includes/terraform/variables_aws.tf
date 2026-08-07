# ---------------------------------------------------------
# AWS site deployment & placement
# ---------------------------------------------------------

variable "enable_aws" {
  description = "Enable deployment of the AWS Customer Edge site, VPC, EC2 instances, and XC resources."
  type        = bool
  default     = false
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

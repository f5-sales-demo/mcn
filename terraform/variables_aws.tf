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
  description = "Request AWS Transit Gateway Connect BGP. This is unavailable until an immutable F5 SMSv2 telemetry contract and matching live capability response attest the required runtime semantics."
  type        = bool
  default     = false
}

variable "smsv2_contract_release" {
  description = "Immutable stable SMSv2 contract release to verify before an AWS TGW Connect request."
  type        = string
  default     = "v2.1.222"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.smsv2_contract_release))
    error_message = "smsv2_contract_release must be a stable vX.Y.Z release tag."
  }
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

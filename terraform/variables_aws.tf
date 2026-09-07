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

variable "aws_ssh_public_key" {
  description = "Optional AWS-only SSH public key material. When empty, the shared ssh_public_key input is used."
  type        = string
  default     = ""
}

variable "enable_aws_tgw_connect" {
  description = "Enable the v7 SMSv2 AWS Transit Gateway Connect topology."
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

variable "aws_smsv2_devices" {
  description = "Guest ethernet device names by independent AWS site key, verified against each ENI MAC. Required when AWS is enabled; no role-to-device names are inferred."
  type = map(object({
    slo = string
    sli = string
  }))
  default  = {}
  nullable = false

  validation {
    condition = !var.enable_aws || toset(keys(var.aws_smsv2_devices)) == toset([
      for index in range(var.aws_ce_count) : format("%02d", index + 1)
    ])
    error_message = "Supply aws_smsv2_devices for every enabled AWS site key, with no extra keys."
  }

  validation {
    condition = alltrue([for devices in values(var.aws_smsv2_devices) : try(
      devices.slo != devices.sli &&
      length(devices.slo) >= 1 && length(devices.slo) <= 64 && trimspace(devices.slo) == devices.slo &&
      length(devices.sli) >= 1 && length(devices.sli) <= 64 && trimspace(devices.sli) == devices.sli,
      false
    )])
    error_message = "Each site needs distinct, nonempty SLO and SLI guest device names of at most 64 characters without surrounding whitespace."
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


variable "aws_location" {
  description = "AWS region for all AWS resources."
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_vpc_cidr" {
  description = "AWS VPC address space."
  type        = string
  default     = "10.150.0.0/16"
}

variable "aws_ce_count" {
  description = "Number of independent single-node Customer Edge sites. The validated showcase topology requires exactly three."
  type        = number
  default     = 3

  validation {
    condition     = var.aws_ce_count == 3
    error_message = "aws_ce_count must remain 3 for the validated three-site showcase."
  }
}

variable "aws_bootstrap_site_keys" {
  description = "Cumulative AWS site keys whose JWT token and cloud-init are issued during a controlled replacement. Use [\"01\"], then [\"01\", \"02\"], then all three; the default is the complete topology."
  type        = list(string)
  default     = ["01", "02", "03"]

  validation {
    condition     = contains(["01", "01,02", "01,02,03"], join(",", var.aws_bootstrap_site_keys))
    error_message = "aws_bootstrap_site_keys must be a non-empty cumulative prefix: [\"01\"], [\"01\", \"02\"], or [\"01\", \"02\", \"03\"]."
  }
}

variable "aws_instance_type" {
  description = "EC2 instance size for the Customer Edge nodes."
  type        = string
  default     = "m5.2xlarge"
}

variable "aws_vip" {
  description = "Plan-bound private address of the internal AWS Network Load Balancer in the workload subnet."
  type        = string
  default     = "10.151.1.10"

  validation {
    condition     = can(cidrhost("${var.aws_vip}/32", 0))
    error_message = "aws_vip must be a valid IPv4 address."
  }
}

variable "aws_workload_vpc_cidr" {
  description = "Address space for the TGW-attached AWS workload VPC."
  type        = string
  default     = "10.151.0.0/16"
}

variable "aws_baseline_software_version" {
  description = "Verified software version installed before the showcase upgrade."
  type        = string
  default     = "crt-20251002-0027"
}

variable "aws_baseline_os_version" {
  description = "Verified operating-system version installed before the showcase upgrade."
  type        = string
  default     = "9.2026.10"
}

variable "aws_target_software_version" {
  description = "Tenant-advertised software version selected for the showcase upgrade."
  type        = string
  default     = "crt-20260201-0179"
}

variable "aws_target_os_version" {
  description = "Tenant-advertised operating-system version selected for the showcase upgrade."
  type        = string
  default     = "9.2026.17"
}

variable "aws_upgrade_wait" {
  description = "Wait for every supplied upgrade target to be installed and for each site to return ONLINE."
  type        = bool
  default     = false
}

variable "aws_upgrade_timeout_seconds" {
  description = "Bounded per-site upgrade convergence timeout."
  type        = number
  default     = 7200
}

variable "aws_upgrade_poll_interval_seconds" {
  description = "Polling interval for site upgrade observations."
  type        = number
  default     = 30
}

variable "aws_upgrade_observed_sites" {
  description = "Canonical two-digit AWS site keys observed by the upgrade status data source."
  type        = set(string)
  default     = ["01", "02", "03"]

  validation {
    condition     = length(setsubtract(var.aws_upgrade_observed_sites, toset(["01", "02", "03"]))) == 0
    error_message = "aws_upgrade_observed_sites may contain only 01, 02, and 03."
  }
}

variable "aws_lb_domain" {
  description = "Domain name for the HTTP Load Balancer serving the AWS CE site."
  type        = string
  default     = "aws.mcn-ce-ha.f5-sales-demo.com"
}

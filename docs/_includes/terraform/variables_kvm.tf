# KVM Customer Edge showcase. The generated xcsh_site_image data source owns the
# F5 QCOW2 lookup, so this interface contains no caller-supplied image path.
variable "enable_kvm" {
  description = "Enable one KVM Customer Edge, its FRR BGP peer, and a local test client."
  type        = bool
  default     = true
}

variable "kvm_domain_name" {
  description = "Libvirt domain name for the KVM Customer Edge."
  type        = string
  default     = "mcn-kvm-ce"
}

variable "kvm_network_name" {
  description = "Libvirt network used by the CE, FRR peer, and test client."
  type        = string
  default     = "mcn-kvm-net"
}

variable "kvm_network_cidr" {
  description = "IPv4 network for the local KVM showcase."
  type        = string
  default     = "172.30.10.0/24"
}

variable "kvm_ce_address" {
  description = "Static SLO IPv4 address for the KVM Customer Edge."
  type        = string
  default     = "172.30.10.10"
}

variable "kvm_frr_address" {
  description = "Static IPv4 address of the local FRR BGP peer."
  type        = string
  default     = "172.30.10.2"
}

variable "kvm_client_address" {
  description = "Static IPv4 address of the local HTTP test client."
  type        = string
  default     = "172.30.10.20"
}

variable "kvm_vip" {
  description = "External VIP advertised by the KVM Customer Edge to FRR."
  type        = string
  default     = "198.51.100.20"

  validation {
    condition     = can(cidrhost("${var.kvm_vip}/32", 0))
    error_message = "kvm_vip must be a valid IPv4 address."
  }
}

variable "kvm_lb_domain" {
  description = "Domain name for the HTTP load balancer advertised on the KVM VIP."
  type        = string
  default     = "kvm.mcn-ce-ha.f5-sales-demo.com"

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.kvm_lb_domain))
    error_message = "kvm_lb_domain must be a fully-qualified lowercase domain name (for example kvm.mcn-ce-ha.f5-sales-demo.com)."
  }
}

variable "kvm_ce_asn" {
  description = "BGP ASN for the KVM Customer Edge."
  type        = number
  default     = 64520
}

variable "kvm_frr_asn" {
  description = "BGP ASN for the local FRR peer."
  type        = number
  default     = 64521
}

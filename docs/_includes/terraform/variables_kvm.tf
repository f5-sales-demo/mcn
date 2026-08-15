# KVM Customer Edge showcase. The CE image is intentionally required whenever
# KVM is enabled: F5 issues this QCOW2 image for the created site; substituting a
# generic cloud image cannot produce a supported Customer Edge.
variable "enable_kvm" {
  description = "Enable one KVM Customer Edge, its FRR BGP peer, and a local test client."
  type        = bool
  default     = true
}

variable "kvm_ce_image_path" {
  description = "Absolute path on the libvirt host to the F5 Distributed Cloud CE QCOW2 image downloaded for this site. Required when enable_kvm is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_kvm || trimspace(var.kvm_ce_image_path) != ""
    error_message = "kvm_ce_image_path is required when enable_kvm is true; download the F5 CE QCOW2 image for the KVM site first."
  }
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
  default     = "172.30.10.1"
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

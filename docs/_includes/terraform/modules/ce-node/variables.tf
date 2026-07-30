variable "hostname" {
  description = "CE VM hostname (also the Azure VM name), e.g. f5-xc-ce-vm-01."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group (created by the hub module)."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "zone" {
  description = "Availability zone for the VM (1, 2 or 3)."
  type        = string
}

variable "vm_size" {
  description = "VM size."
  type        = string
  default     = "Standard_D8_v4"
}

variable "mgmt_subnet_id" {
  description = "snet-hub-management subnet ID (eth0/SLO)."
  type        = string
}

variable "external_subnet_id" {
  description = "snet-hub-external subnet ID."
  type        = string
}

variable "internal_subnet_id" {
  description = "snet-hub-internal subnet ID."
  type        = string
}

variable "mgmt_private_ip" {
  description = "Static private IP for the eth0/SLO (mgmt) NIC — the BGP local address (e.g. 10.0.1.4)."
  type        = string
}

variable "admin_username" {
  description = "SSH admin username."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH public key MATERIAL (string), passed down from the root."
  type        = string
}

variable "custom_data" {
  description = "Base64-encoded cloud-init custom data for the volterra-node bootstrap."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

# Sized from measurement, not from a rule of thumb. Issue #714 ran one disposable
# single-node Azure Secure Mesh v2 site per size, all from marketplace image 0.9.2,
# installing the pair the tenant advertises (crt-20260201-0179 + OS 9.2026.14):
#
#     31 GiB (the image default)   FAIL — voucher DaemonSet 0/1, site stuck
#                                  PROVISIONING with nothing installed
#     33 GB                        PASS
#     36 / 40 / 48 / 64 GB         PASS
#
# The default below is deliberately NOT the measured 33 GB floor. 33 works for that
# pair on that image today; a build with a marginally larger payload would fail there
# with no configuration change and no obvious cause — exactly the position the image
# default is in now.
#
# Do NOT size this from F5's documented "20 GB plus 15% of capacity" pre-upgrade
# figure. That check gates Console UI upgrades only and does not apply to the API
# path; applied here it predicts 48 GB would fail, and 48 GB installs cleanly.
variable "os_disk_size_gb" {
  description = "CE OS disk size in GB. The marketplace image default of 31 GiB is measured to FAIL the version pair F5 advertises (#714); 33 GB is the smallest size that works and this default carries headroom above it."
  type        = number
  default     = 64

  validation {
    condition     = var.os_disk_size_gb >= 40
    error_message = "os_disk_size_gb must be at least 40 GB. The image default of 31 GiB fails the advertised version pair, and 33 GB — the measured minimum — leaves no margin for a larger future payload (#714)."
  }
}

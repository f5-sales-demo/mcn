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

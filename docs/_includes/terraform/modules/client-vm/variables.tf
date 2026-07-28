variable "name" {
  description = "Test client VM name."
  type        = string
  default     = "ar-ecmp-client"
}

variable "resource_group_name" {
  description = "Resource group (created by the hub module)."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "subnet_id" {
  description = "snet-hub-internal subnet ID the client attaches to."
  type        = string
}

variable "vm_size" {
  description = "VM size."
  type        = string
  default     = "Standard_B2s"
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
  description = "Base64-encoded cloud-init custom data."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

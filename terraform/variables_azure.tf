# ---------------------------------------------------------
# Azure subscription / placement
# ---------------------------------------------------------

variable "subscription_id" {
  description = "Azure subscription ID used by the azurerm provider."
  type        = string
  # Default = the f5-AZR_4261_SALES_SA_ALL subscription the lab was built in.
  default = "75f86c46-9cbc-4f6c-85ea-195e3d3c8ac0"
}

variable "resource_group_name" {
  description = "Resource group that holds the hub VNet, Route Server, CE VMs and test client."
  type        = string
  default     = "rmordasiewicz-f5-xc-ce-infra"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus"
}

# ---------------------------------------------------------
# Network CIDRs
# ---------------------------------------------------------

variable "hub_cidr" {
  description = "Hub VNet address space."
  type        = string
  default     = "10.0.0.0/16"
}

variable "spoke_cidr" {
  description = "Spoke VNet address space (not deployed here; used only to assert the VIP is outside it)."
  type        = string
  default     = "10.1.0.0/16"
}

variable "mgmt_subnet_prefix" {
  description = "snet-hub-management prefix. CE eth0/SLO NICs (BGP local address) live here."
  type        = string
  default     = "10.0.1.0/26"
}

variable "external_subnet_prefix" {
  description = "snet-hub-external prefix."
  type        = string
  default     = "10.0.2.0/26"
}

variable "internal_subnet_prefix" {
  description = "snet-hub-internal prefix. The test client lives here."
  type        = string
  default     = "10.0.3.0/26"
}

variable "route_server_subnet_prefix" {
  description = "RouteServerSubnet prefix. MUST be exactly /27, named literally RouteServerSubnet, with no NSG or route table."
  type        = string
  default     = "10.0.4.0/27"

  validation {
    condition     = tonumber(split("/", var.route_server_subnet_prefix)[1]) == 27
    error_message = "RouteServerSubnet must be a /27."
  }
}

variable "route_server_name" {
  description = "Azure Route Server name."
  type        = string
  default     = "ce-ha-lab-rrs"
}

# ---------------------------------------------------------
# CE / client VM inputs
# ---------------------------------------------------------

variable "ce_vm_size" {
  description = "VM size for the Customer Edge nodes."
  type        = string
  default     = "Standard_D8_v4"
}

variable "admin_username" {
  description = "SSH admin username for the VMs."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH public key MATERIAL (the key string). When empty, read from ssh_public_key_path. Passing material keeps plan tests hermetic."
  type        = string
  default     = ""
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file, read once at the root when ssh_public_key is empty."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

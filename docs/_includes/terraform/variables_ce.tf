# ---------------------------------------------------------
# CE topology / scaling
# ---------------------------------------------------------

variable "ce_count" {
  description = "Number of single-node Secure Mesh v2 CE sites (1..3). Each originates the LB VIP via eBGP to the Azure Route Server for active/active ECMP."
  type        = number
  default     = 3

  validation {
    condition     = var.ce_count >= 1 && var.ce_count <= 3
    error_message = "ce_count must be between 1 and 3."
  }
}

# ---------------------------------------------------------
# Canada CE topology / scaling
# ---------------------------------------------------------

variable "ca_ce_count" {
  description = "Number of Canadian single-node Secure Mesh v2 CE sites (1..3)."
  type        = number
  default     = 3

  validation {
    condition     = var.ca_ce_count >= 1 && var.ca_ce_count <= 3
    error_message = "ca_ce_count must be between 1 and 3."
  }
}

variable "ca_site_prefix" {
  description = "Prefix for Canadian XC site names (site = <ca_site_prefix>-<ca_region_short>0<n>). Leave null to derive `<component>-ca`."
  type        = string
  default     = null
}

variable "region_short" {
  description = "Short region token used to build the per-CE key and site name (component `mcn-ce-ha` + region `eastus` -> site `mcn-ce-ha-eastus01`). Leave null (the default) to use var.location verbatim; set it only when the Azure region name is longer than you want inside object names."
  type        = string
  default     = null
}

variable "site_prefix" {
  description = "Prefix for XC site names (site = <prefix>-<region_short>0<n>). Leave null to use var.component. Changing it replaces each site-scoped cloud-init issuance and CE node."
  type        = string
  default     = null
}

variable "ce_asn" {
  description = "BGP ASN for the Customer Edge nodes (eBGP local ASN)."
  type        = number
  default     = 64512
}

variable "rs_asn" {
  description = "BGP ASN of the Azure Route Server (fixed by Azure at 65515)."
  type        = number
  default     = 65515
}

variable "enable_bgp" {
  description = "Create the per-CE xcsh_bgp objects. Disable only for a focused topology run without BGP."
  type        = bool
  default     = true
}

variable "ce_os_version" {
  description = "CE OS version selected at site creation. Empty selects the current version advertised by F5 Distributed Cloud."
  type        = string
  default     = ""
}

variable "ce_sw_version" {
  description = "CE software version selected at site creation. Empty selects the current build advertised by F5 Distributed Cloud."
  type        = string
  default     = ""
}

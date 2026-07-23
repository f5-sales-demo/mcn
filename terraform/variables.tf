# General variables. Domain-specific inputs live in variables_azure.tf,
# variables_xc.tf and variables_ce.tf.

variable "component" {
  description = "Component name used in tags."
  type        = string
  default     = "mcn-ce-ha"
}

variable "environment" {
  description = "Environment label used in tags."
  type        = string
  default     = "lab"
}

variable "deployer" {
  description = "Override for the deployer identifier used in tags (auto-resolved from Azure AD when empty)."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags merged with the standard tags (component/environment/deployer/managed_by)."
  type        = map(string)
  default     = {}
}

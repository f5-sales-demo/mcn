variable "component" {
  type    = string
  default = "mcn-ce-ha"
}
variable "environment" {
  type    = string
  default = "lab"
}
variable "deployer" {
  type    = string
  default = ""
}
variable "tags" {
  type    = map(string)
  default = {}
}
variable "expected_xc_tenant" {
  type    = string
  default = "f5-sales-demo"
}
variable "xc_app_namespace" {
  type    = string
  default = "multi-cloud-networking"
}
variable "origin_port" {
  type    = number
  default = 80
}
variable "deployment_generation" {
  description = "Required immutable identity for this complete AWS/XC deployment generation. Select a new value only after the preceding generation has been ownership-verified and destroyed."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", var.deployment_generation))
    error_message = "deployment_generation must be a 1-32 character DNS-style label: lowercase alphanumerics and hyphens, not starting or ending with a hyphen."
  }
}
variable "ssh_public_key" {
  type    = string
  default = ""
}
variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

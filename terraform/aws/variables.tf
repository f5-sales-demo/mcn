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
variable "site_prefix" {
  type     = string
  default  = null
  nullable = true
}
variable "smsv2_site_generation" {
  type    = string
  default = "smsv2"
}
variable "ssh_public_key" {
  type    = string
  default = ""
}
variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

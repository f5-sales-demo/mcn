# ---------------------------------------------------------
# F5 XC data-plane inputs
# ---------------------------------------------------------

variable "xc_app_namespace" {
  description = "Name of a PRE-EXISTING F5 XC namespace to place the app-tier objects (origin pool + HTTP load balancer) in. This deployment reads the namespace, it never creates or deletes it: namespace creation is tenant-scoped and 403s for the deploying credential (issue #634)."
  type        = string
  default     = "multi-cloud-networking"

  validation {
    condition     = length(var.xc_app_namespace) > 0
    error_message = "xc_app_namespace must name an existing namespace; it is looked up, not created."
  }
}

variable "origin_pool_name" {
  description = "Name of the origin pool."
  type        = string
  default     = "wsp-demo-pool"
}

variable "origin_ip" {
  description = "Public IP of the origin server the pool targets."
  type        = string
  default     = "20.98.232.135"
}

variable "origin_port" {
  description = "TCP port of the origin server."
  type        = number
  default     = 80
}

variable "lb_name" {
  description = "Name of the HTTP load balancer."
  type        = string
  default     = "ar-bgp-ecmp-lb"
}

variable "lb_domain" {
  description = "Domain served by the HTTP load balancer."
  type        = string
  default     = "ar-bgp-ecmp.bankexample.com"
}

variable "vip" {
  description = "HA VIP advertised as a /32 by every CE via eBGP. MUST be outside all VNet CIDRs (Azure prefers the VNet system route over a more-specific BGP /32 otherwise)."
  type        = string
  default     = "10.250.0.10"

  validation {
    # Self-contained format check. Cross-CIDR containment is asserted by the
    # check{} block in main.tf (which may reference other variables).
    condition     = can(cidrhost("${var.vip}/32", 0))
    error_message = "vip must be a valid IPv4 address."
  }
}

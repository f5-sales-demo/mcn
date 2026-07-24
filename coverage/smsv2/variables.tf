variable "probe_name" {
  description = "Throwaway SMSv2 site name (fresh per run to avoid duplicate-StatusObject 500)."
  type        = string
  default     = "cov-probe-01"
}

variable "mtu" {
  description = "SLO interface MTU. Provider validator: AtMost(16384) (API rule is 0 or 512-16384). S1 pushes >16384 to prove rejection."
  type        = number
  default     = 1500
}

variable "priority" {
  description = "eth0 interface priority. Provider validator: Between(0, 255). S1 pushes >255 to prove rejection."
  type        = number
  default     = 10
}

variable "vlan_id" {
  description = "vlan_interface VLAN tag. Provider validator: Between(1, 4095). S1 pushes >4095 to prove rejection."
  type        = number
  default     = 100
}

variable "proxy_port" {
  description = "custom_proxy port. Provider validator: Between(0, 65535). S1 pushes >65535 to prove rejection."
  type        = number
  default     = 8080
}

variable "mac" {
  description = "eth0 ethernet_interface MAC. Provider validator: `MACValidator()`. S2 pushes \"not-a-mac\" to prove rejection. Wired only when string_arms=true."
  type        = string
  default     = "7C-1E-52-7F-F8-12"
}

variable "node_type" {
  description = "node_list[].type. Provider validator: `OneOf(\"Control\", \"Worker\")`. S2 pushes \"Bogus\" to prove rejection. Always wired (valid default keeps the base probe live-appliable)."
  type        = string
  default     = "Control"
}

variable "ip_address" {
  description = "static_ip.ip_address (CIDR). Provider validator: `CIDRValidator()`. S2 pushes \"999.999.0.0/8\" to prove rejection. Rendered only when string_arms=true."
  type        = string
  default     = "10.0.1.5/24"
}

variable "default_gw" {
  description = "static_ip.default_gw (plain IP). Provider validator: `IPValidator()`. Rendered only when string_arms=true."
  type        = string
  default     = "10.0.1.1"
}

variable "nameserver" {
  description = "local_vrf.sli_config.nameserver (plain IPv4). Provider validator: `IPv4Validator()`. S2 pushes an invalid IPv4 to prove rejection. Rendered only when vrf_string_arms=true."
  type        = string
  default     = "10.0.2.53"
}

variable "vip" {
  description = "local_vrf.sli_config.vip (plain IPv4). Provider validator: `IPv4Validator()`. Rendered only when vrf_string_arms=true."
  type        = string
  default     = "10.0.2.100"
}

variable "vrf_string_arms" {
  description = <<-EOT
    When true, the probe renders an additional `local_vrf.sli_config` block exposing the
    `nameserver` and `vip` leaves so the `IPv4Validator()` string validator is reachable at PLAN
    time. Default false: `sli_config` is a distinct `local_vrf` oneof arm from the proven base
    `default_sli_config{}`, so it is NOT live-applied here (it would collide with the base VRF arm,
    an S3 oneof-coverage concern). Set true only under mock_provider tests, where the schema
    validator fires at plan without contacting the API.
  EOT
  type        = bool
  default     = false
}

variable "string_arms" {
  description = <<-EOT
    When true (default), the probe wires the eth0 ethernet_interface `mac` leaf and renders a
    `static_ip { ip_address, default_gw }` address block in place of the base `dhcp_client {}`,
    so the `MACValidator()`, `CIDRValidator()` and `IPValidator()` string validators are reachable
    at PLAN time (they fire during plan under both mock_provider tests and live plans). Set false
    only for a live apply if the XC API rejects the mac/static_ip combination on the single-node
    `azure` not_managed probe: the base eth0 interface reverts to `dhcp_client {}` with no `mac`,
    which applies live and stays idempotent/import-clean, while mac/ip_address/default_gw remain
    plan-validated. The node `type` leaf is always wired (its valid default is live-safe).
  EOT
  type        = bool
  default     = true
}

variable "extended_arms" {
  description = <<-EOT
    When true (default), the probe renders the S1 vlan_interface interface entry and the
    top-level custom_proxy block so the vlan_id and proxy_port numeric leaves are reachable
    at PLAN time (schema validators fire during plan under both mock_provider tests and live
    plans). Set false only for a live apply if the XC API rejects the vlan/proxy combination:
    the base eth0 interface (which carries the mtu and priority leaves) still applies live and
    stays idempotent/import-clean, while vlan_id/proxy_port remain plan-validated.
  EOT
  type        = bool
  default     = true
}

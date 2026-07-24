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
    When true (default), the probe wires the eth0 `ethernet_interface.mac` leaf so the
    `MACValidator()` string validator is reachable at PLAN time (it fires during plan under both
    mock_provider tests and live plans). Set false only for a live apply if the XC API rejects the
    `mac` value on the single-node `azure` not_managed probe: the eth0 `ethernet_interface` then
    renders with no `mac`, which applies live and stays idempotent/import-clean, while `mac` remains
    plan-validated. Applies only when `interface_arm = "ethernet"` (the `mac` leaf lives on the
    ethernet arm). The node `type` leaf is always wired (its valid default is live-safe).

    NOTE (S3): the address_choice oneof (`dhcp_client`/`static_ip`/`no_ipv4_address`) is now driven
    by `var.address_arm`, not this toggle — so exactly one address member ever renders. The
    `static_ip` leaves (`ip_address`/`default_gw`) are reached at plan whenever `address_arm =
    "static_ip"` (the default), decoupled from `string_arms`.
  EOT
  type        = bool
  default     = true
}

# --- S3: interface / addressing oneof selectors --------------------------------------------------
# Each interface oneof is modeled as an enum selector so exactly ONE member renders and no two
# siblings of a oneof ever coexist (which would trip the provider's ConflictsWith). Defaults are
# the live-safe base arm so a bare `terraform apply` stays idempotent and import-clean.

variable "interface_arm" {
  description = <<-EOT
    interface_choice oneof member for eth0. `ethernet` (default) is the live-safe base arm and
    carries the `mac` leaf (via `string_arms`). `bond` and `vlan` 400 on a single-node `azure`
    not_managed probe (bond needs real member devices; vlan needs a parent device) so they are
    plan-only — their schema (bond `devices` `SizeBetween(1, 8)`, vlan `vlan_id` `Between(1, 4095)`)
    is proven at PLAN.
  EOT
  type        = string
  default     = "ethernet"
  validation {
    condition     = contains(["ethernet", "bond", "vlan"], var.interface_arm)
    error_message = "interface_arm must be ethernet | bond | vlan."
  }
}

variable "address_arm" {
  description = <<-EOT
    address_choice oneof member for eth0. `static_ip` (default) and `dhcp_client` and
    `no_ipv4_address` are all live-appliable. `static_ip` exposes the `ip_address` `CIDRValidator()`
    and `default_gw` `IPValidator()` leaves at PLAN; `dhcp_client`/`no_ipv4_address` are empty
    markers. Exactly one address member renders (supersedes the old `string_arms` address swap).
  EOT
  type        = string
  default     = "static_ip"
  validation {
    condition     = contains(["dhcp_client", "static_ip", "no_ipv4_address"], var.address_arm)
    error_message = "address_arm must be dhcp_client | static_ip | no_ipv4_address."
  }
}

variable "ipv6_arm" {
  description = <<-EOT
    ipv6_address_choice oneof member for eth0. `no_ipv6_address` (default) is live-appliable.
    `ipv6_auto_config` (renders the `host {}` autoconfig arm) and `static_ipv6_address` (renders
    `node_static_ip { ip_address }`, `CIDRValidator()`) 400 on a single-node IPv4 `azure` probe, so
    they are plan-only — their schema is proven at PLAN.
  EOT
  type        = string
  default     = "no_ipv6_address"
  validation {
    condition     = contains(["no_ipv6_address", "ipv6_auto_config", "static_ipv6_address"], var.ipv6_arm)
    error_message = "ipv6_arm must be no_ipv6_address | ipv6_auto_config | static_ipv6_address."
  }
}

variable "monitor_arm" {
  description = "monitoring_choice oneof member for eth0. Both `monitor` and `monitor_disabled` (default) are empty markers and live-appliable."
  type        = string
  default     = "monitor_disabled"
  validation {
    condition     = contains(["monitor", "monitor_disabled"], var.monitor_arm)
    error_message = "monitor_arm must be monitor | monitor_disabled."
  }
}

variable "s2s_iface_arm" {
  description = <<-EOT
    site_to_site_connectivity_interface_choice oneof member for eth0. Both `disabled` (default) and
    `enabled` are empty markers and both are live-appliable on the single-node `azure` probe
    (confirmed apply/idempotent/import-clean).
  EOT
  type        = string
  default     = "disabled"
  validation {
    condition     = contains(["disabled", "enabled"], var.s2s_iface_arm)
    error_message = "s2s_iface_arm must be disabled | enabled."
  }
}

variable "ipv6_address" {
  description = "static_ipv6_address.node_static_ip.ip_address (IPv6 CIDR). Provider validator: `CIDRValidator()` + `LengthBetween(7, 1024)`. Rendered only when ipv6_arm=static_ipv6_address. reject-static-ipv6 pushes a malformed CIDR."
  type        = string
  default     = "2001:db8::10/64"
}

variable "bond_devices" {
  description = "bond_interface.devices (member ethernet devices). Provider validator: `SizeBetween(1, 8)`. Rendered only when interface_arm=bond. reject-bond-devices pushes an empty list."
  type        = list(string)
  default     = ["eth1", "eth2"]
}

variable "bond_lacp_rate" {
  description = "bond_interface.lacp.rate (LACP transmit interval, seconds). Provider validator: `Between(1, 30)`. Rendered only when interface_arm=bond."
  type        = number
  default     = 1
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

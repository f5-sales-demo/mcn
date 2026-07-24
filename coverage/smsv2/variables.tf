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

# --- S4: networking / services top-level oneof selectors ------------------------------------------
# Each top-level networking/services oneof is modeled as an enum selector driving mutually-exclusive
# `dynamic` blocks so exactly ONE member of each oneof renders (no ConflictsWith trip). Every default
# is the arm the base probe already applies live, so a bare `terraform plan` (all defaults) shows NO
# diff versus the pre-S4 base. Live-appliable (S4a) arms apply/idempotent/import on the single-node
# `azure` probe; ref-dependent (S4b) and single-node-400 (S4c) arms are plan-only.

variable "services_arm" {
  description = <<-EOT
    services oneof member. `block_all_services` (default) is the base arm. `blocked_services` renders
    a `blocked_service` entry (S4a live) exposing the `network_type` `OneOf` validator.
  EOT
  type        = string
  default     = "block_all_services"
  validation {
    condition     = contains(["block_all_services", "blocked_services"], var.services_arm)
    error_message = "services_arm must be block_all_services | blocked_services."
  }
}

variable "blocked_network_type" {
  description = "blocked_services.blocked_service.network_type. Provider validator: `OneOf(VIRTUAL_NETWORK_*)`. reject-network-type pushes \"BOGUS\". No terraform validation so the provider OneOf fires at plan."
  type        = string
  default     = "VIRTUAL_NETWORK_SITE_LOCAL"
}

variable "ha_arm" {
  description = <<-EOT
    node_ha oneof member. `disable_ha` (default) is the base arm and live-appliable. `enable_ha`
    400s on a single-node `azure` probe (needs >=3 nodes) so it is plan-only (S4c).
  EOT
  type        = string
  default     = "disable_ha"
  validation {
    condition     = contains(["disable_ha", "enable_ha"], var.ha_arm)
    error_message = "ha_arm must be disable_ha | enable_ha."
  }
}

variable "dns_arm" {
  description = "dns_ntp_config dns oneof member. `f5_dns_default` (default, base) | `custom_dns` (renders `dns_servers`, S4a live)."
  type        = string
  default     = "f5_dns_default"
  validation {
    condition     = contains(["f5_dns_default", "custom_dns"], var.dns_arm)
    error_message = "dns_arm must be f5_dns_default | custom_dns."
  }
}

variable "ntp_arm" {
  description = "dns_ntp_config ntp oneof member. `f5_ntp_default` (default, base) | `custom_ntp` (renders `ntp_servers`, S4a live)."
  type        = string
  default     = "f5_ntp_default"
  validation {
    condition     = contains(["f5_ntp_default", "custom_ntp"], var.ntp_arm)
    error_message = "ntp_arm must be f5_ntp_default | custom_ntp."
  }
}

variable "dns_servers" {
  description = "custom_dns.dns_servers (list of DNS server IPs). Rendered only when dns_arm=custom_dns. Provider validator: `SizeAtMost(64)`."
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "ntp_servers" {
  description = "custom_ntp.ntp_servers (list of NTP servers). Rendered only when ntp_arm=custom_ntp. Provider validator: `SizeAtMost(64)`."
  type        = list(string)
  default     = ["216.239.35.0", "216.239.35.4"]
}

variable "proxy_arm" {
  description = <<-EOT
    enterprise_proxy oneof member. `custom_proxy` (default) keeps the S1/S2 `proxy_port` +
    `proxy_ip_address` coverage and renders only when `extended_arms` is true (matching the pre-S4
    base — `custom_proxy` 400s live on this probe). `f5_proxy` is an empty marker and S4a live.
    `none` renders neither member.
  EOT
  type        = string
  default     = "custom_proxy"
  validation {
    condition     = contains(["custom_proxy", "f5_proxy", "none"], var.proxy_arm)
    error_message = "proxy_arm must be custom_proxy | f5_proxy | none."
  }
}

variable "proxy_ip_address" {
  description = "custom_proxy.proxy_ip_address (IPv4). Provider validator: `IPv4Validator()`. reject-proxy-ip pushes \"999.1.1.1\". No terraform validation so the provider IPv4 validator fires at plan."
  type        = string
  default     = "10.0.0.10"
}

variable "proxy_bypass_arm" {
  description = <<-EOT
    proxy_bypass oneof member. `unset` (default) omits the oneof entirely (matching the pre-S4 base,
    which never set it). `no_proxy_bypass` (empty marker) and `custom_proxy_bypass` (renders
    `proxy_bypass` domain list) are S4a live.
  EOT
  type        = string
  default     = "unset"
  validation {
    condition     = contains(["unset", "no_proxy_bypass", "custom_proxy_bypass"], var.proxy_bypass_arm)
    error_message = "proxy_bypass_arm must be unset | no_proxy_bypass | custom_proxy_bypass."
  }
}

variable "proxy_bypass_domains" {
  description = "custom_proxy_bypass.proxy_bypass (list of domains to bypass the proxy). Rendered only when proxy_bypass_arm=custom_proxy_bypass."
  type        = list(string)
  default     = ["example.com", "internal.local"]
}

variable "url_cat_arm" {
  description = <<-EOT
    url_categorization oneof member. `unset` (default) omits the oneof (pre-S4 base never set it).
    `disable_url_categorization` and `enable_url_categorization` are empty markers, both S4a live.
  EOT
  type        = string
  default     = "unset"
  validation {
    condition     = contains(["unset", "disable_url_categorization", "enable_url_categorization"], var.url_cat_arm)
    error_message = "url_cat_arm must be unset | disable_url_categorization | enable_url_categorization."
  }
}

variable "mgmt_net_arm" {
  description = <<-EOT
    management_network oneof member. `unset` (default) omits the oneof (pre-S4 base never set it).
    `disable_management_network` is an empty marker, S4a live. `enable_management_network` 400s on a
    single-node `azure` probe so it is plan-only (S4c).
  EOT
  type        = string
  default     = "unset"
  validation {
    condition     = contains(["unset", "disable_management_network", "enable_management_network"], var.mgmt_net_arm)
    error_message = "mgmt_net_arm must be unset | disable_management_network | enable_management_network."
  }
}

variable "s2s_slo_arm" {
  description = <<-EOT
    s2s_connectivity_slo oneof member. `no_s2s_connectivity_slo` (default, base). `dc_cluster_group_slo`
    (ObjectRefType) is ref-dependent, plan-only (S4b). `site_mesh_group_empty` renders
    `site_mesh_group_on_slo { no_site_mesh_group {} sm_connection_public_ip {} }` (S4a live).
    `site_mesh_group_ref` renders the `site_mesh_group` ObjectRefType arm, plan-only (S4b).
  EOT
  type        = string
  default     = "no_s2s_connectivity_slo"
  validation {
    condition     = contains(["no_s2s_connectivity_slo", "dc_cluster_group_slo", "site_mesh_group_empty", "site_mesh_group_ref"], var.s2s_slo_arm)
    error_message = "s2s_slo_arm must be no_s2s_connectivity_slo | dc_cluster_group_slo | site_mesh_group_empty | site_mesh_group_ref."
  }
}

variable "s2s_sli_arm" {
  description = "s2s_connectivity_sli oneof member. `no_s2s_connectivity_sli` (default, base) | `dc_cluster_group_sli` (ObjectRefType, ref-dependent, plan-only S4b)."
  type        = string
  default     = "no_s2s_connectivity_sli"
  validation {
    condition     = contains(["no_s2s_connectivity_sli", "dc_cluster_group_sli"], var.s2s_sli_arm)
    error_message = "s2s_sli_arm must be no_s2s_connectivity_sli | dc_cluster_group_sli."
  }
}

variable "forward_proxy_arm" {
  description = "forward_proxy oneof member. `no_forward_proxy` (default, base) | `active_forward_proxy_policies` (ObjectRefType list, ref-dependent, plan-only S4b)."
  type        = string
  default     = "no_forward_proxy"
  validation {
    condition     = contains(["no_forward_proxy", "active_forward_proxy_policies"], var.forward_proxy_arm)
    error_message = "forward_proxy_arm must be no_forward_proxy | active_forward_proxy_policies."
  }
}

variable "network_policy_arm" {
  description = "network_policy oneof member. `no_network_policy` (default, base) | `active_enhanced_firewall_policies` (ObjectRefType list, ref-dependent, plan-only S4b)."
  type        = string
  default     = "no_network_policy"
  validation {
    condition     = contains(["no_network_policy", "active_enhanced_firewall_policies"], var.network_policy_arm)
    error_message = "network_policy_arm must be no_network_policy | active_enhanced_firewall_policies."
  }
}

variable "logs_arm" {
  description = <<-EOT
    logs_receiver oneof member. `logs_streaming_disabled` (default, base) | `log_receiver_with_net`
    (ObjectRefType log_receiver + use_slo_sli, ref-dependent, plan-only S4b). Drives logs via
    `log_receiver_with_net`, never the stale top-level `log_receiver` field (provider #1256).
  EOT
  type        = string
  default     = "logs_streaming_disabled"
  validation {
    condition     = contains(["logs_streaming_disabled", "log_receiver_with_net"], var.logs_arm)
    error_message = "logs_arm must be logs_streaming_disabled | log_receiver_with_net."
  }
}

variable "vip_vrrp_mode" {
  description = <<-EOT
    load_balancing.vip_vrrp_mode. Empty string "" (default) omits the `load_balancing` block entirely
    (pre-S4 base never set it). `VIP_VRRP_ENABLE`/`VIP_VRRP_DISABLE`/`VIP_VRRP_INVALID` render
    `load_balancing`; ENABLE/DISABLE are S4a live. Provider validator: `OneOf(VIP_VRRP_INVALID,
    VIP_VRRP_ENABLE, VIP_VRRP_DISABLE)`. reject-vip-vrrp-mode pushes "BOGUS". No terraform validation
    so the provider OneOf fires at plan.
  EOT
  type        = string
  default     = ""
}

variable "segment_vrf_arm" {
  description = <<-EOT
    segment_vrf selector. `unset` (default) omits `segment_vrf` (pre-S4 base never set it). `inline`
    renders one `segment_vrf { segment_config { nameserver ... } }` entry. Plan-only: a live
    `segment_vrf` needs a Segment object reference the provider cannot yet inject (specs #1053).
  EOT
  type        = string
  default     = "unset"
  validation {
    condition     = contains(["unset", "inline"], var.segment_vrf_arm)
    error_message = "segment_vrf_arm must be unset | inline."
  }
}

variable "segment_nameserver" {
  description = "segment_vrf.segment_config.nameserver (IPv4). Provider validator: `IPv4Validator()`. reject-segment-nameserver pushes an invalid IPv4. No terraform validation so the provider IPv4 validator fires at plan."
  type        = string
  default     = "10.0.3.53"
}

# --- S4b plan-only ObjectRefType names (each ref points at a fictitious object in `system`; the arm
# is proven at PLAN only, so the referent need not exist) -----------------------------------------

variable "forward_proxy_policy_ref_name" {
  description = "active_forward_proxy_policies.forward_proxy_policies[].name (plan-only ref)."
  type        = string
  default     = "cov-forward-proxy-policy"
}

variable "firewall_policy_ref_name" {
  description = "active_enhanced_firewall_policies.enhanced_firewall_policies[].name (plan-only ref)."
  type        = string
  default     = "cov-enhanced-firewall-policy"
}

variable "log_receiver_ref_name" {
  description = "log_receiver_with_net.log_receiver.name (plan-only ref)."
  type        = string
  default     = "cov-log-receiver"
}

variable "dc_cluster_group_slo_ref_name" {
  description = "dc_cluster_group_slo.name (plan-only ref)."
  type        = string
  default     = "cov-dc-cluster-group-slo"
}

variable "dc_cluster_group_sli_ref_name" {
  description = "dc_cluster_group_sli.name (plan-only ref)."
  type        = string
  default     = "cov-dc-cluster-group-sli"
}

variable "site_mesh_group_ref_name" {
  description = "site_mesh_group_on_slo.site_mesh_group.name (plan-only ref)."
  type        = string
  default     = "cov-site-mesh-group"
}

variable "ref_namespace" {
  description = "Namespace for the S4b plan-only ObjectRefType references."
  type        = string
  default     = "system"
}

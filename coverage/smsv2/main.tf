# Minimal Azure-free SMSv2 probe modeled on the proven live spec
# (terraform/modules/xc-site/main.tf): azure.not_managed single Control node with
# an explicit eth0/SLO interface, and every site toggle set to its disable/no arm.
# No backing Azure VM is required — the object create/read/delete is Azure-free
# (each HTTP 200). Numeric leaves are wired to variables so later slices can push
# out-of-range values through input validation. NEVER targets the live demo sites
# (ar-bgp-eastus01/02/03) — always use a fresh throwaway probe_name.
resource "xcsh_securemesh_site_v2" "probe" {
  name      = var.probe_name
  namespace = "system"

  azure {
    not_managed {
      node_list {
        hostname = "cov-probe-node-01"
        # S2: node type exposes the OneOf("Control", "Worker") enum validator. Always wired;
        # the valid default ("Control") keeps the base probe live-appliable. Reject test pushes "Bogus".
        type = var.node_type

        interface_list {
          name     = "eth0"
          mtu      = var.mtu
          priority = var.priority

          # S3 interface_choice oneof {ethernet_interface | bond_interface | vlan_interface}. Modeled
          # as the var.interface_arm enum so exactly ONE member renders (no ConflictsWith trip).
          # ethernet (default) is live-safe; bond/vlan are plan-only (400 on a single-node probe).
          dynamic "ethernet_interface" {
            for_each = var.interface_arm == "ethernet" ? [1] : []
            content {
              device = "eth0"
              # S2: mac exposes the MACValidator() string validator. Gated by var.string_arms so a
              # live apply can fall back to no-mac if the XC API rejects it — the validator still
              # fires at PLAN time whenever string_arms is true and interface_arm is ethernet.
              mac = var.string_arms ? var.mac : null
            }
          }

          # S3 bond_interface (plan-only): devices SizeBetween(1, 8), lacp.rate Between(1, 30).
          dynamic "bond_interface" {
            for_each = var.interface_arm == "bond" ? [1] : []
            content {
              devices = var.bond_devices
              lacp {
                rate = var.bond_lacp_rate
              }
            }
          }

          # S3 vlan_interface (plan-only): vlan_id Between(1, 4095) (S1 reject already covers >4095
          # via the extended_arms second interface below; this arm proves it on the primary oneof).
          dynamic "vlan_interface" {
            for_each = var.interface_arm == "vlan" ? [1] : []
            content {
              device  = "eth0"
              vlan_id = var.vlan_id
            }
          }

          network_option {
            site_local_network {}
          }

          # S3 address_choice oneof {dhcp_client | static_ip | no_ipv4_address}, one per var.address_arm.
          # static_ip (default) exposes the ip_address CIDRValidator() and default_gw IPValidator()
          # string validators; all three arms are live-appliable.
          dynamic "dhcp_client" {
            for_each = var.address_arm == "dhcp_client" ? [1] : []
            content {}
          }

          dynamic "static_ip" {
            for_each = var.address_arm == "static_ip" ? [1] : []
            content {
              ip_address = var.ip_address
              default_gw = var.default_gw
            }
          }

          dynamic "no_ipv4_address" {
            for_each = var.address_arm == "no_ipv4_address" ? [1] : []
            content {}
          }

          # S3 ipv6_address_choice oneof {no_ipv6_address | ipv6_auto_config | static_ipv6_address}.
          # no_ipv6_address (default) is live-appliable; the other two 400 on a single-node IPv4
          # probe (plan-only). static_ipv6_address.node_static_ip.ip_address is CIDRValidator()-guarded.
          dynamic "no_ipv6_address" {
            for_each = var.ipv6_arm == "no_ipv6_address" ? [1] : []
            content {}
          }

          dynamic "ipv6_auto_config" {
            for_each = var.ipv6_arm == "ipv6_auto_config" ? [1] : []
            content {
              host {} # autoconfig_choice: host (empty) — the router arm needs an IPv6 prefix
            }
          }

          dynamic "static_ipv6_address" {
            for_each = var.ipv6_arm == "static_ipv6_address" ? [1] : []
            content {
              node_static_ip { # network_prefix_choice: node_static_ip (vs cluster_static_ip)
                ip_address = var.ipv6_address
              }
            }
          }

          # S3 monitoring_choice oneof {monitor | monitor_disabled}. Both empty, both live-appliable.
          dynamic "monitor" {
            for_each = var.monitor_arm == "monitor" ? [1] : []
            content {}
          }

          dynamic "monitor_disabled" {
            for_each = var.monitor_arm == "monitor_disabled" ? [1] : []
            content {}
          }

          # S3 site_to_site_connectivity_interface_choice oneof {disabled | enabled}. disabled
          # (default) is live-appliable; enabled needs site s2s wiring (plan-only).
          dynamic "site_to_site_connectivity_interface_disabled" {
            for_each = var.s2s_iface_arm == "disabled" ? [1] : []
            content {}
          }

          dynamic "site_to_site_connectivity_interface_enabled" {
            for_each = var.s2s_iface_arm == "enabled" ? [1] : []
            content {}
          }
        }

        # S1: a second interface exposing the vlan_interface.vlan_id leaf (validator
        # Between(1, 4095)). Gated by var.extended_arms so a live apply can fall back to
        # the proven base-only probe if the XC API rejects the vlan/proxy combination —
        # the schema validator still fires at PLAN time regardless of this toggle.
        dynamic "interface_list" {
          for_each = var.extended_arms ? [1] : []
          content {
            name = "eth0-vlan"

            vlan_interface {
              device  = "eth0"
              vlan_id = var.vlan_id
            }

            network_option {
              site_local_network {}
            }

            dhcp_client {}
          }
        }
      }
    }
  }

  block_all_services {}
  disable_ha {}

  dns_ntp_config {
    f5_dns_default {}
    f5_ntp_default {}
  }

  local_vrf {
    default_config {}
    default_sli_config {}

    # S2: sli_config exposes the nameserver/vip leaves guarded by IPv4Validator(). This is a
    # distinct local_vrf oneof arm from default_sli_config above; gated by var.vrf_string_arms
    # (default false) so it is only rendered under mock_provider plan tests — the validator fires
    # at PLAN regardless. Not live-applied (oneof collision with default_sli_config is an S3 arm).
    dynamic "sli_config" {
      for_each = var.vrf_string_arms ? [1] : []
      content {
        nameserver = var.nameserver
        vip        = var.vip
      }
    }
  }

  logs_streaming_disabled {}
  no_forward_proxy {}
  no_network_policy {}
  no_s2s_connectivity_sli {}
  no_s2s_connectivity_slo {}

  offline_survivability_mode {
    no_offline_survivability_mode {}
  }

  performance_enhancement_mode {
    perf_mode_l7_enhanced {}
  }

  re_select {
    geo_proximity {}
  }

  software_settings {
    os {
      default_os_version {}
    }
    sw {
      default_sw_version {}
    }
  }

  # S1: custom_proxy exposes the proxy_port leaf (validator Between(0, 65535)). This is the
  # custom_proxy|f5_proxy oneof, distinct from the no_forward_proxy oneof set above. Gated by
  # var.extended_arms (see the vlan_interface note); the validator fires at PLAN time regardless.
  dynamic "custom_proxy" {
    for_each = var.extended_arms ? [1] : []
    content {
      proxy_ip_address = "10.0.0.10"
      proxy_port       = var.proxy_port
    }
  }
}

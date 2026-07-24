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

  # S4 services oneof {block_all_services | blocked_services}, keyed on var.services_arm so exactly
  # one member renders. block_all_services (default) is the base arm; blocked_services renders a
  # blocked_service entry exposing the network_type OneOf validator (S4a live).
  dynamic "block_all_services" {
    for_each = var.services_arm == "block_all_services" ? [1] : []
    content {}
  }

  dynamic "blocked_services" {
    for_each = var.services_arm == "blocked_services" ? [1] : []
    content {
      blocked_service {
        network_type = var.blocked_network_type
        ssh {}
        web_user_interface {}
      }
    }
  }

  # S4 node_ha oneof {disable_ha | enable_ha}. disable_ha (default) is live; enable_ha is plan-only
  # (400 on a single-node probe — needs >=3 nodes).
  dynamic "disable_ha" {
    for_each = var.ha_arm == "disable_ha" ? [1] : []
    content {}
  }

  dynamic "enable_ha" {
    for_each = var.ha_arm == "enable_ha" ? [1] : []
    content {}
  }

  # S4 dns_ntp_config renders one dns sub-oneof member + one ntp sub-oneof member (keyed on
  # var.dns_arm / var.ntp_arm). The f5_*_default defaults match the base probe; custom_dns/custom_ntp
  # expose the dns_servers / ntp_servers list leaves (S4a live).
  dns_ntp_config {
    dynamic "f5_dns_default" {
      for_each = var.dns_arm == "f5_dns_default" ? [1] : []
      content {}
    }

    dynamic "custom_dns" {
      for_each = var.dns_arm == "custom_dns" ? [1] : []
      content {
        dns_servers = var.dns_servers
      }
    }

    dynamic "f5_ntp_default" {
      for_each = var.ntp_arm == "f5_ntp_default" ? [1] : []
      content {}
    }

    dynamic "custom_ntp" {
      for_each = var.ntp_arm == "custom_ntp" ? [1] : []
      content {
        ntp_servers = var.ntp_servers
      }
    }
  }

  # S4 proxy_bypass oneof {no_proxy_bypass | custom_proxy_bypass}, unset by default (the pre-S4 base
  # never set it) so a bare plan is unchanged. Both alternative arms are S4a live.
  dynamic "no_proxy_bypass" {
    for_each = var.proxy_bypass_arm == "no_proxy_bypass" ? [1] : []
    content {}
  }

  dynamic "custom_proxy_bypass" {
    for_each = var.proxy_bypass_arm == "custom_proxy_bypass" ? [1] : []
    content {
      proxy_bypass = var.proxy_bypass_domains
    }
  }

  # S4 url_categorization oneof {disable_url_categorization | enable_url_categorization}, unset by
  # default. Both alternative arms are empty markers and S4a live.
  dynamic "disable_url_categorization" {
    for_each = var.url_cat_arm == "disable_url_categorization" ? [1] : []
    content {}
  }

  dynamic "enable_url_categorization" {
    for_each = var.url_cat_arm == "enable_url_categorization" ? [1] : []
    content {}
  }

  # S4 management_network oneof {disable_management_network | enable_management_network}, unset by
  # default. disable_management_network is S4a live; enable_management_network is plan-only (400).
  dynamic "disable_management_network" {
    for_each = var.mgmt_net_arm == "disable_management_network" ? [1] : []
    content {}
  }

  dynamic "enable_management_network" {
    for_each = var.mgmt_net_arm == "enable_management_network" ? [1] : []
    content {}
  }

  # S4 load_balancing.vip_vrrp_mode. Omitted entirely when var.vip_vrrp_mode is "" (pre-S4 base never
  # set it). ENABLE/DISABLE are S4a live; the OneOf validator is proven by reject-vip-vrrp-mode.
  dynamic "load_balancing" {
    for_each = var.vip_vrrp_mode != "" ? [1] : []
    content {
      vip_vrrp_mode = var.vip_vrrp_mode
    }
  }

  # S4 segment_vrf (plan-only — a live segment_vrf needs a Segment object ref the provider cannot yet
  # inject, specs #1053). Renders one entry exposing the segment_config.nameserver IPv4Validator leaf.
  dynamic "segment_vrf" {
    for_each = var.segment_vrf_arm == "inline" ? [1] : []
    content {
      segment_config {
        nameserver = var.segment_nameserver
        no_static_routes {}
        no_v6_static_routes {}
      }
    }
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

  # S4 logs_receiver oneof {logs_streaming_disabled | log_receiver_with_net}. logs_streaming_disabled
  # (default) is the base arm. log_receiver_with_net is ref-dependent (plan-only, S4b); it drives logs
  # via the network-aware receiver, never the stale top-level log_receiver field (provider #1256).
  dynamic "logs_streaming_disabled" {
    for_each = var.logs_arm == "logs_streaming_disabled" ? [1] : []
    content {}
  }

  dynamic "log_receiver_with_net" {
    for_each = var.logs_arm == "log_receiver_with_net" ? [1] : []
    content {
      log_receiver {
        name      = var.log_receiver_ref_name
        namespace = var.ref_namespace
      }
      use_slo_sli {}
    }
  }

  # S4 forward_proxy oneof {no_forward_proxy | active_forward_proxy_policies}. no_forward_proxy
  # (default) is the base arm; active_forward_proxy_policies is a ref list (plan-only, S4b).
  dynamic "no_forward_proxy" {
    for_each = var.forward_proxy_arm == "no_forward_proxy" ? [1] : []
    content {}
  }

  dynamic "active_forward_proxy_policies" {
    for_each = var.forward_proxy_arm == "active_forward_proxy_policies" ? [1] : []
    content {
      forward_proxy_policies {
        name      = var.forward_proxy_policy_ref_name
        namespace = var.ref_namespace
      }
    }
  }

  # S4 network_policy oneof {no_network_policy | active_enhanced_firewall_policies}. no_network_policy
  # (default) is the base arm; active_enhanced_firewall_policies is a ref list (plan-only, S4b).
  dynamic "no_network_policy" {
    for_each = var.network_policy_arm == "no_network_policy" ? [1] : []
    content {}
  }

  dynamic "active_enhanced_firewall_policies" {
    for_each = var.network_policy_arm == "active_enhanced_firewall_policies" ? [1] : []
    content {
      enhanced_firewall_policies {
        name      = var.firewall_policy_ref_name
        namespace = var.ref_namespace
      }
    }
  }

  # S4 s2s_connectivity_sli oneof {no_s2s_connectivity_sli | dc_cluster_group_sli}. Base arm default;
  # dc_cluster_group_sli is an ObjectRefType (plan-only, S4b).
  dynamic "no_s2s_connectivity_sli" {
    for_each = var.s2s_sli_arm == "no_s2s_connectivity_sli" ? [1] : []
    content {}
  }

  dynamic "dc_cluster_group_sli" {
    for_each = var.s2s_sli_arm == "dc_cluster_group_sli" ? [1] : []
    content {
      name      = var.dc_cluster_group_sli_ref_name
      namespace = var.ref_namespace
    }
  }

  # S4 s2s_connectivity_slo oneof {no_s2s_connectivity_slo | dc_cluster_group_slo |
  # site_mesh_group_on_slo}. no_s2s_connectivity_slo (default) is the base arm. dc_cluster_group_slo
  # is an ObjectRefType (plan-only, S4b). site_mesh_group_on_slo carries two sub-oneofs
  # (mesh_group_choice + connection_choice): the all-empty variant
  # {no_site_mesh_group{} sm_connection_public_ip{}} is S4a live; the site_mesh_group ref variant is
  # plan-only (S4b).
  dynamic "no_s2s_connectivity_slo" {
    for_each = var.s2s_slo_arm == "no_s2s_connectivity_slo" ? [1] : []
    content {}
  }

  dynamic "dc_cluster_group_slo" {
    for_each = var.s2s_slo_arm == "dc_cluster_group_slo" ? [1] : []
    content {
      name      = var.dc_cluster_group_slo_ref_name
      namespace = var.ref_namespace
    }
  }

  dynamic "site_mesh_group_on_slo" {
    for_each = var.s2s_slo_arm == "site_mesh_group_empty" || var.s2s_slo_arm == "site_mesh_group_ref" ? [1] : []
    content {
      # mesh_group_choice: no_site_mesh_group (empty variant) vs site_mesh_group (ref variant).
      dynamic "no_site_mesh_group" {
        for_each = var.s2s_slo_arm == "site_mesh_group_empty" ? [1] : []
        content {}
      }

      dynamic "site_mesh_group" {
        for_each = var.s2s_slo_arm == "site_mesh_group_ref" ? [1] : []
        content {
          name      = var.site_mesh_group_ref_name
          namespace = var.ref_namespace
        }
      }

      # connection_choice: public IP for the site mesh connection (live-safe empty marker).
      sm_connection_public_ip {}
    }
  }

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

  # S1/S4 enterprise_proxy oneof {custom_proxy | f5_proxy}, distinct from the no_forward_proxy oneof
  # set above. custom_proxy exposes the proxy_port `Between(0, 65535)` and proxy_ip_address
  # `IPv4Validator()` leaves; it renders only when proxy_arm=custom_proxy (default) AND extended_arms
  # is true (custom_proxy 400s live on this probe, so a live apply uses extended_arms=false — matching
  # the pre-S4 base). f5_proxy is an empty marker and S4a live.
  dynamic "custom_proxy" {
    for_each = var.proxy_arm == "custom_proxy" && var.extended_arms ? [1] : []
    content {
      proxy_ip_address = var.proxy_ip_address
      proxy_port       = var.proxy_port
    }
  }

  dynamic "f5_proxy" {
    for_each = var.proxy_arm == "f5_proxy" ? [1] : []
    content {}
  }
}

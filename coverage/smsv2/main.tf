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
        type     = "Control"

        interface_list {
          name     = "eth0"
          mtu      = var.mtu
          priority = var.priority

          ethernet_interface {
            device = "eth0"
          }

          network_option {
            site_local_network {}
          }

          dhcp_client {}
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

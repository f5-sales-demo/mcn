# Single-node Secure Mesh v2 CE site with an EXPLICIT eth0/SLO interface. The
# explicit interface is what makes XC auto-create the network_interface object
# (var.interface_name) that the BGP peer binds to — without it a standalone bgp
# object is accepted but never renders to FRR (see xcsh #1207).
resource "xcsh_securemesh_site_v2" "this" {
  name        = var.site_name
  namespace   = "system"
  description = "MCN CE-HA (BGP/ECMP) single-node SMSv2 site ${var.site_name} — explicit eth0 SLO interface for BGP peer binding."
  labels      = var.labels

  azure {
    not_managed {
      node_list {
        hostname  = var.hostname
        type      = "Control"
        public_ip = ""

        interface_list {
          name = "eth0"

          ethernet_interface {
            device = "eth0"
            mac    = var.mgmt_nic_mac
          }

          # Site Local Outside (SLO) — required on every site; BGP peers from here.
          network_option {
            site_local_network {}
          }

          dhcp_client {}
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
}

# One bgp object per CE site: eBGP from the CE (ASN var.ce_asn) to the Azure
# Route Server (ASN var.rs_asn), one external peer per Route Server virtual
# router IP, each bound to the explicit SLO interface.
#
# KNOWN BLOCKER (provider bug — tracked under epic xcsh #1207 alongside the
# #1205/#1206 token/approval gaps): the provider caps EVERY object-ref name at
# stringvalidator.LengthBetween(1, 63) (see terraform-provider-xcsh
# internal/provider/bgp_resource.go). The interface object XC auto-generates for
# the explicit SLO interface is 71 chars
# (ves-io-securemesh-site-v2-<site>-network-<hostname>-eth0-0), which the API
# accepts (see AS-BUILT.md §3.2 / the live bgp JSON) but the provider rejects at
# plan/apply time. No naming choice inside the mandated scheme fits (even minimal
# names land at ~65), so the pure-Terraform BGP binding cannot apply until the
# provider validator is relaxed. enable_bgp defaults true (faithful intent); the
# plan tests set it false to work around the provider bug, and a dedicated bgp
# test verifies the HCL/schema wiring with a shortened interface name.
resource "xcsh_bgp" "this" {
  count = var.enable_bgp ? 1 : 0

  name        = "${var.site_name}-bgp"
  namespace   = "system"
  description = "CE ${var.site_name} BGP to Azure Route Server via explicit SLO interface."

  where {
    site {
      ref {
        namespace = "system"
        name      = xcsh_securemesh_site_v2.this.name
      }
      network_type = "VIRTUAL_NETWORK_SITE_LOCAL"
      disable_internet_vip {}
    }
  }

  bgp_parameters {
    asn = var.ce_asn
    # local_address {} = derive the BGP router ID from the interface's local
    # address (the JSON's BGP_ROUTER_ID_FROM_INTERFACE; there is no separate
    # bgp_router_id_type attribute in the provider schema).
    local_address {}
  }

  # Iterate over a plan-KNOWN peer count (rs_peer_count) and index into
  # rs_peer_ips. The IP values may be unknown until the Route Server is applied,
  # but the number of peers is fixed, so the block expands cleanly at plan time.
  dynamic "peers" {
    for_each = { for i in range(var.rs_peer_count) : "azure-rrs-${i + 1}" => i }
    content {
      metadata {
        name = peers.key
      }

      external {
        asn     = var.rs_asn
        address = var.rs_peer_ips[peers.value]
        port    = var.peer_port

        interface {
          namespace = "system"
          name      = var.interface_name
        }

        disable_v6 {}
      }

      passive_mode_disabled {}
      bfd_disabled {}
    }
  }
}

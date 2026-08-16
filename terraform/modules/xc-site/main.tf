# Single-node Secure Mesh v2 CE site with an explicit eth0/SLO interface. The
# site exists before the VM so Terraform can request its one-time node cloud-init.
resource "xcsh_securemesh_site_v2" "this" {
  name        = var.site_name
  namespace   = "system"
  description = "MCN CE-HA (BGP/ECMP) single-node SMSv2 site ${var.site_name} — explicit eth0 SLO interface for BGP peer binding."
  labels      = length(var.labels) > 0 ? var.labels : null

  admin_user_credentials {
    ssh_key = var.ssh_public_key
    admin_password {
      clear_secret_info {
        url = "string:///${base64encode(var.admin_password)}"
      }
    }
  }

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
    perf_mode_l7_enhanced {
      # Provider v3.80.0 gave perf_mode_l7_enhanced a {jumbo_disabled | jumbo_enabled}
      # sub-oneof. F5 materialises jumbo_disabled server-side, so leaving both members
      # undeclared makes the site land and then re-plan the marker as a removal on
      # every subsequent plan — it never reaches 0 changes. Declaring the server
      # default explicitly is what settles it (same fix coverage/smsv2 took in #625).
      jumbo_disabled {}
    }
  }

  re_select {
    geo_proximity {}
  }

  # CE software and OS selection is create-time configuration. The node always
  # installs a destination build on first boot; an empty variable arms the
  # default_* marker and means "install the newest version the server advertises."
  # That is the deployment policy, not an accidental omission. The clean
  # 2026-08-03 rebuild selected the advertised pair on all three 64 GB nodes and
  # brought all three sites ONLINE. Issue #714 separately proves why the disk
  # default carries headroom: the same pair failed on the marketplace image's
  # 31 GiB disk and installed at every tested size from 33 GB upwards.
  #
  # Terraform cannot update these fields after creation: PUT is rejected when
  # pinning forward, pinning backward, or clearing a pin. The platform can perform
  # an in-place change through the site upgrade_sw and upgrade_os actions, but the
  # provider cannot drive those actions yet (xcsh#1390). Set a concrete value only
  # when deliberately reproducing an older build.
  software_settings {
    os {
      dynamic "default_os_version" {
        for_each = var.os_version == "" ? [1] : []
        content {}
      }
      operating_system_version = var.os_version == "" ? null : var.os_version
    }
    sw {
      dynamic "default_sw_version" {
        for_each = var.sw_version == "" ? [1] : []
        content {}
      }
      volterra_software_version = var.sw_version == "" ? null : var.sw_version
    }
  }

}

# One bgp object per CE site: eBGP from the CE (ASN var.ce_asn) to the Azure
# Route Server (ASN var.rs_asn), one external peer per Route Server virtual
# router IP, each bound to the explicit SLO interface.
#
# var.interface_name is the deterministic object name F5 Distributed Cloud assigns
# to the explicit SLO interface. The BGP object can be created before the node is
# online and converges when that interface becomes available.
resource "xcsh_bgp" "this" {
  count = var.enable_bgp ? 1 : 0

  name        = "${var.site_name}-bgp"
  namespace   = "system"
  description = "CE ${var.site_name} BGP to Azure Route Server via explicit SLO interface."

  where {
    site {
      ref {
        namespace = "system"
        name      = var.site_name
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
        address = try(var.rs_peer_ips[peers.value], "")
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

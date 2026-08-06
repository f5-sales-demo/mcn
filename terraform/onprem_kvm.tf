# On-Prem KVM SecureMesh Site v2
resource "xcsh_securemesh_site_v2" "onprem_kvm" {
  name        = "onprem-kvm-site"
  namespace   = "system"
  description = "On-Prem KVM SecureMesh Site v2"

  baremetal {
    not_managed {
      node_list {
        hostname  = "onprem-ce01"
        type      = "Control"
        public_ip = ""

        interface_list {
          name = "eth0"

          ethernet_interface {
            device = "eth0"
          }

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
      jumbo_disabled {}
    }
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

# eBGP Peering configuration for On-Prem KVM Site
resource "xcsh_bgp" "onprem_ebgp" {
  name      = "onprem-kvm-ebgp"
  namespace = "system"

  where {
    site {
      network_type = "VIRTUAL_NETWORK_SITE_LOCAL"
      ref {
        name      = xcsh_securemesh_site_v2.onprem_kvm.name
        namespace = "system"
      }
      disable_internet_vip {}
    }
  }

  bgp_parameters {
    asn = 64512
    local_address {}
  }

  peers {
    metadata {
      name = "peer-router"
    }
    external {
      asn     = 65515
      address = "10.100.0.1"
      port    = 179

      interface {
        name      = "ves-io-securemesh-site-v2-onprem-kvm-site-network-onprem-ce01-eth0-0"
        namespace = "system"
      }

      disable_v6 {}
    }
    passive_mode_disabled {}
    bfd_disabled {}
  }
}

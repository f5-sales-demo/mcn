# On-Prem KVM SecureMesh Site v2
resource "xcsh_securemesh_site_v2" "onprem_kvm" {
  name        = "onprem-kvm-site"
  namespace   = "system"
  description = "On-Prem KVM SecureMesh Site v2"

  azure {
    not_managed {}
  }

  disable_ha {}
  block_all_services {}
  no_network_policy {}
  no_forward_proxy {}
  f5_proxy {}
  no_proxy_bypass {}
  logs_streaming_disabled {}
  no_s2s_connectivity_sli {}
  no_s2s_connectivity_slo {}
  disable_url_categorization {}
  disable_management_network {}
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
        name      = "eth0"
        namespace = "system"
      }

      disable_v6 {}
    }
    passive_mode_disabled {}
    bfd_disabled {}
  }
}

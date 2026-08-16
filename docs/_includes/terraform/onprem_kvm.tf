# The F5 site is KVM, not Azure: this is a single-node KVM site paired with the
# FRR container on the local libvirt segment.
resource "random_password" "site_console_admin_kvm" {
  count = var.enable_kvm ? 1 : 0

  length           = 32
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  min_upper        = 1
  override_special = "!#%*+-=?@^_~"
}

resource "xcsh_securemesh_site_v2" "kvm" {
  count       = var.enable_kvm ? 1 : 0
  name        = "${var.component}-kvm-site"
  namespace   = "system"
  description = "KVM single-node Customer Edge showcase"

  admin_user_credentials {
    ssh_key = local.ssh_public_key
    admin_password {
      clear_secret_info {
        url = "string:///${base64encode(random_password.site_console_admin_kvm[0].result)}"
      }
    }
  }

  kvm {
    not_managed {
      node_list {
        hostname  = var.kvm_domain_name
        type      = "Control"
        public_ip = ""

        interface_list {
          name = "eth0"
          ethernet_interface {
            device = "eth0"
            mac    = local.kvm_ce_mac_address
          }
          network_option {
            site_local_network {}
          }
          dhcp_client {}
        }
      }
    }
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

resource "xcsh_bgp" "kvm" {
  count     = var.enable_kvm ? 1 : 0
  name      = "${var.component}-kvm-bgp"
  namespace = "system"
  where {
    site {
      network_type = "VIRTUAL_NETWORK_SITE_LOCAL"
      ref {
        name      = xcsh_securemesh_site_v2.kvm[0].name
        namespace = "system"
      }
      disable_internet_vip {}
    }
  }
  bgp_parameters {
    asn = var.kvm_ce_asn
    local_address {}
  }
  peers {
    metadata { name = "kvm-frr" }
    external {
      asn     = var.kvm_frr_asn
      address = var.kvm_frr_address
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

resource "xcsh_virtual_site" "kvm" {
  count     = var.enable_kvm ? 1 : 0
  name      = "${var.component}-kvm-vsite"
  namespace = data.xcsh_namespace.mcn.name
  site_type = "CUSTOMER_EDGE"
  site_selector { expressions = ["ves.io/siteName in (${xcsh_securemesh_site_v2.kvm[0].name})"] }
}

resource "xcsh_origin_pool" "kvm" {
  count       = var.enable_kvm ? 1 : 0
  name        = "${var.component}-kvm-pool"
  namespace   = data.xcsh_namespace.mcn.name
  description = "KVM Customer Edge showcase origin pool"
  port        = var.origin_port
  origin_servers {
    labels = {}
    public_ip { ip = var.origin_ip }
  }
  no_tls {}
  loadbalancer_algorithm = "ROUND_ROBIN"
  endpoint_selection     = "DISTRIBUTED"
}

resource "xcsh_http_loadbalancer" "kvm" {
  count     = var.enable_kvm ? 1 : 0
  name      = "${var.component}-kvm-lb"
  namespace = data.xcsh_namespace.mcn.name
  domains   = [var.kvm_lb_domain]
  http { port = 80 }
  advertise_custom {
    advertise_where {
      virtual_site_with_vip {
        ip      = var.kvm_vip
        network = "SITE_NETWORK_SPECIFIED_VIP_OUTSIDE"
        virtual_site {
          name      = xcsh_virtual_site.kvm[0].name
          namespace = data.xcsh_namespace.mcn.name
        }
      }
      use_default_port {}
    }
  }
  default_route_pools {
    pool {
      name      = xcsh_origin_pool.kvm[0].name
      namespace = data.xcsh_namespace.mcn.name
    }
    weight   = 1
    priority = 1
  }
  round_robin {}
  no_challenge {}
  user_id_client_ip {}
  disable_waf {}
  disable_rate_limit {}
  disable_api_discovery {}
  disable_api_testing {}
  disable_api_definition {}
  l7_ddos_protection {}
}

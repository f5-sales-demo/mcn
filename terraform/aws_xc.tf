# Independent AWS Secure Mesh sites and their BGP sessions. AWS Route Server
# peers with each EC2 SLO address; the F5 object records the matching session.
resource "random_password" "site_console_admin_aws" {
  for_each = local.aws_sites

  length           = 32
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  min_upper        = 1
  override_special = "!#%*+-=?@^_~"
}

resource "xcsh_securemesh_site_v2" "aws" {
  for_each    = local.aws_sites
  name        = each.value.site_name
  namespace   = "system"
  description = "AWS single-node Customer Edge ${each.key}"

  admin_user_credentials {
    ssh_key = local.ssh_public_key
    admin_password {
      clear_secret_info {
        url = "string:///${base64encode(random_password.site_console_admin_aws[each.key].result)}"
      }
    }
  }

  aws {
    not_managed {
      node_list {
        hostname  = each.value.site_name
        type      = "Control"
        public_ip = aws_eip.ce[each.key].public_ip

        interface_list {
          name = "eth0"
          ethernet_interface {
            device = "eth0"
            mac    = aws_network_interface.slo[each.key].mac_address
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

resource "xcsh_bgp" "aws" {
  for_each  = local.aws_sites
  name      = "${each.value.site_name}-bgp"
  namespace = "system"
  where {
    site {
      network_type = "VIRTUAL_NETWORK_SITE_LOCAL"
      ref {
        name      = xcsh_securemesh_site_v2.aws[each.key].name
        namespace = "system"
      }
      disable_internet_vip {}
    }
  }
  bgp_parameters {
    asn = var.aws_ce_asn
    local_address {}
  }
  peers {
    metadata { name = "aws-route-server-${each.key}" }
    external {
      asn     = var.aws_route_server_asn
      address = aws_vpc_route_server_endpoint.aws[each.value.index % 2].eni_address
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

resource "xcsh_virtual_site" "aws" {
  count     = var.enable_aws ? 1 : 0
  name      = "${var.component}-aws-vsite"
  namespace = data.xcsh_namespace.mcn.name
  site_type = "CUSTOMER_EDGE"
  site_selector { expressions = ["ves.io/siteName in (${join(", ", [for site in values(local.aws_sites) : site.site_name])})"] }
}

resource "xcsh_origin_pool" "aws" {
  count       = var.enable_aws ? 1 : 0
  name        = "${var.component}-aws-pool"
  namespace   = data.xcsh_namespace.mcn.name
  description = "AWS Route Server showcase origin pool"
  port        = var.origin_port
  origin_servers {
    labels = {}
    public_ip { ip = var.origin_ip }
  }
  no_tls {}
  loadbalancer_algorithm = "ROUND_ROBIN"
  endpoint_selection     = "DISTRIBUTED"
}

resource "xcsh_http_loadbalancer" "aws" {
  count     = var.enable_aws ? 1 : 0
  name      = "${var.component}-aws-lb"
  namespace = data.xcsh_namespace.mcn.name
  domains   = [var.aws_lb_domain]
  http { port = 80 }
  advertise_custom {
    advertise_where {
      virtual_site_with_vip {
        ip      = var.aws_vip
        network = "SITE_NETWORK_SPECIFIED_VIP_OUTSIDE"
        virtual_site {
          name      = xcsh_virtual_site.aws[0].name
          namespace = data.xcsh_namespace.mcn.name
        }
      }
      use_default_port {}
    }
  }
  default_route_pools {
    pool {
      name      = xcsh_origin_pool.aws[0].name
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

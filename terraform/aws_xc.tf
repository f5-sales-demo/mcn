# ---------------------------------------------------------
# F5 XC SecureMesh v2 Site, BGP, Virtual Site, Origin Pool & LB for AWS
# ---------------------------------------------------------

resource "xcsh_securemesh_site_v2" "aws" {
  count       = var.enable_aws ? 1 : 0
  name        = "aws-site"
  namespace   = "system"
  description = "AWS Customer Edge SecureMesh Site v2"

  aws {
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

resource "xcsh_bgp" "aws_ebgp" {
  count     = var.enable_aws ? 1 : 0
  name      = "${var.component}-aws-ebgp"
  namespace = "system"

  where {
    site {
      network_type = "VIRTUAL_NETWORK_SITE_LOCAL"
      ref {
        name      = xcsh_securemesh_site_v2.aws[0].name
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
      name = "peer-aws-router"
    }
    external {
      asn     = 65515
      address = cidrhost(var.aws_vpc_cidr, 1)
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
  site_selector {
    expressions = ["ves.io/siteName in (aws-site)"]
  }
}

resource "xcsh_origin_pool" "aws" {
  count       = var.enable_aws ? 1 : 0
  name        = "${var.component}-aws-pool"
  namespace   = data.xcsh_namespace.mcn.name
  description = "AWS origin pool serving MCN CE-HA demo"

  port = var.origin_port

  origin_servers {
    labels {}
    public_ip {
      ip = var.origin_ip
    }
  }

  no_tls {}
  loadbalancer_algorithm = "ROUND_ROBIN"
  endpoint_selection     = "DISTRIBUTED"
}

resource "xcsh_http_loadbalancer" "aws" {
  count     = var.enable_aws ? 1 : 0
  name      = "${var.component}-aws-lb"
  namespace = data.xcsh_namespace.mcn.name

  domains = [var.aws_lb_domain]

  http {
    port = 80
  }

  advertise_custom {
    advertise_where {
      virtual_site {
        network = "SITE_NETWORK_INSIDE_AND_OUTSIDE"
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

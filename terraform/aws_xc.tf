# ---------------------------------------------------------
# F5 XC SecureMesh v2 Site, Virtual Site, Origin Pool & LB for AWS
# ---------------------------------------------------------

locals {
  aws_ce_hostnames = [
    for index in range(var.enable_aws ? var.aws_ce_count : 0) :
    "${var.component}-aws-ce-${index + 1}"
  ]
}

resource "xcsh_securemesh_site_v2" "aws" {
  count       = var.enable_aws ? 1 : 0
  name        = "aws-site"
  namespace   = "system"
  description = "AWS Customer Edge SecureMesh Site v2"

  aws {
    not_managed {
      dynamic "node_list" {
        for_each = { for index in range(var.aws_ce_count) : tostring(index) => index }
        content {
          hostname  = local.aws_ce_hostnames[node_list.value]
          type      = "Control"
          public_ip = null

          interface_list {
            name = "slo"
            mtu  = var.aws_smsv2_interface_mtu
            ethernet_interface {
              device = "eth0"
              mac    = aws_network_interface.slo[node_list.value].mac_address
            }
            network_option {
              site_local_network {}
            }
            dhcp_client {}
          }

          interface_list {
            name = "sli"
            mtu  = var.aws_smsv2_interface_mtu
            ethernet_interface {
              device = "eth1"
              mac    = aws_network_interface.sli[node_list.value].mac_address
            }
            network_option {
              site_local_inside_network {}
            }
            dhcp_client {}
          }
        }
      }
    }
  }

  enable_ha {}
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

  lifecycle {
    replace_triggered_by = [terraform_data.aws_ce_instances]
  }
}

# Runtime registrations exist only after each appliance boots. This lookup is
# intentionally independent of the site resource so an initial plan reports
# found=false and a later convergence pass can approve all registered nodes.
data "xcsh_site_registration" "aws" {
  for_each = {
    for index, hostname in local.aws_ce_hostnames : tostring(index) => hostname
  }

  site_name = "aws-site"
  hostname  = each.value
  namespace = "system"
}

resource "xcsh_registration_approval" "aws" {
  for_each = {
    for key, registration in data.xcsh_site_registration.aws :
    key => registration if registration.found
  }

  namespace    = "system"
  name         = each.value.name
  cluster_size = var.aws_ce_count
  state        = "APPROVED"
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
    labels = {}
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

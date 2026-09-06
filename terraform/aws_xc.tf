# ---------------------------------------------------------
# Three independent F5 XC SecureMesh v2 sites and AWS VIP
# ---------------------------------------------------------

locals {
  aws_sites = {
    for index in range(var.enable_aws ? var.aws_ce_count : 0) :
    format("%02d", index + 1) => {
      index    = index
      name     = format("%s-aws-%s-%02d", var.component, var.aws_location, index + 1)
      hostname = format("%s-aws-%s-%02d", var.component, var.aws_location, index + 1)
    }
  }
  # Bootstrap keys are cumulative during controlled replacement: 01, then
  # 01+02, then all three. The default remains the complete topology.
  aws_bootstrap_sites = {
    for key, site in local.aws_sites : key => site
    if contains(var.aws_bootstrap_site_keys, key)
  }
  aws_ce_hostnames = [for site in values(local.aws_sites) : site.hostname]
}

resource "xcsh_token" "aws" {
  for_each = local.aws_bootstrap_sites

  name        = "${each.value.name}-registration"
  namespace   = "system"
  description = "Registration token for independent AWS site ${each.value.name}"
  type        = 1
  site_name   = each.value.name
}

resource "xcsh_securemesh_site_v2" "aws" {
  for_each    = local.aws_sites
  name        = each.value.name
  namespace   = "system"
  description = "Independent AWS Customer Edge SecureMesh v2 site ${each.key}"

  aws {
    not_managed {
      node_list {
        hostname  = each.value.hostname
        type      = "Control"
        public_ip = null

        interface_list {
          name = "slo"
          mtu  = var.aws_smsv2_interface_mtu
          ethernet_interface {
            device = try(var.aws_smsv2_devices[each.key].slo, null)
            mac    = aws_network_interface.slo[each.value.index].mac_address
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
            device = try(var.aws_smsv2_devices[each.key].sli, null)
            mac    = aws_network_interface.sli[each.value.index].mac_address
          }
          network_option {
            site_local_inside_network {}
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

  software_settings {
    os {
      operating_system_version = var.aws_baseline_os_version
    }
    sw {
      volterra_software_version = var.aws_baseline_software_version
    }
  }
}

resource "xcsh_site_cloud_init" "aws" {
  # Cloud-init records remain stable for all sites. Only the sensitive JWT
  # issuance is staged, so a CE01 replacement cannot delete peer bootstrap
  # records from state or the XC API.
  for_each                  = local.aws_sites
  provider_ref              = "aws"
  site_name                 = xcsh_securemesh_site_v2.aws[each.key].name
  enable_management_network = false
}

data "xcsh_site_registration" "aws" {
  for_each = local.aws_sites

  site_name = each.value.name
  hostname  = each.value.hostname
  namespace = "system"

}

resource "xcsh_registration_approval" "aws" {
  for_each = {
    for key, registration in data.xcsh_site_registration.aws :
    key => registration if registration.found
  }

  namespace    = "system"
  name         = each.value.name
  cluster_size = 1
  state        = "APPROVED"
}

resource "xcsh_virtual_site" "aws" {
  count     = var.enable_aws ? 1 : 0
  name      = "${var.component}-aws-vsite"
  namespace = data.xcsh_namespace.mcn.name

  site_type = "CUSTOMER_EDGE"
  site_selector {
    expressions = [format("ves.io/siteName in (%s)", join(",", [for site in values(local.aws_sites) : site.name]))]
  }
}

resource "xcsh_origin_pool" "aws" {
  count       = var.enable_aws ? 1 : 0
  name        = "${var.component}-aws-pool"
  namespace   = data.xcsh_namespace.mcn.name
  description = "AWS origin pool serving the three-site TGW showcase"
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
        network = "SITE_NETWORK_SPECIFIED_VIP_INSIDE"
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

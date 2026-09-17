# ---------------------------------------------------------
# Three independent F5 XC SecureMesh v2 sites and AWS VIP
# ---------------------------------------------------------

locals {
  aws_sites = {
    for index in range(var.enable_aws ? var.aws_ce_count : 0) :
    format("%02d", index + 1) => {
      index       = index
      name        = format("%s-aws-%s-%02d", local.site_prefix, var.aws_location, index + 1)
      hostname    = format("%s-aws-%s-%02d", local.site_prefix, var.aws_location, index + 1)
      listener_ip = cidrhost(cidrsubnet(var.aws_vpc_cidr, 8, index + 11), 10)
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

# Discovery sites intentionally omit node_list. The F5 API then records the
# booted guest hardware inventory, including the authoritative device-name/MAC
# pairs. A later configured plan MAC-joins that inventory; it never guesses a
# Linux NIC name from AWS attachment order.
data "xcsh_site_registrations_by_site" "aws" {
  for_each = var.enable_aws && var.aws_site_configuration_phase == "configured" ? local.aws_sites : {}

  namespace = "system"
  site_name = each.value.name
}

locals {
  aws_discovered_networks = {
    for key, registration in data.xcsh_site_registrations_by_site.aws :
    key => flatten([
      for item in registration.items : try(item.get_spec.infra.hw_info.network, [])
    ])
  }
  # Preserve each full matching record so the configured phase can reject a
  # missing or ambiguous inventory rather than silently submitting a null or
  # guessed device value.
  aws_discovered_device_candidates = {
    for key, site in local.aws_sites : key => {
      slo = [
        for network in try(local.aws_discovered_networks[key], []) : network
        if try(lower(network.mac_address), "") == lower(aws_network_interface.slo[site.index].mac_address)
      ]
      sli = [
        for network in try(local.aws_discovered_networks[key], []) : network
        if try(lower(network.mac_address), "") == lower(aws_network_interface.sli[site.index].mac_address)
      ]
    }
  }
  aws_discovered_devices = {
    for key, site in local.aws_sites : key => {
      slo = try(trimspace(one(local.aws_discovered_device_candidates[key].slo).name), null)
      sli = try(trimspace(one(local.aws_discovered_device_candidates[key].sli).name), null)
    }
  }
}

resource "xcsh_token" "aws" {
  for_each = local.aws_bootstrap_sites

  name        = "${each.value.name}-registration"
  namespace   = "system"
  description = "Registration token for independent AWS site ${each.value.name}"
  labels      = local.xc_labels
  type        = 1
  site_name   = xcsh_securemesh_site_v2.aws[each.key].name
}

resource "xcsh_securemesh_site_v2" "aws" {
  for_each    = local.aws_sites
  name        = each.value.name
  namespace   = "system"
  description = "Independent AWS Customer Edge SecureMesh v2 site ${each.key}"
  labels      = local.xc_labels

  aws {
    not_managed {
      dynamic "node_list" {
        for_each = var.aws_site_configuration_phase == "configured" ? [each.value] : []

        content {
          hostname  = node_list.value.hostname
          type      = "Control"
          public_ip = null

          interface_list {
            name = "slo"
            mtu  = var.aws_smsv2_interface_mtu
            ethernet_interface {
              device = local.aws_discovered_devices[each.key].slo
              mac    = aws_network_interface.slo[node_list.value.index].mac_address
            }
            network_option {
              site_local_network = {}
            }
            dhcp_client = {}
          }

          interface_list {
            name = "sli"
            mtu  = var.aws_smsv2_interface_mtu
            ethernet_interface {
              device = local.aws_discovered_devices[each.key].sli
              mac    = aws_network_interface.sli[node_list.value.index].mac_address
            }
            network_option {
              site_local_inside_network = {}
            }
            dhcp_client = {}
          }
        }
      }
    }
  }

  disable_ha                 = {}
  block_all_services         = {}
  no_network_policy          = {}
  no_forward_proxy           = {}
  f5_proxy                   = {}
  no_proxy_bypass            = {}
  logs_streaming_disabled    = {}
  no_s2s_connectivity_sli    = {}
  no_s2s_connectivity_slo    = {}
  disable_url_categorization = {}
  disable_management_network = {}

  local_vrf {
    default_config     = {}
    default_sli_config = {}
  }

  software_settings {
    # First boot must request the field-proven runtime pair.  A staged
    # baseline leaves a newly created CE in UPGRADE_IN_PROGRESS before the
    # post-bootstrap action stage can observe or recover it.
    os {
      operating_system_version = var.aws_os_version
    }
    sw {
      volterra_software_version = var.aws_software_version
    }
  }

  lifecycle {
    precondition {
      condition = var.aws_site_configuration_phase == "discovery" || (
        length(local.aws_discovered_device_candidates[each.key].slo) == 1 &&
        length(local.aws_discovered_device_candidates[each.key].sli) == 1 &&
        try(length(local.aws_discovered_devices[each.key].slo), 0) > 0 &&
        try(length(local.aws_discovered_devices[each.key].sli), 0) > 0 &&
        local.aws_discovered_devices[each.key].slo != local.aws_discovered_devices[each.key].sli
      )
      error_message = "Configured AWS SMSv2 requires exactly one nonempty registered hardware device for each Terraform-owned SLO/SLI ENI MAC, with distinct devices. Run and apply the discovery phase, wait for registration inventory, then retry; do not guess guest device names."
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
    key => registration if registration.found && registration.state == "NEW"
  }

  namespace    = "system"
  name         = each.value.name
  cluster_size = 1
  state        = "APPROVED"

  depends_on = [xcsh_securemesh_site_v2.aws]
}

resource "xcsh_virtual_site" "aws" {
  count     = var.enable_aws ? 1 : 0
  name      = "${local.aws_resource_prefix}-aws-vsite"
  namespace = data.xcsh_namespace.mcn.name
  labels    = local.xc_labels

  site_type = "CUSTOMER_EDGE"
  site_selector {
    expressions = ["mcn-topology in (${local.site_prefix}-aws)"]
  }
}

resource "xcsh_origin_pool" "aws" {
  count       = var.enable_aws ? 1 : 0
  name        = "${local.aws_resource_prefix}-aws-pool"
  namespace   = data.xcsh_namespace.mcn.name
  description = "AWS origin pool serving the three-site TGW showcase"
  labels      = local.xc_labels
  port        = var.origin_port

  origin_servers {
    labels = {}
    public_name { dns_name = var.aws_origin_dns_name }
  }

  no_tls                 = {}
  loadbalancer_algorithm = "ROUND_ROBIN"
  endpoint_selection     = "DISTRIBUTED"

}

resource "xcsh_http_loadbalancer" "aws" {
  count     = var.enable_aws ? 1 : 0
  name      = "${local.aws_resource_prefix}-aws-lb"
  namespace = data.xcsh_namespace.mcn.name
  domains   = [var.aws_lb_domain]
  labels    = local.xc_labels

  http {
    port = 80
  }

  advertise_custom {
    dynamic "advertise_where" {
      for_each = local.aws_sites
      content {
        site {
          network = "SITE_NETWORK_INSIDE"
          site {
            name      = xcsh_securemesh_site_v2.aws[advertise_where.key].name
            namespace = "system"
          }
        }
        use_default_port = {}
      }
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

  round_robin            = {}
  no_challenge           = {}
  user_id_client_ip      = {}
  disable_waf            = {}
  disable_rate_limit     = {}
  disable_api_discovery  = {}
  disable_api_testing    = {}
  disable_api_definition = {}
  l7_ddos_protection {}
}

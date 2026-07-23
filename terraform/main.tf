# MCN CE-HA (BGP/ECMP) — top-level wiring.
#
# N single-node Secure Mesh v2 CE sites, each originating the LB VIP 10.250.0.10/32
# via eBGP (ASN 64512) to Azure Route Server (ASN 65515). Equal-cost advertisements
# from multiple CEs program ECMP (active/active) into the hub VNet.
#
# Deploy-time ordering (see AS-BUILT.md §5.4): Azure (VNet/subnets/RS/NICs/VMs) ->
# XC site (explicit interface) -> token -> CE cloud-init boot -> MANUAL console
# approval -> CE ONLINE -> xcsh_bgp + RS bgpConnection -> LB advertise. The bgp/LB
# objects can be applied before ONLINE; they converge once the CE is up.

# Guard: the HA VIP MUST be outside every VNet CIDR, or Azure prefers the VNet
# system route over the more-specific BGP /32. Masks the VIP to each CIDR's prefix
# length and compares network addresses (a correct containment test for any prefix).
check "vip_outside_vnet_cidrs" {
  assert {
    condition     = cidrhost(var.hub_cidr, 0) != cidrhost("${var.vip}/${split("/", var.hub_cidr)[1]}", 0)
    error_message = "vip ${var.vip} must be OUTSIDE hub_cidr ${var.hub_cidr}."
  }
  assert {
    condition     = cidrhost(var.spoke_cidr, 0) != cidrhost("${var.vip}/${split("/", var.spoke_cidr)[1]}", 0)
    error_message = "vip ${var.vip} must be OUTSIDE spoke_cidr ${var.spoke_cidr}."
  }
}

# Tenant-scoped, reusable site registration token. The provider now ships
# xcsh_token with a Computed `uid` (system_metadata.uid) — the token VALUE a CE
# feeds to VPM at registration (the resource `id` is the token NAME, not the
# value). The spec is empty; only metadata is needed and namespace defaults to
# system. This replaces the manual var.registration_token prerequisite (#1205);
# registration approval remains console-only (deferred, #1206 / #1210).
resource "xcsh_token" "ce" {
  name        = "mcn-ce-registration"
  namespace   = "system"
  description = "MCN CE-HA registration token (tenant-scoped, reusable across CE sites)"
}

# Pure expansion of ce_count into the per-CE node map (hostname, site_name,
# slo_ip, az, interface_name). Drives every for_each below.
module "ce_topology" {
  source = "./modules/ce-topology"

  ce_count           = var.ce_count
  region_short       = var.region_short
  mgmt_subnet_prefix = var.mgmt_subnet_prefix
}

# Hub: RG, VNet, four subnets, Azure Route Server.
module "azure_hub" {
  source = "./modules/azure-hub"

  resource_group_name        = var.resource_group_name
  location                   = var.location
  hub_cidr                   = var.hub_cidr
  mgmt_subnet_prefix         = var.mgmt_subnet_prefix
  external_subnet_prefix     = var.external_subnet_prefix
  internal_subnet_prefix     = var.internal_subnet_prefix
  route_server_subnet_prefix = var.route_server_subnet_prefix
  route_server_name          = var.route_server_name
  tags                       = local.tags
}

# One CE VM (3 NICs + identity) per node.
module "ce_node" {
  source   = "./modules/ce-node"
  for_each = module.ce_topology.ce_nodes

  hostname            = each.value.hostname
  resource_group_name = module.azure_hub.resource_group_name
  location            = module.azure_hub.location
  zone                = each.value.az
  vm_size             = var.ce_vm_size
  mgmt_subnet_id      = module.azure_hub.management_subnet_id
  external_subnet_id  = module.azure_hub.external_subnet_id
  internal_subnet_id  = module.azure_hub.internal_subnet_id
  mgmt_private_ip     = each.value.slo_ip
  admin_username      = var.admin_username
  ssh_public_key      = local.ssh_public_key

  custom_data = base64encode(templatefile("${path.module}/cloud-init/ce-node.yaml", {
    cluster_name = each.value.site_name
    token        = local.ce_registration_token
  }))

  tags = local.tags
}

# One XC SMSv2 site + bgp object per node. The MAC is wired from the mgmt NIC so
# a NIC recreate updates the site binding automatically.
module "xc_site" {
  source   = "./modules/xc-site"
  for_each = module.ce_topology.ce_nodes

  site_name      = each.value.site_name
  hostname       = each.value.hostname
  interface_name = each.value.interface_name
  mgmt_nic_mac   = module.ce_node[each.key].mgmt_nic_mac
  rs_peer_ips    = module.azure_hub.rs_peer_ips
  ce_asn         = var.ce_asn
  rs_asn         = var.rs_asn
  enable_bgp     = var.enable_bgp
}

# The Azure side of each eBGP session (Route Server -> CE eth0/SLO IP).
module "azure_route_server_bgp" {
  source   = "./modules/azure-route-server-bgp"
  for_each = module.ce_topology.ce_nodes

  name            = "${each.key}-bgp"
  route_server_id = module.azure_hub.route_server_id
  peer_asn        = var.ce_asn
  peer_ip         = module.ce_node[each.key].mgmt_private_ip
}

# Test client in snet-hub-internal.
module "client_vm" {
  source = "./modules/client-vm"

  resource_group_name = module.azure_hub.resource_group_name
  location            = module.azure_hub.location
  subnet_id           = module.azure_hub.internal_subnet_id
  admin_username      = var.admin_username
  ssh_public_key      = local.ssh_public_key
  tags                = local.tags
}

# ---------------------------------------------------------
# F5 XC data-plane (app tier)
# ---------------------------------------------------------

resource "xcsh_origin_pool" "this" {
  name        = var.origin_pool_name
  namespace   = var.xc_app_namespace
  description = "MCN reference origin pool -> ${var.origin_ip}:${var.origin_port}"

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

resource "xcsh_http_loadbalancer" "this" {
  name        = var.lb_name
  namespace   = var.xc_app_namespace
  description = "BGP/ECMP HA: custom VIP ${var.vip} advertised from every CE site."

  domains = [var.lb_domain]

  http {
    port                 = 80
    dns_volterra_managed = false
  }

  # Advertise the VIP on the outside network of every CE site.
  advertise_custom {
    dynamic "advertise_where" {
      for_each = module.ce_topology.ce_nodes
      content {
        site {
          network = "SITE_NETWORK_OUTSIDE"
          site {
            namespace = "system"
            name      = advertise_where.value.site_name
          }
          ip = var.vip
        }
        use_default_port {}
      }
    }
  }

  default_route_pools {
    pool {
      namespace = var.xc_app_namespace
      name      = xcsh_origin_pool.this.name
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
  service_policies_from_namespace {}
  disable_trust_client_ip_headers {}
  disable_malicious_user_detection {}
  disable_malware_protection {}
  disable_threat_mesh {}
  default_sensitive_data_policy {}
}

# AWS owns ENI, TGW, Connect, GRE, and inside-CIDR facts. F5 XC owns
# SMSv2 configuration, health, BGP, and route observations.
locals {
  aws_tgw_roles = toset(["slo", "sli"])
  aws_smsv2_api_release_commit = join("", [
    "8a48ca67ad",
    "9fc23174d0",
    "86c0d63a27",
    "83e531044b",
  ])
  aws_smsv2_bindings = merge(
    {
      for index in range(var.enable_aws ? var.aws_ce_count : 0) :
      format("node_%02d_slo", index + 1) => {
        index             = index
        order             = index
        node              = local.aws_ce_hostnames[index]
        role              = "slo"
        payload_role      = "sli"
        mac               = aws_network_interface.slo[index].mac_address
        gre_peer_address  = aws_network_interface.slo[index].private_ip
        inside_cidr_block = cidrsubnet(var.aws_tgw_inside_cidr, 5, index)
      }
    },
    {
      for index in range(var.enable_aws ? var.aws_ce_count : 0) :
      format("node_%02d_sli", index + 1) => {
        index             = index
        order             = var.aws_ce_count + index
        node              = local.aws_ce_hostnames[index]
        role              = "sli"
        payload_role      = "sli"
        mac               = aws_network_interface.sli[index].mac_address
        gre_peer_address  = aws_network_interface.sli[index].private_ip
        inside_cidr_block = cidrsubnet(var.aws_tgw_inside_cidr, 5, var.aws_ce_count + index)
      }
    },
  )
  aws_smsv2_nodes = {
    for key, interface in local.aws_smsv2_bindings : key => {
      node = interface.node
      role = interface.role
      mac  = interface.mac
    }
  }
}

data "xcsh_smsv2_contract" "aws" {
  count = var.enable_aws_tgw_connect ? 1 : 0
}

resource "terraform_data" "aws_tgw_contract_gate" {
  count = var.enable_aws_tgw_connect ? 1 : 0
  input = {
    contract_id         = data.xcsh_smsv2_contract.aws[0].contract_id
    contract_version    = data.xcsh_smsv2_contract.aws[0].contract_version
    api_release_tag     = data.xcsh_smsv2_contract.aws[0].api_release_tag
    api_release_commit  = data.xcsh_smsv2_contract.aws[0].api_release_commit
    telemetry_schema_id = data.xcsh_smsv2_contract.aws[0].telemetry_schema_id
    capabilities        = data.xcsh_smsv2_contract.aws[0].capabilities
    f5xc_authorities    = data.xcsh_smsv2_contract.aws[0].f5xc_authorities
    aws_authorities     = data.xcsh_smsv2_contract.aws[0].aws_authorities
  }

  lifecycle {
    precondition {
      condition     = var.enable_aws
      error_message = "AWS TGW Connect requires enable_aws = true."
    }
    precondition {
      condition     = var.aws_ce_count == 3
      error_message = "AWS TGW Connect requires the validated three-node, six-interface topology."
    }
    precondition {
      condition = (
        data.xcsh_smsv2_contract.aws[0].contract_id == "f5xc-ce-automation/v3" &&
        data.xcsh_smsv2_contract.aws[0].contract_version == "6.0.0" &&
        data.xcsh_smsv2_contract.aws[0].api_release_tag == "v6.0.2" &&
        data.xcsh_smsv2_contract.aws[0].api_release_commit == local.aws_smsv2_api_release_commit &&
        data.xcsh_smsv2_contract.aws[0].telemetry_schema_id == "f5xc-smsv2-aws-tgw-telemetry/v2"
      )
      error_message = "Provider v7.2.0 must expose the exact immutable SMSv2 v3/API v6 contract."
    }
    precondition {
      condition = (
        length(data.xcsh_smsv2_contract.aws[0].capabilities) == 3 &&
        try(data.xcsh_smsv2_contract.aws[0].capabilities["aws_ce_create"], "") == "available" &&
        try(data.xcsh_smsv2_contract.aws[0].capabilities["runtime_status"], "") == "available" &&
        try(data.xcsh_smsv2_contract.aws[0].capabilities["tgw_connect"], "") == "available"
      )
      error_message = "Provider v7.2.0 must publish all and only the required SMSv2 capabilities as available."
    }
    precondition {
      condition = (
        length(data.xcsh_smsv2_contract.aws[0].f5xc_authorities) == 5 &&
        toset(data.xcsh_smsv2_contract.aws[0].f5xc_authorities) == toset([
          "smsv2_configuration", "runtime_health", "bgp_peers", "bgp_routes", "simplified_routes",
        ]) &&
        length(data.xcsh_smsv2_contract.aws[0].aws_authorities) == 6 &&
        toset(data.xcsh_smsv2_contract.aws[0].aws_authorities) == toset([
          "eni", "transit_gateway", "transit_gateway_connect", "gre_endpoints", "bgp_inside_cidrs", "autonomous_system_numbers",
        ])
      )
      error_message = "The SMSv2 contract authority split does not match this deployment."
    }
  }
}

module "aws_tgw_connect" {
  count                      = var.enable_aws && var.enable_aws_tgw_connect ? 1 : 0
  source                     = "./modules/aws-tgw-connect"
  vpc_id                     = aws_vpc.aws[0].id
  amazon_side_asn            = var.aws_tgw_asn
  transit_gateway_cidr_block = var.aws_tgw_gre_cidr
  transport_subnet_ids       = aws_subnet.private_sli[*].id
  name_prefix                = var.component
  depends_on                 = [terraform_data.aws_tgw_contract_gate]
}

data "xcsh_smsv2_aws_runtime" "aws" {
  count                 = var.enable_aws && var.enable_aws_tgw_connect ? 1 : 0
  namespace             = "system"
  site                  = xcsh_securemesh_site_v2.aws[0].name
  nodes                 = local.aws_smsv2_nodes
  timeout_seconds       = var.aws_bgp_convergence_timeout_seconds
  poll_interval_seconds = var.aws_bgp_poll_interval_seconds
  depends_on            = [xcsh_securemesh_site_v2.aws]
}

resource "terraform_data" "aws_tgw_runtime_gate" {
  count = var.enable_aws && var.enable_aws_tgw_connect ? 1 : 0
  input = {
    healthy    = data.xcsh_smsv2_aws_runtime.aws[0].healthy
    interfaces = data.xcsh_smsv2_aws_runtime.aws[0].interfaces
  }
  lifecycle {
    precondition {
      condition = (
        data.xcsh_smsv2_aws_runtime.aws[0].healthy &&
        length(data.xcsh_smsv2_aws_runtime.aws[0].interfaces) == 6 &&
        alltrue([
          for interface in values(data.xcsh_smsv2_aws_runtime.aws[0].interfaces) :
          interface.healthy && interface.mtu == var.aws_smsv2_interface_mtu &&
          contains(["slo", "sli"], interface.role)
        ])
      )
      error_message = "All six MAC-bound SMSv2 interfaces must agree on node/role/MTU and report healthy before AWS Connect peers are created."
    }
  }
}

resource "aws_ec2_transit_gateway_connect_peer" "aws" {
  for_each                      = var.enable_aws && var.enable_aws_tgw_connect ? local.aws_smsv2_bindings : {}
  bgp_asn                       = tostring(var.aws_ce_bgp_asn)
  inside_cidr_blocks            = [each.value.inside_cidr_block]
  peer_address                  = each.value.gre_peer_address
  transit_gateway_address       = cidrhost(var.aws_tgw_gre_cidr, each.value.order + 1)
  transit_gateway_attachment_id = module.aws_tgw_connect[0].connect_attachment_ids[each.value.role]
  tags                          = merge(local.tags, { Name = "${var.component}-aws-tgw-peer-${replace(each.key, "_", "-")}" })
  depends_on                    = [terraform_data.aws_tgw_runtime_gate]
}

resource "xcsh_external_connector" "aws_tgw" {
  for_each    = var.enable_aws && var.enable_aws_tgw_connect ? local.aws_smsv2_bindings : {}
  name        = "${var.component}-aws-tgw-${replace(each.key, "_", "-")}"
  namespace   = "system"
  description = "AWS TGW Connect GRE tunnel for ${each.key}."
  ce_site_reference {
    name      = xcsh_securemesh_site_v2.aws[0].name
    namespace = "system"
  }
  gre {
    gre_parameters {
      dynamic "site_local_network" {
        for_each = each.value.payload_role == "slo" ? [1] : []
        content {}
      }
      dynamic "site_local_inside_network" {
        for_each = each.value.payload_role == "sli" ? [1] : []
        content {}
      }
      # The external-connector API caps GRE MTU at 1370. Preserve a smaller
      # observed underlay ceiling while never constructing an invalid request.
      tunnel_mtu = min(data.xcsh_smsv2_aws_runtime.aws[0].interfaces[each.key].mtu - 24, 1370)
      peer_ip_address {
        addr = aws_ec2_transit_gateway_connect_peer.aws[each.key].transit_gateway_address
      }
      tunnel_eps {
        node             = data.xcsh_smsv2_aws_runtime.aws[0].interfaces[each.key].node
        interface        = data.xcsh_smsv2_aws_runtime.aws[0].interfaces[each.key].interface_name
        local_tunnel_ip  = "${aws_ec2_transit_gateway_connect_peer.aws[each.key].bgp_peer_address}/29"
        remote_tunnel_ip = "${sort(tolist(aws_ec2_transit_gateway_connect_peer.aws[each.key].bgp_transit_gateway_addresses))[0]}/29"
      }
    }
  }
  depends_on = [aws_route_table.public, aws_route_table.private]
}

resource "xcsh_bgp" "aws_tgw" {
  for_each    = var.enable_aws && var.enable_aws_tgw_connect ? local.aws_tgw_roles : toset([])
  name        = "${var.component}-aws-tgw-${each.key}-bgp"
  namespace   = "system"
  description = "AWS TGW Connect BGP for the ${upper(each.key)} interfaces."
  where {
    site {
      # The external-connector API accepts TGW payload only in Site Local
      # Inside, independently of whether GRE transport uses SLO or SLI.
      network_type = "VIRTUAL_NETWORK_SITE_LOCAL_INSIDE"
      ref {
        name      = xcsh_securemesh_site_v2.aws[0].name
        namespace = "system"
      }
      disable_internet_vip {}
    }
  }
  bgp_parameters {
    asn = var.aws_ce_bgp_asn
    local_address {}
  }
  dynamic "peers" {
    for_each = { for key, interface in local.aws_smsv2_bindings : key => interface if interface.role == each.key }
    content {
      metadata { name = replace(peers.key, "_", "-") }
      external {
        asn     = module.aws_tgw_connect[0].amazon_side_asn
        address = sort(tolist(aws_ec2_transit_gateway_connect_peer.aws[peers.key].bgp_transit_gateway_addresses))[0]
        port    = 179
        family_inet {
          enable {}
        }
        interface {
          name      = "ves-io-external-connector-${xcsh_external_connector.aws_tgw[peers.key].name}"
          namespace = "system"
        }
        disable_v6 {}
      }
      passive_mode_disabled {}
      bfd_disabled {}
    }
  }
  depends_on = [xcsh_external_connector.aws_tgw]
}

data "xcsh_site_bgp_status" "aws" {
  count     = var.enable_aws && var.enable_aws_tgw_connect ? 1 : 0
  namespace = "system"
  site      = xcsh_securemesh_site_v2.aws[0].name
  expected_peers = {
    for key, interface in local.aws_smsv2_bindings : key => {
      node            = interface.node
      role            = interface.payload_role
      mac             = interface.mac
      peer_address    = sort(tolist(aws_ec2_transit_gateway_connect_peer.aws[key].bgp_transit_gateway_addresses))[0]
      expected_routes = [var.aws_vpc_cidr]
    }
  }
  timeout_seconds       = var.aws_bgp_convergence_timeout_seconds
  poll_interval_seconds = var.aws_bgp_poll_interval_seconds
  depends_on            = [xcsh_bgp.aws_tgw]
}

output "aws_tgw_connect_status" {
  description = "Non-sensitive SMSv2 contract, runtime, and BGP convergence summary."
  value = var.enable_aws && var.enable_aws_tgw_connect ? {
    contract_id      = data.xcsh_smsv2_contract.aws[0].contract_id
    contract_version = data.xcsh_smsv2_contract.aws[0].contract_version
    api_release      = data.xcsh_smsv2_contract.aws[0].api_release_tag
    telemetry_schema = data.xcsh_smsv2_contract.aws[0].telemetry_schema_id
    runtime_healthy  = data.xcsh_smsv2_aws_runtime.aws[0].healthy
    interface_count  = length(data.xcsh_smsv2_aws_runtime.aws[0].interfaces)
    bgp_converged    = data.xcsh_site_bgp_status.aws[0].converged
    peer_count       = length(data.xcsh_site_bgp_status.aws[0].peers)
  } : null
}

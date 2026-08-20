# AWS resources are deliberately driven only by values carried in the verified
# telemetry contract. No endpoint, ASN, MTU, interface order, or route is derived.

locals {
  tags = {
    Name      = "${var.name_prefix}-tgw"
    ManagedBy = "terraform"
  }
}

resource "aws_ec2_transit_gateway" "this" {
  amazon_side_asn                 = var.amazon_side_asn
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = local.tags
}

resource "aws_ec2_transit_gateway_vpc_attachment" "transport" {
  subnet_ids                                      = var.transport_subnet_ids
  transit_gateway_id                              = aws_ec2_transit_gateway.this.id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  vpc_id                                          = var.vpc_id

  tags = merge(local.tags, { Name = "${var.name_prefix}-tgw-transport" })
}

resource "aws_ec2_transit_gateway_route_table" "this" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-tgw-rt" })
}

resource "aws_ec2_transit_gateway_route_table_association" "transport" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.transport.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this.id
}

resource "aws_ec2_transit_gateway_connect" "this" {
  protocol                                        = "gre"
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  transit_gateway_id                              = aws_ec2_transit_gateway.this.id
  transport_attachment_id                         = aws_ec2_transit_gateway_vpc_attachment.transport.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-tgw-connect" })
}

resource "aws_ec2_transit_gateway_route_table_propagation" "connect" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_connect.this.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this.id
}

resource "aws_ec2_transit_gateway_connect_peer" "this" {
  for_each = var.interfaces

  bgp_asn                       = each.value.bgp_local_asn
  inside_cidr_blocks            = [each.value.inside_cidr_block]
  peer_address                  = each.value.gre_peer_address
  transit_gateway_attachment_id = aws_ec2_transit_gateway_connect.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-tgw-peer-${each.value.interface_order}" })

  lifecycle {
    precondition {
      condition     = each.value.bgp_remote_asn == var.amazon_side_asn
      error_message = "Each telemetry-attested BGP remote ASN must equal amazon_side_asn."
    }

    precondition {
      condition     = each.value.effective_mtu > 0
      error_message = "Each telemetry-attested effective MTU must be positive."
    }

    precondition {
      condition     = can(cidrhost("${each.value.gre_peer_address}/32", 0)) && can(cidrhost(each.value.inside_cidr_block, 0))
      error_message = "Each telemetry-attested GRE peer address and inside CIDR block must be valid IPv4 values."
    }
  }
}

resource "aws_ec2_transit_gateway_route" "this" {
  for_each = var.routes

  destination_cidr_block         = each.key
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_connect_peer.this[each.value].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this.id
}

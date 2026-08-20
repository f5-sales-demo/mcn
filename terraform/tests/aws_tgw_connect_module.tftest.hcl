# The module models all TGW values from inputs; it never derives CE runtime state.

mock_provider "aws" {}

run "plans_ordered_gre_bgp_peers_and_routes" {
  command = plan

  module {
    source = "./modules/aws-tgw-connect"
  }

  variables {
    vpc_id               = "vpc-plan-test"
    amazon_side_asn      = 64520
    transport_subnet_ids = ["subnet-plan-a", "subnet-plan-b"]
    name_prefix          = "mcn-plan-test"
    interfaces = {
      ce01 = {
        interface_order   = 1
        gre_peer_address  = "192.0.2.10"
        inside_cidr_block = "169.254.100.0/29"
        bgp_local_asn     = 65010
        bgp_remote_asn    = 64520
        effective_mtu     = 1500
      }
      ce02 = {
        interface_order   = 2
        gre_peer_address  = "192.0.2.11"
        inside_cidr_block = "169.254.101.0/29"
        bgp_local_asn     = 65011
        bgp_remote_asn    = 64520
        effective_mtu     = 1500
      }
    }
    routes = {
      "10.60.0.0/16" = "ce01"
      "10.61.0.0/16" = "ce02"
    }
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_connect_peer.this) == 2
    error_message = "Each telemetry-attested CE interface must plan exactly one Connect peer."
  }

  assert {
    condition     = tonumber(aws_ec2_transit_gateway_connect_peer.this["ce01"].bgp_asn) == 65010
    error_message = "The Connect peer must use the telemetry-attested CE local ASN."
  }

  assert {
    condition     = aws_ec2_transit_gateway_route.this["10.60.0.0/16"].destination_cidr_block == "10.60.0.0/16"
    error_message = "Each telemetry-attested route must be represented deterministically."
  }
}

run "rejects_unattested_remote_asn" {
  command = plan

  module {
    source = "./modules/aws-tgw-connect"
  }

  variables {
    vpc_id               = "vpc-plan-test"
    amazon_side_asn      = 64520
    transport_subnet_ids = ["subnet-plan-a"]
    name_prefix          = "mcn-plan-test"
    interfaces = {
      ce01 = {
        interface_order   = 1
        gre_peer_address  = "192.0.2.10"
        inside_cidr_block = "169.254.100.0/29"
        bgp_local_asn     = 65010
        bgp_remote_asn    = 64521
        effective_mtu     = 1500
      }
    }
    routes = { "10.60.0.0/16" = "ce01" }
  }

  expect_failures = [aws_ec2_transit_gateway_connect_peer.this]
}

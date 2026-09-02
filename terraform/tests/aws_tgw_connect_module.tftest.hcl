# The module owns only AWS TGW transport. F5 runtime identity and BGP state are
# intentionally absent and are composed by the root module.
mock_provider "aws" {}

run "plans_two_role_connect_attachments_and_explicit_routing" {
  command = plan

  module {
    source = "./modules/aws-tgw-connect"
  }

  variables {
    vpc_id                     = "vpc-plan-test"
    amazon_side_asn            = 64520
    transit_gateway_cidr_block = "100.64.0.0/24"
    transport_subnet_ids       = ["subnet-plan-a", "subnet-plan-b", "subnet-plan-c"]
    name_prefix                = "mcn-plan-test"
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_connect.role) == 2
    error_message = "The module must create exactly the SLO and SLI Connect attachments."
  }

  assert {
    condition     = toset(keys(aws_ec2_transit_gateway_connect.role)) == toset(["slo", "sli"])
    error_message = "Connect attachments must be keyed strictly by the SLO and SLI roles."
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_vpc_attachment.transport.subnet_ids) == 3
    error_message = "The transport attachment must use exactly three availability-zone subnets."
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table_association.connect) == 2 && length(aws_ec2_transit_gateway_route_table_propagation.connect) == 2
    error_message = "Each role attachment must have an explicit association and propagation."
  }

  assert {
    condition     = aws_ec2_transit_gateway.this.default_route_table_association == "disable" && aws_ec2_transit_gateway.this.default_route_table_propagation == "disable"
    error_message = "The TGW must use explicit route-table associations and propagations only."
  }
}

run "rejects_duplicate_or_incomplete_transport_subnets" {
  command = plan

  module {
    source = "./modules/aws-tgw-connect"
  }

  variables {
    vpc_id                     = "vpc-plan-test"
    amazon_side_asn            = 64520
    transit_gateway_cidr_block = "100.64.0.0/24"
    transport_subnet_ids       = ["subnet-plan-a", "subnet-plan-a", "subnet-plan-b"]
    name_prefix                = "mcn-plan-test"
  }

  expect_failures = [var.transport_subnet_ids]
}

run "rejects_invalid_amazon_side_asn" {
  command = plan

  module {
    source = "./modules/aws-tgw-connect"
  }

  variables {
    vpc_id                     = "vpc-plan-test"
    amazon_side_asn            = 0
    transit_gateway_cidr_block = "100.64.0.0/24"
    transport_subnet_ids       = ["subnet-plan-a", "subnet-plan-b", "subnet-plan-c"]
    name_prefix                = "mcn-plan-test"
  }

  expect_failures = [var.amazon_side_asn]
}

run "rejects_invalid_tgw_cidr" {
  command = plan

  module {
    source = "./modules/aws-tgw-connect"
  }

  variables {
    vpc_id                     = "vpc-plan-test"
    amazon_side_asn            = 64520
    transit_gateway_cidr_block = "not-a-cidr"
    transport_subnet_ids       = ["subnet-plan-a", "subnet-plan-b", "subnet-plan-c"]
    name_prefix                = "mcn-plan-test"
  }

  expect_failures = [var.transit_gateway_cidr_block]
}

# Three independent one-node sites share two role-based TGW Connect
# attachments, with one SLO and one SLI peer per site.
mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "libvirt" {}
mock_provider "random" {}

mock_provider "aws" {
  mock_resource "aws_ec2_transit_gateway_connect_peer" {
    defaults = {
      bgp_peer_address              = "169.254.100.2"
      bgp_transit_gateway_addresses = ["169.254.100.1"]
      transit_gateway_address       = "100.64.0.1"
    }
  }
}

mock_provider "xcsh" {}

override_data {
  override_during = plan
  target          = data.xcsh_smsv2_contract.aws[0]
  values = {
    contract_id         = "f5xc-ce-automation/v3"
    contract_version    = "6.1.0"
    api_release_tag     = "v6.1.1"
    api_release_commit  = "2b27355ac9bf4683d3a${"321f7d6388676f756c2f5"}"
    telemetry_schema_id = "f5xc-smsv2-aws-tgw-telemetry/v2"
    capabilities = {
      aws_ce_create  = "available"
      runtime_status = "available"
      site_upgrade   = "available"
      tgw_connect    = "available"
    }
    f5xc_authorities = ["smsv2_configuration", "runtime_health", "bgp_peers", "bgp_routes", "simplified_routes", "site_upgrade_observation"]
    aws_authorities  = ["eni", "transit_gateway", "transit_gateway_connect", "gre_endpoints", "bgp_inside_cidrs", "autonomous_system_numbers"]
  }
}

override_resource {
  target = aws_network_interface.slo[0]
  values = { mac_address = "02:00:00:00:00:01", private_ip = "10.150.1.10" }
}
override_resource {
  target = aws_network_interface.slo[1]
  values = { mac_address = "02:00:00:00:00:02", private_ip = "10.150.2.10" }
}
override_resource {
  target = aws_network_interface.slo[2]
  values = { mac_address = "02:00:00:00:00:03", private_ip = "10.150.3.10" }
}
override_resource {
  target = aws_network_interface.sli[0]
  values = { mac_address = "02:00:00:00:01:01", private_ip = "10.150.11.10" }
}
override_resource {
  target = aws_network_interface.sli[1]
  values = { mac_address = "02:00:00:00:01:02", private_ip = "10.150.12.10" }
}
override_resource {
  target = aws_network_interface.sli[2]
  values = { mac_address = "02:00:00:00:01:03", private_ip = "10.150.13.10" }
}

override_data {
  target = data.xcsh_smsv2_aws_runtime.aws["01"]
  values = {
    healthy = true
    interfaces = {
      node_01_slo = { node = "mcn-ce-ha-aws-ap-northeast-1-01", role = "slo", mac = "02:00:00:00:00:01", interface_name = "site-01-eth0", mtu = 1500, healthy = true }
      node_01_sli = { node = "mcn-ce-ha-aws-ap-northeast-1-01", role = "sli", mac = "02:00:00:00:01:01", interface_name = "site-01-eth1", mtu = 1500, healthy = true }
    }
  }
}
override_data {
  target = data.xcsh_smsv2_aws_runtime.aws["02"]
  values = {
    healthy = true
    interfaces = {
      node_02_slo = { node = "mcn-ce-ha-aws-ap-northeast-1-02", role = "slo", mac = "02:00:00:00:00:02", interface_name = "site-02-eth0", mtu = 1500, healthy = true }
      node_02_sli = { node = "mcn-ce-ha-aws-ap-northeast-1-02", role = "sli", mac = "02:00:00:00:01:02", interface_name = "site-02-eth1", mtu = 1500, healthy = true }
    }
  }
}
override_data {
  target = data.xcsh_smsv2_aws_runtime.aws["03"]
  values = {
    healthy = true
    interfaces = {
      node_03_slo = { node = "mcn-ce-ha-aws-ap-northeast-1-03", role = "slo", mac = "02:00:00:00:00:03", interface_name = "site-03-eth0", mtu = 1500, healthy = true }
      node_03_sli = { node = "mcn-ce-ha-aws-ap-northeast-1-03", role = "sli", mac = "02:00:00:00:01:03", interface_name = "site-03-eth1", mtu = 1500, healthy = true }
    }
  }
}

variables {
  lb_domain              = "mcn-ce-ha.example.com"
  aws_lb_domain          = "aws.mcn-ce-ha.example.com"
  origin_ip              = "203.0.113.10"
  deployer               = "tester"
  enable_bastion         = false
  ssh_public_key         = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
  aws_ce_ami_id          = "ami-0123456789abcdef0"
  aws_vip                = "198.51.100.10"
  enable_aws             = true
  enable_aws_tgw_connect = true
}

run "plans_three_sites_six_peers_and_workload_attachment" {
  command = plan

  assert {
    condition     = length(xcsh_securemesh_site_v2.aws) == 3 && alltrue([for site in values(xcsh_securemesh_site_v2.aws) : length(site.aws.not_managed.node_list) == 1])
    error_message = "The topology must contain three independent one-node sites."
  }
  assert {
    condition     = length(module.aws_tgw_connect) == 1 && length(module.aws_tgw_connect[0].connect_attachment_ids) == 2
    error_message = "The topology must contain exactly two role-based Connect attachments."
  }
  assert {
    condition     = length(aws_ec2_transit_gateway_connect_peer.aws) == 6 && length(xcsh_external_connector.aws_tgw) == 6
    error_message = "All six MAC-bound interfaces must own an AWS Connect peer and XC external connector."
  }
  assert {
    condition     = length(xcsh_bgp.aws_tgw) == 3 && alltrue([for bgp in values(xcsh_bgp.aws_tgw) : length(bgp.peers) == 2])
    error_message = "Every site must own one two-peer BGP object."
  }
  assert {
    condition     = length(data.xcsh_smsv2_aws_runtime.aws) == 3 && length(data.xcsh_site_bgp_status.aws) == 3
    error_message = "Runtime and BGP convergence must be observed independently for all sites."
  }
  assert {
    condition     = length(aws_ec2_transit_gateway_vpc_attachment.workload) == 1 && length(aws_ec2_transit_gateway_route_table_association.workload) == 1 && length(aws_ec2_transit_gateway_route_table_propagation.workload) == 1
    error_message = "The workload VPC must have explicit TGW attachment, association, and propagation."
  }
  assert {
    condition     = anytrue([for route in aws_route_table.workload[0].route : route.cidr_block == "198.51.100.10/32"])
    error_message = "The workload route table must send the external VIP through the TGW."
  }
}

# Clean-break provider-v7 orchestration: AWS supplies transport facts while F5
# XC supplies the immutable contract, MAC-bound runtime state, BGP, and routes.
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

# Stable AWS-owned identities are shared across every matrix row. Provider mocks
# still execute schema validation, so each logical node/role pair needs a valid,
# distinct ENI MAC even when the contract gate is expected to reject the plan.
override_resource {
  target = aws_network_interface.slo[0]
  values = { mac_address = "02:00:00:00:00:01", private_ip = "10.100.1.10" }
}
override_resource {
  target = aws_network_interface.slo[1]
  values = { mac_address = "02:00:00:00:00:02", private_ip = "10.100.2.10" }
}
override_resource {
  target = aws_network_interface.slo[2]
  values = { mac_address = "02:00:00:00:00:03", private_ip = "10.100.3.10" }
}
override_resource {
  target = aws_network_interface.sli[0]
  values = { mac_address = "02:00:00:00:01:01", private_ip = "10.100.11.10" }
}
override_resource {
  target = aws_network_interface.sli[1]
  values = { mac_address = "02:00:00:00:01:02", private_ip = "10.100.12.10" }
}
override_resource {
  target = aws_network_interface.sli[2]
  values = { mac_address = "02:00:00:00:01:03", private_ip = "10.100.13.10" }
}

override_data {
  target = data.xcsh_smsv2_aws_runtime.aws[0]
  values = {
    healthy = true
    interfaces = {
      node_01_slo = { node = "node-01", role = "slo", mac = "02:00:00:00:00:01", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-01-eth0-0", mtu = 1500, healthy = true }
      node_02_slo = { node = "node-02", role = "slo", mac = "02:00:00:00:00:02", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-02-eth0-0", mtu = 1500, healthy = true }
      node_03_slo = { node = "node-03", role = "slo", mac = "02:00:00:00:00:03", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-03-eth0-0", mtu = 1500, healthy = true }
      node_01_sli = { node = "node-01", role = "sli", mac = "02:00:00:00:01:01", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-01-eth1-0", mtu = 1500, healthy = true }
      node_02_sli = { node = "node-02", role = "sli", mac = "02:00:00:00:01:02", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-02-eth1-0", mtu = 1500, healthy = true }
      node_03_sli = { node = "node-03", role = "sli", mac = "02:00:00:00:01:03", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-03-eth1-0", mtu = 1500, healthy = true }
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
  enable_aws             = true
  aws_ce_count           = 3
  enable_aws_tgw_connect = true
}

run "plans_mac_bound_tgw_connect_and_convergence_gates" {
  command = plan

  override_resource {
    target = aws_network_interface.slo[0]
    values = { mac_address = "02:00:00:00:00:01", private_ip = "10.100.1.10" }
  }
  override_resource {
    target = aws_network_interface.slo[1]
    values = { mac_address = "02:00:00:00:00:02", private_ip = "10.100.2.10" }
  }
  override_resource {
    target = aws_network_interface.slo[2]
    values = { mac_address = "02:00:00:00:00:03", private_ip = "10.100.3.10" }
  }
  override_resource {
    target = aws_network_interface.sli[0]
    values = { mac_address = "02:00:00:00:01:01", private_ip = "10.100.11.10" }
  }
  override_resource {
    target = aws_network_interface.sli[1]
    values = { mac_address = "02:00:00:00:01:02", private_ip = "10.100.12.10" }
  }
  override_resource {
    target = aws_network_interface.sli[2]
    values = { mac_address = "02:00:00:00:01:03", private_ip = "10.100.13.10" }
  }

  override_data {
    override_during = plan
    target          = data.xcsh_smsv2_contract.aws[0]
    values = {
      contract_id      = "f5xc-ce-automation/v3"
      contract_version = "6.0.0"
      api_release_tag  = "v6.0.2"
      api_release_commit = join("", [
        "8a48ca67ad",
        "9fc23174d0",
        "86c0d63a27",
        "83e531044b",
      ])
      telemetry_schema_id = "f5xc-smsv2-aws-tgw-telemetry/v2"
      capabilities = {
        aws_ce_create  = "available"
        runtime_status = "available"
        tgw_connect    = "available"
      }
      f5xc_authorities = ["smsv2_configuration", "runtime_health", "bgp_peers", "bgp_routes", "simplified_routes"]
      aws_authorities  = ["eni", "transit_gateway", "transit_gateway_connect", "gre_endpoints", "bgp_inside_cidrs", "autonomous_system_numbers"]
    }
  }

  override_data {
    override_during = plan
    target          = data.xcsh_smsv2_aws_runtime.aws[0]
    values = {
      healthy = true
      interfaces = {
        node_01_slo = { node = "node-01", role = "slo", mac = "02:00:00:00:00:01", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-01-eth0-0", mtu = 1500, healthy = true }
        node_02_slo = { node = "node-02", role = "slo", mac = "02:00:00:00:00:02", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-02-eth0-0", mtu = 1500, healthy = true }
        node_03_slo = { node = "node-03", role = "slo", mac = "02:00:00:00:00:03", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-03-eth0-0", mtu = 1500, healthy = true }
        node_01_sli = { node = "node-01", role = "sli", mac = "02:00:00:00:01:01", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-01-eth1-0", mtu = 1500, healthy = true }
        node_02_sli = { node = "node-02", role = "sli", mac = "02:00:00:00:01:02", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-02-eth1-0", mtu = 1500, healthy = true }
        node_03_sli = { node = "node-03", role = "sli", mac = "02:00:00:00:01:03", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-03-eth1-0", mtu = 1500, healthy = true }
      }
    }
  }

  override_data {
    override_during = plan
    target          = data.xcsh_site_bgp_status.aws[0]
    values = {
      converged = true
      peers = {
        node_01_slo = { node = "node-01", role = "slo", mac = "02:00:00:00:00:01", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-01-eth0-0", peer_address = "169.254.100.1", state = "ESTABLISHED", established = true, received_prefix_count = 1, advertised_prefix_count = 1, state_changed_at = "2026-09-01T00:00:00Z" }
        node_02_slo = { node = "node-02", role = "slo", mac = "02:00:00:00:00:02", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-02-eth0-0", peer_address = "169.254.100.9", state = "ESTABLISHED", established = true, received_prefix_count = 1, advertised_prefix_count = 1, state_changed_at = "2026-09-01T00:00:00Z" }
        node_03_slo = { node = "node-03", role = "slo", mac = "02:00:00:00:00:03", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-03-eth0-0", peer_address = "169.254.100.17", state = "ESTABLISHED", established = true, received_prefix_count = 1, advertised_prefix_count = 1, state_changed_at = "2026-09-01T00:00:00Z" }
        node_01_sli = { node = "node-01", role = "sli", mac = "02:00:00:00:01:01", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-01-eth1-0", peer_address = "169.254.100.25", state = "ESTABLISHED", established = true, received_prefix_count = 1, advertised_prefix_count = 1, state_changed_at = "2026-09-01T00:00:00Z" }
        node_02_sli = { node = "node-02", role = "sli", mac = "02:00:00:00:01:02", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-02-eth1-0", peer_address = "169.254.100.33", state = "ESTABLISHED", established = true, received_prefix_count = 1, advertised_prefix_count = 1, state_changed_at = "2026-09-01T00:00:00Z" }
        node_03_sli = { node = "node-03", role = "sli", mac = "02:00:00:00:01:03", interface_name = "ves-io-securemesh-site-v2-aws-site-network-node-03-eth1-0", peer_address = "169.254.100.41", state = "ESTABLISHED", established = true, received_prefix_count = 1, advertised_prefix_count = 1, state_changed_at = "2026-09-01T00:00:00Z" }
      }
      bgp_routes_json = "{}"
      slo_routes_json = "{}"
      sli_routes_json = "{}"
    }
  }

  assert {
    condition     = length(module.aws_tgw_connect) == 1 && length(module.aws_tgw_connect[0].connect_attachment_ids) == 2
    error_message = "A successful contract gate must plan exactly two role-keyed Connect attachments."
  }
  assert {
    condition     = length(aws_ec2_transit_gateway_connect_peer.aws) == 6
    error_message = "Each of the six physical MAC-bound interfaces must own one AWS Connect peer."
  }
  assert {
    condition     = length(xcsh_external_connector.aws_tgw) == 6 && length(xcsh_bgp.aws_tgw) == 2
    error_message = "The F5 graph must plan six external connectors and two role-keyed BGP objects."
  }
  assert {
    condition = alltrue([
      for binding in values(local.aws_smsv2_bindings) : binding.payload_role == "sli"
    ])
    error_message = "Every GRE connector must place payload in Site Local Inside, as required by the live F5 API."
  }
  assert {
    condition     = length(terraform_data.aws_tgw_contract_gate) == 1 && length(terraform_data.aws_tgw_runtime_gate) == 1
    error_message = "The available path must retain both the immutable contract and six-interface runtime gates."
  }
  assert {
    condition     = length(data.xcsh_site_bgp_status.aws) == 1
    error_message = "The available path must retain the v7 BGP convergence graph."
  }
}

run "rejects_published_unavailable_capabilities" {
  command = plan

  override_data {
    target = data.xcsh_smsv2_contract.aws[0]
    values = {
      contract_id         = "f5xc-ce-automation/v3"
      contract_version    = "6.0.0"
      api_release_tag     = "v6.0.2"
      api_release_commit  = join("", ["8a48ca67ad", "9fc23174d0", "86c0d63a27", "83e531044b"])
      telemetry_schema_id = "f5xc-smsv2-aws-tgw-telemetry/v2"
      capabilities = {
        aws_ce_create  = "unavailable"
        runtime_status = "unavailable"
        tgw_connect    = "unavailable"
      }
      f5xc_authorities = ["smsv2_configuration", "runtime_health", "bgp_peers", "bgp_routes", "simplified_routes"]
      aws_authorities  = ["eni", "transit_gateway", "transit_gateway_connect", "gre_endpoints", "bgp_inside_cidrs", "autonomous_system_numbers"]
    }
  }

  expect_failures = [terraform_data.aws_tgw_contract_gate]
}

run "rejects_wrong_contract_identity" {
  command = plan

  override_data {
    target = data.xcsh_smsv2_contract.aws[0]
    values = {
      contract_id         = "f5xc-ce-automation/v2"
      contract_version    = "5.0.1"
      api_release_tag     = "v5.0.1"
      api_release_commit  = "wrong-contract-commit"
      telemetry_schema_id = "f5xc-smsv2-aws-tgw-telemetry/v1"
      capabilities = {
        aws_ce_create  = "available"
        runtime_status = "available"
        tgw_connect    = "available"
      }
      f5xc_authorities = ["smsv2_configuration", "runtime_health", "bgp_peers", "bgp_routes", "simplified_routes"]
      aws_authorities  = ["eni", "transit_gateway", "transit_gateway_connect", "gre_endpoints", "bgp_inside_cidrs", "autonomous_system_numbers"]
    }
  }

  expect_failures = [terraform_data.aws_tgw_contract_gate]
}

run "rejects_wrong_authority_sets" {
  command = plan

  override_data {
    target = data.xcsh_smsv2_contract.aws[0]
    values = {
      contract_id         = "f5xc-ce-automation/v3"
      contract_version    = "6.0.0"
      api_release_tag     = "v6.0.2"
      api_release_commit  = join("", ["8a48ca67ad", "9fc23174d0", "86c0d63a27", "83e531044b"])
      telemetry_schema_id = "f5xc-smsv2-aws-tgw-telemetry/v2"
      capabilities = {
        aws_ce_create  = "available"
        runtime_status = "available"
        tgw_connect    = "available"
      }
      f5xc_authorities = ["smsv2_configuration", "runtime_health", "bgp_peers", "bgp_routes"]
      aws_authorities  = ["eni", "transit_gateway", "transit_gateway_connect", "gre_endpoints", "bgp_inside_cidrs"]
    }
  }

  expect_failures = [terraform_data.aws_tgw_contract_gate]
}

run "rejects_non_exact_capability_map" {
  command = plan

  override_data {
    target = data.xcsh_smsv2_contract.aws[0]
    values = {
      contract_id         = "f5xc-ce-automation/v3"
      contract_version    = "6.0.0"
      api_release_tag     = "v6.0.2"
      api_release_commit  = join("", ["8a48ca67ad", "9fc23174d0", "86c0d63a27", "83e531044b"])
      telemetry_schema_id = "f5xc-smsv2-aws-tgw-telemetry/v2"
      capabilities = {
        aws_ce_create         = "available"
        runtime_status        = "available"
        tgw_connect           = "available"
        unexpected_capability = "available"
      }
      f5xc_authorities = ["smsv2_configuration", "runtime_health", "bgp_peers", "bgp_routes", "simplified_routes"]
      aws_authorities  = ["eni", "transit_gateway", "transit_gateway_connect", "gre_endpoints", "bgp_inside_cidrs", "autonomous_system_numbers"]
    }
  }

  expect_failures = [terraform_data.aws_tgw_contract_gate]
}

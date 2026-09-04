# Test suite for AWS Customer Edge site, VPC, EC2 instances, and XC resources.

mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "xcsh" {}
mock_provider "aws" {}
mock_provider "libvirt" {}

override_resource {
  override_during = plan
  target          = xcsh_token.ce
  values          = { uid = "test-registration-token" }
}

override_data {
  target = data.xcsh_site_registration.aws["0"]
  values = { found = false }
}

override_data {
  target = data.xcsh_site_registration.aws["1"]
  values = { found = false }
}

override_data {
  target = data.xcsh_site_registration.aws["2"]
  values = { found = false }
}

variables {
  site_prefix            = null
  lb_name                = null
  origin_pool_name       = null
  route_server_name      = null
  bastion_name           = null
  client_vm_name         = null
  region_short           = null
  resource_group_name    = null
  lb_domain              = "mcn-ce-ha.f5-sales-demo.com"
  aws_lb_domain          = "aws.mcn-ce-ha.f5-sales-demo.com"
  origin_ip              = "203.0.113.10"
  deployer               = "tester"
  ssh_public_key         = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
  xc_app_namespace       = "multi-cloud-networking"
  aws_ce_ami_id          = "ami-0123456789abcdef0"
  enable_aws             = true
  enable_aws_tgw_connect = false
}

run "aws_site_and_resources" {
  command = plan

  variables {
    aws_ce_count = 3
  }

  assert {
    condition     = output.aws_lb_domain == "aws.mcn-ce-ha.f5-sales-demo.com"
    error_message = "AWS HTTP Load Balancer domain should be aws.mcn-ce-ha.f5-sales-demo.com."
  }

  assert {
    condition     = output.aws_loadbalancer_name == "mcn-ce-ha-aws-lb"
    error_message = "AWS HTTP Load Balancer name should be mcn-ce-ha-aws-lb."
  }

  assert {
    condition     = output.aws_origin_pool_name == "mcn-ce-ha-aws-pool"
    error_message = "AWS Origin Pool name should be mcn-ce-ha-aws-pool."
  }

  assert {
    condition     = output.aws_vip == "10.150.0.10"
    error_message = "AWS VIP should be 10.150.0.10."
  }

  assert {
    condition     = aws_instance.ce[0].ami == "ami-0123456789abcdef0"
    error_message = "AWS CE instances must use the explicitly approved AMI, not a dynamic discovery result."
  }

  assert {
    condition     = aws_instance.ce[0].root_block_device[0].volume_size == 100
    error_message = "AWS CE instances must plan a 100-GiB root volume."
  }

  assert {
    condition = alltrue([
      for required in [
        "ClusterType: ce",
        "ClusterName: aws-site",
        "MauriceEndpoint: https://register.ves.volterra.io",
        "MauricePrivateEndpoint: https://register-tls.ves.volterra.io",
        "CertifiedHardwareEndpoint: https://vesio.blob.core.windows.net/releases/certified-hardware/aws.yml",
        "CloudProvider: disabled",
        "path: /var/home/admin/.ssh/authorized_keys",
      ] : strcontains(aws_instance.ce[0].user_data, required)
    ])
    error_message = "AWS CE cloud-init must contain the complete VPM registration and operator-access contract."
  }

  assert {
    condition     = length(terraform_data.aws_ce_instances) == 1
    error_message = "The AWS SMSv2 site lifecycle must track the CE instance identities."
  }

  assert {
    condition     = length(data.xcsh_site_registration.aws) == 3 && length(xcsh_registration_approval.aws) == 0
    error_message = "AWS must look up all three runtime registrations and defer approval until they are found."
  }

  assert {
    condition = alltrue([
      for node in xcsh_securemesh_site_v2.aws[0].aws.not_managed.node_list :
      node.interface_list[0].ethernet_interface.device == "eth0" &&
      node.interface_list[1].ethernet_interface.device == "eth1"
    ])
    error_message = "Every AWS SMSv2 node must map SLO to eth0 and SLI to eth1, as required by the live API contract."
  }

  assert {
    condition = [
      for node in xcsh_securemesh_site_v2.aws[0].aws.not_managed.node_list : node.hostname
    ] == ["mcn-ce-ha-aws-ce-1", "mcn-ce-ha-aws-ce-2", "mcn-ce-ha-aws-ce-3"]
    error_message = "AWS SMSv2 nodes must use the canonical hostnames configured during CE registration."
  }
}

run "aws_requires_an_explicit_ami_before_any_instance_plan" {
  command = plan

  variables {
    aws_ce_ami_id = null
  }

  expect_failures = [aws_instance.ce]
}

run "aws_disabled_plans_no_aws_resources" {
  command = plan

  variables {
    enable_aws             = false
    enable_aws_tgw_connect = false
  }

  assert {
    condition     = length(aws_vpc.aws) == 0
    error_message = "With enable_aws = false, no AWS VPC should be created."
  }

  assert {
    condition     = length(aws_instance.ce) == 0
    error_message = "With enable_aws = false, no AWS EC2 instances should be created."
  }

  assert {
    condition     = length(xcsh_securemesh_site_v2.aws) == 0
    error_message = "With enable_aws = false, no AWS SecureMesh site should be created."
  }

  assert {
    condition     = length(xcsh_http_loadbalancer.aws) == 0
    error_message = "With enable_aws = false, no AWS HTTP load balancer should be created."
  }

  assert {
    condition     = output.aws_vpc_id == null
    error_message = "With enable_aws = false, aws_vpc_id output must be null."
  }
}

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

override_resource {
  override_during = plan
  target          = xcsh_token.aws["01"]
  values          = { uid = "test-site-token-01" }
}

override_resource {
  override_during = plan
  target          = xcsh_token.aws["02"]
  values          = { uid = "test-site-token-02" }
}

override_resource {
  override_during = plan
  target          = xcsh_token.aws["03"]
  values          = { uid = "test-site-token-03" }
}

override_resource {
  override_during = plan
  target          = xcsh_site_cloud_init.aws["01"]
  values          = { cloud_init_config = "#cloud-config\nwrite_files:\n  - path: /etc/vpm/user_data\n    content: |\n      token: {{ .token }}\n" }
}

override_resource {
  override_during = plan
  target          = xcsh_site_cloud_init.aws["02"]
  values          = { cloud_init_config = "#cloud-config\nwrite_files:\n  - path: /etc/vpm/user_data\n    content: |\n      token: {{ .token }}\n" }
}

override_resource {
  override_during = plan
  target          = xcsh_site_cloud_init.aws["03"]
  values          = { cloud_init_config = "#cloud-config\nwrite_files:\n  - path: /etc/vpm/user_data\n    content: |\n      token: {{ .token }}\n" }
}

override_data {
  target = data.xcsh_site_registration.aws["01"]
  values = { found = false }
}

override_data {
  target = data.xcsh_site_registration.aws["02"]
  values = { found = false }
}

override_data {
  target = data.xcsh_site_registration.aws["03"]
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
  aws_ssh_public_key     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwsSpecificKeyMaterialOnlyForTests aws-plan-test-only"
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
    condition     = length(data.azuread_client_config.current) == 0 && length(data.azuread_user.current) == 0
    error_message = "An explicit deployer must keep AWS-only planning from reading Azure AD."
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
    condition     = output.aws_vip == "198.51.100.10"
    error_message = "AWS VIP should be the external documentation address 198.51.100.10."
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
    condition     = aws_key_pair.ce[0].public_key == var.aws_ssh_public_key
    error_message = "AWS must support an AWS-only operator key without changing Azure VM access."
  }

  assert {
    condition     = length(xcsh_securemesh_site_v2.aws) == 3 && length(xcsh_site_cloud_init.aws) == 3 && length(xcsh_token.aws) == 3
    error_message = "AWS must plan three independent sites and one site-scoped bootstrap per site."
  }

  assert {
    condition = alltrue([
      for key, token in xcsh_token.aws : token.type == 1 && token.site_name == local.aws_sites[key].name
    ])
    error_message = "Every AWS registration credential must be a JWT token bound to its exact Secure Mesh Site v2 name."
  }

  assert {
    condition = length(data.xcsh_site_registration.aws) == 3 && length(xcsh_registration_approval.aws) == 0

    error_message = "AWS must look up all three runtime registrations and defer approval until they are found."
  }

  assert {
    condition = alltrue([
      for bootstrap in values(xcsh_site_cloud_init.aws) : bootstrap.provider_ref == "aws"
    ])
    error_message = "AWS site cloud-init issuance must use the lowercase provider identifier expected by the live API."
  }

  assert {
    condition = alltrue([
      for config in values(local.aws_site_cloud_init) :
      strcontains(nonsensitive(config), "token: test-site-token-") &&
      !strcontains(nonsensitive(config), "{{ .token }}") &&
      !strcontains(nonsensitive(config), "{{ .Token }}")
    ])
    error_message = "Every AWS CE must receive resolved cloud-init with no token template placeholder."
  }

  assert {
    condition = alltrue([
      for site in values(xcsh_securemesh_site_v2.aws) :
      site.aws.not_managed.node_list[0].interface_list[0].ethernet_interface.device == "eth0" &&
      site.aws.not_managed.node_list[0].interface_list[1].ethernet_interface.device == "eth1"
    ])
    error_message = "Every AWS SMSv2 node must map SLO to eth0 and SLI to eth1, as required by the live API contract."
  }

  assert {
    condition = toset([
      for site in values(xcsh_securemesh_site_v2.aws) : site.name
    ]) == toset(["mcn-ce-ha-aws-ap-northeast-1-01", "mcn-ce-ha-aws-ap-northeast-1-02", "mcn-ce-ha-aws-ap-northeast-1-03"])
    error_message = "AWS must use the three canonical independent site names."
  }

  assert {
    condition     = length(aws_vpc.workload) == 1 && length(aws_instance.workload) == 1 && length(aws_security_group.workload) == 1
    error_message = "AWS must plan a dedicated workload VPC and SSM client."
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
    condition     = length(xcsh_securemesh_site_v2.aws) == 0 && length(aws_vpc.workload) == 0
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

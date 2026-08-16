# Test suite for AWS Customer Edge site, VPC, EC2 instances, and XC resources.

mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "xcsh" {
  mock_resource "xcsh_site_cloud_init" {
    defaults = {
      cloud_init_config = "#cloud-config\nwrite_files: []\n"
    }
  }
}
mock_provider "aws" {}
mock_provider "libvirt" {}
mock_provider "random" {
  mock_resource "random_password" {
    defaults = { result = "MockSitePassword-42!" }
  }
}

variables {
  subscription_id     = uuidv5("dns", "example.com")
  component           = "mcn-ce-ha"
  site_prefix         = null
  lb_name             = null
  origin_pool_name    = null
  route_server_name   = null
  bastion_name        = null
  client_vm_name      = null
  region_short        = null
  resource_group_name = null
  lb_domain           = "mcn-ce-ha.f5-sales-demo.com"
  aws_lb_domain       = "aws.mcn-ce-ha.f5-sales-demo.com"
  origin_ip           = "203.0.113.10"
  deployer            = "tester"
  ssh_public_key      = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
  xc_app_namespace    = "multi-cloud-networking"
  enable_aws          = true
}

run "aws_site_and_resources" {
  command = plan

  override_resource {
    target          = aws_network_interface.slo["01"]
    override_during = plan
    values          = { mac_address = "02:00:00:00:00:01" }
  }

  override_resource {
    target          = aws_network_interface.slo["02"]
    override_during = plan
    values          = { mac_address = "02:00:00:00:00:02" }
  }

  override_resource {
    target          = aws_network_interface.slo["03"]
    override_during = plan
    values          = { mac_address = "02:00:00:00:00:03" }
  }

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
    condition     = output.aws_vip == "198.51.100.10"
    error_message = "AWS VIP must be outside the VPC CIDR."
  }

  assert {
    condition = (
      xcsh_http_loadbalancer.aws[0].advertise_custom.advertise_where[0].virtual_site_with_vip.ip == "198.51.100.10" &&
      xcsh_http_loadbalancer.aws[0].advertise_custom.advertise_where[0].virtual_site_with_vip.network == "SITE_NETWORK_SPECIFIED_VIP_OUTSIDE" &&
      xcsh_http_loadbalancer.aws[0].advertise_custom.advertise_where[0].virtual_site_with_vip.virtual_site.name == "mcn-ce-ha-aws-vsite"
    )
    error_message = "The AWS load balancer must advertise aws_vip through its AWS virtual site."
  }

  assert {
    condition     = length(output.aws_site_names) == 3 && length(toset(values(output.aws_site_names))) == 3
    error_message = "AWS must create three independently named Secure Mesh sites."
  }

  assert {
    condition = (
      length(random_password.site_console_admin_aws) == 3 &&
      alltrue([
        for site in values(xcsh_securemesh_site_v2.aws) :
        site.admin_user_credentials.ssh_key == var.ssh_public_key &&
        startswith(site.admin_user_credentials.admin_password.clear_secret_info.url, "string:///")
      ])
    )
    error_message = "Every AWS site must configure one independently generated admin credential through the supported secret URL."
  }

  assert {
    condition = alltrue([
      for key, site in xcsh_securemesh_site_v2.aws :
      length(site.aws.not_managed.node_list) == 1 &&
      site.aws.not_managed.node_list[0].hostname == "mcn-ce-ha-aws-${key}" &&
      site.aws.not_managed.node_list[0].interface_list[0].name == "eth0" &&
      site.aws.not_managed.node_list[0].interface_list[0].ethernet_interface.mac == aws_network_interface.slo[key].mac_address
    ])
    error_message = "Every AWS site must model its own CE node and eth0 SLO interface."
  }

  assert {
    condition = alltrue([
      for node in values(aws_instance.ce) :
      node.root_block_device[0].volume_size >= 80 &&
      node.root_block_device[0].volume_type == "gp3" &&
      node.root_block_device[0].encrypted
    ])
    error_message = "Every AWS Customer Edge must have an encrypted gp3 root disk of at least 80 GB."
  }

  assert {
    condition     = length(aws_vpc_route_server_endpoint.aws) == 2 && length(aws_vpc_route_server_peer.ce) == 3
    error_message = "AWS Route Server must expose two endpoints and peer with every CE."
  }

  assert {
    condition = length(xcsh_site_cloud_init.aws) == 3 && alltrue([
      for key, issued in xcsh_site_cloud_init.aws :
      issued.provider_ref == "aws" && issued.site_name == "mcn-ce-ha-aws-${key}"
    ])
    error_message = "Every independent AWS site must issue its own site-scoped node cloud-init."
  }

  assert {
    condition     = length(aws_vpc_route_server_propagation.aws) == 2 && length(aws_instance.test_client) == 1
    error_message = "AWS must propagate learned routes and provide a test client."
  }

  assert {
    condition = anytrue([
      for rule in aws_security_group.ce[0].ingress :
      rule.protocol == "tcp" &&
      rule.from_port == 80 &&
      rule.to_port == 80 &&
      contains(rule.cidr_blocks, var.aws_vpc_cidr)
    ])
    error_message = "The AWS CE security group must admit test-client HTTP traffic to the advertised VIP."
  }

  assert {
    condition = (
      length(aws_iam_role_policy_attachment.test_client_ssm) == 1 &&
      aws_instance.test_client[0].iam_instance_profile == aws_iam_instance_profile.test_client[0].name
    )
    error_message = "The AWS test client must support keyless Systems Manager Run Command verification."
  }

}

run "aws_vip_inside_vpc_is_rejected" {
  command = plan

  variables {
    aws_vip = "10.150.0.10"
  }

  expect_failures = [check.aws_vip_outside_vpc_cidr]
}

run "aws_undersized_root_volume_is_rejected" {
  command = plan

  variables {
    aws_root_volume_size_gb = 79
  }

  expect_failures = [var.aws_root_volume_size_gb]
}

run "aws_disabled_plans_no_aws_resources" {
  command = plan

  variables {
    enable_aws = false
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
    condition     = length(aws_iam_instance_profile.test_client) == 0
    error_message = "With enable_aws = false, no AWS test-client execution role should be created."
  }

  assert {
    condition     = length(xcsh_securemesh_site_v2.aws) == 0
    error_message = "With enable_aws = false, no AWS SecureMesh site should be created."
  }

  assert {
    condition     = length(xcsh_site_cloud_init.aws) == 0
    error_message = "With enable_aws = false, no AWS node credential should be issued."
  }

  assert {
    condition     = length(xcsh_http_loadbalancer.aws) == 0
    error_message = "With enable_aws = false, no AWS HTTP load balancer should be created."
  }

  assert {
    condition     = output.aws_vpc_id == null && output.aws_vip == null
    error_message = "With enable_aws = false, AWS resource and VIP outputs must be null."
  }
}

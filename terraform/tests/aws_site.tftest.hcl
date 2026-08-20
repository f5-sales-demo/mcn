# Test suite for AWS Customer Edge site, VPC, EC2 instances, and XC resources.

mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "xcsh" {}
mock_provider "aws" {}
mock_provider "libvirt" {}

variables {
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
  aws_ce_ami_id       = "ami-0123456789abcdef0"
  enable_aws          = true
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

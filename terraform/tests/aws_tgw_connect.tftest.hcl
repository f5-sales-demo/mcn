# The current immutable SMSv2 release permits AWS CE configuration only. It
# explicitly withholds runtime telemetry and TGW Connect, so Terraform must
# fail a requested Connect/BGP deployment before it can plan AWS mutations.

mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "xcsh" {}
mock_provider "aws" {}
mock_provider "libvirt" {}

variables {
  lb_domain      = "mcn-ce-ha.example.com"
  origin_ip      = "203.0.113.10"
  deployer       = "tester"
  enable_bastion = false
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
}

run "tgw_connect_is_rejected_before_aws_mutation" {
  command = plan

  variables {
    enable_aws_tgw_connect = true
  }

  expect_failures = [var.enable_aws_tgw_connect]
}
